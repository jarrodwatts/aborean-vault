// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title Voting Escrow Interface
/// @notice Interface for locking ABX tokens to create veABX NFTs
interface IVotingEscrow {
    /// @notice Deposit types for lock operations
    enum DepositType {
        DEPOSIT_FOR_TYPE,
        CREATE_LOCK_TYPE,
        INCREASE_LOCK_AMOUNT,
        INCREASE_UNLOCK_TIME,
        MERGE_TYPE
    }

    /// @notice Emitted when tokens are deposited or lock parameters are updated
    event Deposit(
        address indexed provider,
        uint256 indexed tokenId,
        DepositType indexed depositType,
        uint256 value,
        uint256 locktime,
        uint256 ts
    );

    /// @notice Emitted when a lock is converted to permanent
    event LockPermanent(address indexed _owner, uint256 indexed _tokenId, uint256 amount, uint256 _ts);

    /// @notice Emitted when two veNFTs are merged
    event Merge(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint256 _amountFrom,
        uint256 _amountTo,
        uint256 _amountFinal,
        uint256 _locktime,
        uint256 _ts
    );

    /// @notice Create a new lock
    /// @param _value Amount of tokens to lock
    /// @param _lockDuration Duration to lock tokens (in seconds, rounded down to weeks)
    /// @return tokenId The ID of the newly minted veNFT
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256);

    /// @notice Add more tokens to an existing lock
    /// @param _tokenId The veNFT token ID
    /// @param _value Amount of additional tokens to lock
    function increaseAmount(uint256 _tokenId, uint256 _value) external;

    /// @notice Extend the unlock time of an existing lock
    /// @param _tokenId The veNFT token ID
    /// @param _lockDuration Additional duration to extend lock (in seconds)
    function increaseUnlockTime(uint256 _tokenId, uint256 _lockDuration) external;

    /// @notice Convert a time-locked veNFT to a permanent lock
    /// @param _tokenId The veNFT token ID
    function lockPermanent(uint256 _tokenId) external;

    /// @notice Merge two veNFTs into one
    /// @param _from Source veNFT to merge (will be burned)
    /// @param _to Destination veNFT to merge into
    function merge(uint256 _from, uint256 _to) external;

    /// @notice Get the voting power of a veNFT
    /// @param _tokenId The veNFT token ID
    /// @return Voting power of the veNFT
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256);

    /// @notice Check if an address is approved or owner of a veNFT
    /// @param _spender Address to check
    /// @param _tokenId The veNFT token ID
    /// @return True if approved or owner
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool);

    /// @notice Approve an address to manage a veNFT
    /// @param _approved Address to approve
    /// @param _tokenId The veNFT token ID
    function approve(address _approved, uint256 _tokenId) external;
}

