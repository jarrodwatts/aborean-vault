// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Concentrated Liquidity Pool interface for Aborean/Aerodrome Slipstream
/// @notice Interface for Slipstream CL pools (different from standard Uniswap V3)
interface ICLPool {
    /// @notice The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas
    /// @dev Pool price can be estimated from sqrtPriceX96 via: price = (sqrtPriceX96 / 2^96)^2
    /// @return sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value
    /// @return tick The current tick of the pool, i.e. according to the last tick transition that was run
    /// @return observationIndex The index of the last oracle observation that was written
    /// @return observationCardinality The current maximum number of observations stored in the pool
    /// @return observationCardinalityNext The next maximum number of observations, to be updated when the observation
    /// @return feeProtocol The protocol fee for both tokens of the pool
    /// NOTE: Slipstream pools do NOT return `unlocked` (unlike standard Uniswap V3)
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol
        );

    /// @notice The pool tick spacing
    /// @dev Ticks can only be used at multiples of this value, minimum of 1 and always positive
    /// e.g. a tickSpacing of 3 means ticks can be initialized every 3rd tick, i.e., ..., -6, -3, 0, 3, 6, ...
    /// This value is an int24 to avoid casting even though it is always positive.
    /// @return The tick spacing
    function tickSpacing() external view returns (int24);

    /// @notice The pool's fee in hundredths of a bip, i.e. 1e-6
    /// @return The fee
    function fee() external view returns (uint24);

    /// @notice The first of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address
    /// @return The token contract address
    function token1() external view returns (address);
}
