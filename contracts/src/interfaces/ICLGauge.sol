// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title Concentrated Liquidity Gauge Interface
/// @notice Handles staking of CL position NFTs and reward distribution
interface ICLGauge {

    /// @notice Emitted when an NFT position is deposited (staked)
    event Deposit(address indexed user, uint256 indexed tokenId, uint128 liquidityToStake);

    /// @notice Emitted when an NFT position is withdrawn (unstaked)
    event Withdraw(address indexed user, uint256 indexed tokenId, uint128 liquidityToStake);

    /// @notice Emitted when rewards are claimed
    event ClaimRewards(address indexed from, uint256 amount);

    /// @notice Emitted when trading fees are claimed
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);

    /// @notice The position manager (NFT contract)
    function nft() external view returns (address);

    /// @notice The pool associated with this gauge
    function pool() external view returns (address);

    /// @notice The reward token (ABX)
    function rewardToken() external view returns (address);

    /// @notice The fees voting reward contract
    function feesVotingReward() external view returns (address);

    /// @notice Deposits (stakes) an NFT position
    /// @dev Caller must own the NFT and approve this gauge
    /// @param tokenId The ID of the NFT to stake
    function deposit(uint256 tokenId) external;

    /// @notice Withdraws (unstakes) an NFT position
    /// @dev Automatically claims pending rewards and collects fees
    /// @param tokenId The ID of the NFT to unstake
    function withdraw(uint256 tokenId) external;

    /// @notice Claims rewards for a specific staked position
    /// @param tokenId The ID of the staked NFT
    function getReward(uint256 tokenId) external;

    /// @notice Claims rewards for all staked positions of an account
    /// @dev Can only be called by the Voter contract
    /// @param account The account to claim rewards for
    function getReward(address account) external;

    /// @notice Returns the earned rewards for a specific position
    /// @param account The account that owns the position
    /// @param tokenId The token ID of the position
    /// @return The amount of rewards earned
    function earned(address account, uint256 tokenId) external view returns (uint256);

    /// @notice Returns all staked token IDs for a depositor
    /// @param depositor The address of the depositor
    /// @return staked Array of staked token IDs
    function stakedValues(address depositor) external view returns (uint256[] memory staked);

    /// @notice Returns a staked token ID at a specific index
    /// @param depositor The address of the depositor
    /// @param index The index in the staked tokens array
    /// @return The token ID at that index
    function stakedByIndex(address depositor, uint256 index) external view returns (uint256);

    /// @notice Checks if a depositor has a specific token staked
    /// @param depositor The address of the depositor
    /// @param tokenId The token ID to check
    /// @return True if the token is staked by the depositor
    function stakedContains(address depositor, uint256 tokenId) external view returns (bool);

    /// @notice Returns the number of staked positions for a depositor
    /// @param depositor The address of the depositor
    /// @return The number of staked positions
    function stakedLength(address depositor) external view returns (uint256);

    /// @notice Whether the gauge is for a pool or not
    function isPool() external view returns (bool);

    /// @notice Token0 of the pool
    function token0() external view returns (address);

    /// @notice Token1 of the pool
    function token1() external view returns (address);

    /// @notice Tick spacing of the pool
    function tickSpacing() external view returns (int24);

    /// @notice Accumulated fees in token0
    function fees0() external view returns (uint256);

    /// @notice Accumulated fees in token1
    function fees1() external view returns (uint256);
}
