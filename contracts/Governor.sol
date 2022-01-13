pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./GovernorInterfaces.sol";

/**
 * 1. Anyone can propose with a deposit
 * 2. All proposals enter pool to be seconded during a Voting_Period
 * 3. At the end of each Voting_Period, the top seconded proposal gets Tabled into a referendum for Conviction voting
 * 4. At the end of a Voting_Period for a refereundum, the Adaptive Quroum Biasing calculates whether it passed or not.
 * 5. If passed, council members get one last Veto_Period to veto with a super majority vote.
 * 6. If vetoed, the referendum gets scrapped
 * 7. If not, the referendum gets put into Timelock to be executed after some time.

 */

contract GovernorV1 is GovernorDelegateStorageV2, GovernorEvents {
    /// @notice The name of this contract
    string public constant name = "GovernorV1";

    /// @notice The maximum number of actions that can be included in a proposal
    uint public constant proposalMaxOperations = 10; // 10 actions

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    /**
      * @notice Used to initialize the contract during delegator contructor
      * @param timelock_ The address of the Timelockod
      * @param dika_ The address of Dika token
      */
    function initialize(address timelock_, address dika_) public {
        require(address(timelock) == address(0), "Governor::initialize: can only initialize once");
        require(msg.sender == admin, "Governor::initialize: admin only");
        require(timelock_ != address(0), "Governor::initialize: invalid timelock address");
        require(dika_ != address(0), "Governor::initialize: invalid dika address");

        timelock = TimelockInterface(timelock_);
        dika = DikasteiraInterface(dika_);
        initialProposalId = 1;
    }

    /**
      * @notice Function used to propose a new proposal. Sender must have delegates above the proposal threshold
      * @param targets Target addresses for proposal calls
      * @param values Eth values for proposal calls
      * @param signatures Function signatures for proposal calls
      * @param calldatas Calldatas for proposal calls
      * @param description String description of the proposal
      * @return Proposal id of new proposal
      */
    function propose(
        address[] memory targets,
        uint[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) public payable returns (uint) {
        // Reject proposals before initiating as Governor
        require(initialProposalId != 0, "Governor::propose: Dikasteira not active");
        // Allow addresses above proposal threshold and whitelisted addresses to propose
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "Governor::propose: proposal function information arity mismatch");
        require(targets.length != 0, "Governor::propose: must provide actions");
        require(targets.length <= proposalMaxOperations, "Governor::propose: too many actions");
        require(msg.value >= MINIMUM_DEPOSIT, "Governor::propose: minimum deposit not met");

        uint latestProposalId = latestProposalIds[msg.sender];
        if (latestProposalId != 0) {
          ProposalState proposersLatestProposalState = state(latestProposalId);
          require(proposersLatestProposalState != ProposalState.Started, "Governor::propose: one live proposal per proposer, found an already started proposal");
          require(proposersLatestProposalState != ProposalState.Tabled, "Governor::propose: one live proposal per proposer, found an already tabled proposal");
        }

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            seconders: 0,
            forVotes: 0,
            againstVotes: 0,
            canceled: false,
            executed: false,
            isReferendum: false
        });

        proposals[newProposal.id] = newProposal;
        latestProposalIds[newProposal.proposer] = newProposal.id;
        deposits[newProposal.proposer] = Deposit({
            from: newProposal.proposer,
            amount: msg.value,
            proposalId: newProposal.id,
            proposerDeposit: true
        });

        emit Proposed(newProposal.id, msg.value);
        return newProposal.id;
    }

    /**
      * @notice Gets actions of a proposal
      * @param proposalId the id of the proposal
      */
    function getActions(uint proposalId) external view returns (address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    /**
      * @notice Gets the receipt for a voter on a given proposal
      * @param proposalId the id of proposal
      * @param voter The address of the voter
      * @return The voting receipt
      */
    function getReceipt(uint proposalId, address voter) external view returns (Receipt memory) {
        return receipts[proposalId][voter];
    }

    /**
      * @notice Gets the state of a proposal
      * @param proposalId The id of the proposal
      * @return Proposal state
      */
    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > initialProposalId, "Governor::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Cancelled;
        } else if (proposal.isReferendum) {
            return ProposalState.Tabled;
        } else if (!proposal.isReferendum) {
            return ProposalState.Started;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < 100) { // TODO: Adaptive Quorum Biasing (no fixed quorum)
            return ProposalState.NotPassed;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
            return ProposalState.Proposed;
        }
    }

    /**
    /**
      * @notice Initiate the Governor contract
      * @dev Admin only. Sets initial proposal id which initiates the contract, ensuring a continuous proposal id count
      * @param governorAlpha The address for the Governor to continue the proposal id count from
      */
    function _initiate(address governorAlpha) external {
        require(msg.sender == admin, "Governor::_initiate: admin only");
        require(initialProposalId == 0, "Governor::_initiate: can only initiate once");

        initialProposalId = proposalCount;
        timelock.acceptAdmin();
    }

    /**
      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      */
    function _setPendingAdmin(address newPendingAdmin) external {
        // Check caller = admin
        require(msg.sender == admin, "Governor:_setPendingAdmin: admin only");

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;

        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
    }

    /**
      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      * @dev Admin function for pending admin to accept role and update admin
      */
    function _acceptAdmin() external {
        // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
        require(msg.sender == pendingAdmin && msg.sender != address(0), "Governor:_acceptAdmin: pending admin only");

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        admin = pendingAdmin;

        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
    }

    function getChainIdInternal() internal view returns (uint) {
        uint chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}