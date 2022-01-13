pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface DikasteiraInterface {}

contract GovernorDelegatorStorage {
    /// @notice Administrator for this contract
    address public admin;

    /// @notice Pending administrator for this contract
    address public pendingAdmin;

    /// @notice Active brains of Governor
    address public implementation;
}


/**
 * @title Storage for Governor Bravo Delegate
 * @notice For future upgrades, do not change GovernorBravoDelegateStorageV1. Create a new
 * contract which implements GovernorBravoDelegateStorageV1 and following the naming convention
 * GovernorBravoDelegateStorageVX.
 */
contract GovernorDelegateStorageV1 is GovernorDelegatorStorage {
	DikasteiraInterface public dika;
	TimelockInterface public timelock;

	/// How often (in blocks) new public referenda are launched.
	uint public LAUNCH_PERIOD;

	/// How often (in blocks) to check for new votes.
	uint public VOTING_PERIOD;

	/// The minimum amount to be used as a deposit for a public referendum proposal.
	uint public MINIMUM_DEPOSIT = 10e18;

	uint public initialProposalId = 0;

	uint public proposalCount = 0;

	mapping (uint => Proposal) public proposals;
	mapping (address => Deposit) public deposits;

	/// latest proposal id of a proposer address
	mapping (address => uint) public latestProposalIds;
	
	/// @notice Receipts of ballots for the entire set of voters of a proposal id
	/// proposalId => voter address => receipt
	mapping (uint => mapping(address => Receipt)) receipts;

	struct Deposit {
		address from;
		uint amount;
		uint proposalId;
		bool proposerDeposit;
	}

	/// 0.1x votes, unlocked.
	/// 1x votes, locked for an enactment period following a successful vote.
	/// 2x votes, locked for 2x enactment periods following a successful vote.
	/// 3x votes, locked for 4x...
	/// 4x votes, locked for 8x...
	/// 5x votes, locked for 16x...
	/// 6x votes, locked for 32x...
	enum Conviction {
		None,
		Locked1x,
		Locked2x,
		Locked3x,
		Locked4x,
		Locked5x,
		Locked6x
	}

	/// @notice Ballot receipt record for a voter
	struct Receipt {
		uint proposalId;
		
		/// @notice Whether or not a vote has been cast
		bool hasVoted;

		/// @notice Whether or not the voter supports the proposal or abstains
		uint8 support;

		/// @notice The deposit attached to the vote
		uint deposit;

		/// @notice conviction based lockup period
		Conviction conviction;
	}


	struct Proposal {
				/// @notice Unique id for looking up a proposal
			uint id;

			/// @notice Creator of the proposal
			address proposer;

			/// @notice the ordered list of target addresses for calls to be made
			address[] targets;

			/// @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
			uint[] values;

			/// @notice The ordered list of function signatures to be called
			string[] signatures;

			/// @notice The ordered list of calldata to be passed to each call
			bytes[] calldatas;

			/// @notice Seconding signals agreement with a proposal, moves it higher on the proposal queue, and requires a matching deposit to the original.
			uint seconders;

			/// @notice Conviction votes for this referendum
			uint forVotes;

			/// @notice Conviction votes against this referendum
			uint againstVotes;

			/// @notice Flag marking whether the proposal has been canceled
			bool canceled;

			/// @notice Flag marking whether the proposal has been executed
			bool executed;

			bool isReferendum;

			/// @notice Receipts of ballots for the entire set of voters
			// mapping (address => Receipt) receipts;
		}

		enum ProposalState {
			Proposed, // proposed to be seconded into being tabled into a referendum vote
			Tabled, // put up for a referendum vote
			Started, // proposal voting period has started
			Passed, // referendum has passed Adaptive Quorum Biasing
			NotPassed, // not passed
			Cancelled, // proposer cancelled it
			Executed, // on chain executed
			Vetoed // council has vetoed the referendum
		}

		struct Vote {
			bool aye;
			Conviction conviction;
		}

		/// Standard: A standard vote, one-way (approve or reject) with a given amount of conviction.
		struct StandardAccountVote {
			Vote vote;
			uint balance;
		}

		/// Split:  A split vote with balances given for both ways, and with no conviction, useful for parachains when voting.
		struct SplitAccountVote {
			uint aye;
			uint nay;
		}

		enum AccountVote {
			Standard,
			Split
		}

		enum VoteThreshold {
			SuperMajorityApprove, 
			SuperMajorityAgainst,
			SimpleMajority
		}
}

contract GovernorEvents is GovernorDelegateStorageV1 {
		event NewImplementation(address oldImplmentation, address newImplmentation);
		/// @notice Emitted when pendingAdmin is changed
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /// @notice Emitted when pendingAdmin is accepted, which means admin is updated
    event NewAdmin(address oldAdmin, address newAdmin);

		/// A motion has been proposed by a public account.
		event Proposed(uint proposal_index, uint deposit);
		/// A public proposal has been tabled for referendum vote.
		event Tabled ( uint proposal_index, uint deposit, address[] depositors);
		/// An external proposal has been tabled.
		event ExternalTabled();
		/// A referendum has begun.
		event Started (uint ref_index, VoteThreshold threshold);
		/// A proposal has been approved by referendum.
		event Passed (uint ref_index);
		/// A proposal has been rejected by referendum.
		event NotPassed (uint ref_index);
		/// A referendum has been cancelled.
		event Cancelled (uint ref_index);
		/// A proposal has been enacted.
		event Executed (uint ref_index);
		/// An account has delegated their vote to another account.
		event Delegated (address who, address target);
		/// An account has cancelled a previous delegation operation.
		event Undelegated (address account);
		/// An external proposal has been vetoed.
		event Vetoed (address who, string proposal_hash, uint until);
		/// A proposal's preimage was noted, and the deposit taken.
		event PreimageNoted (string proposal_hash, address who, uint deposit );
		/// A proposal preimage was removed and used (the deposit was returned).
		event PreimageUsed (string proposal_hash, address provider, uint deposit);
		/// A proposal could not be executed because its preimage was invalid.
		event PreimageInvalid (string proposal_hash, uint ref_index);
		/// A proposal could not be executed because its preimage was missing.
		event PreimageMissing (string proposal_hash, uint ref_index);
		/// A registered preimage was removed and the deposit collected by the reaper.
		event PreimageReaped (
			string proposal_hash,
			address provider,
			uint deposit,
			address reaper
		);
		/// A proposal_hash has been blacklisted permanently.
		event Blacklisted (string proposal_hash);
		/// An account has voted in a referendum
		event Voted (address voter, uint ref_index, AccountVote vote);
		/// An account has secconded a proposal
		event Seconded ( address seconder, uint prop_index );
   
}

contract GovernorDelegateStorageV2 is GovernorDelegateStorageV1 {
    /// @notice Stores the expiration of account whitelist status as a timestamp
    mapping (address => uint) public whitelistAccountExpirations;

    /// @notice Address which manages whitelisted proposals and whitelist accounts
    address public whitelistGuardian;
}

interface TimelockInterface {
    function delay() external view returns (uint);
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external;
    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory);
}