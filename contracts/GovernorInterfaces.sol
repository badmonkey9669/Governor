pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

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
		struct Referendum {}

    struct Proposal {}

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

interface CompInterface {
    function getPriorVotes(address account, uint blockNumber) external view returns (uint96);
}

interface GovernorAlpha {
    /// @notice The total number of proposals
    function proposalCount() external returns (uint);
}