// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title Voter Interface
/// @notice Interface for voting on pool emissions using veABX NFTs
interface IVoter {
    /// @notice Emitted when a veNFT votes for pools
    event Voted(
        address indexed voter,
        address indexed pool,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );

    /// @notice Vote for pool emissions using a veNFT
    /// @param _tokenId The veNFT token ID to vote with
    /// @param _poolVote Array of pool addresses to vote for
    /// @param _weights Array of weights to allocate to each pool (must sum to total voting power)
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;

    /// @notice Reset votes for a veNFT
    /// @param _tokenId The veNFT token ID
    function reset(uint256 _tokenId) external;

    /// @notice Get the gauge address for a pool
    /// @param _pool Pool address
    /// @return Gauge address
    function gauges(address _pool) external view returns (address);

    /// @notice Check if a gauge is alive (active)
    /// @param _gauge Gauge address
    /// @return True if gauge is alive
    function isAlive(address _gauge) external view returns (bool);
}

