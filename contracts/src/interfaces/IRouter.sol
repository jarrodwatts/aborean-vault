// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title Aborean Router Interface
/// @notice Interface for swapping tokens through Aborean pools
interface IRouter {

    /// @notice Struct containing route information for swaps
    struct Route {
        address from;
        address to;
        bool stable;      // true for stable pools, false for volatile
        address factory;  // address(0) to use default factory
    }

    /// @notice Returns the factory registry address
    function factoryRegistry() external view returns (address);

    /// @notice Returns the default factory address
    function defaultFactory() external view returns (address);

    /// @notice Returns the voter contract address
    function voter() external view returns (address);

    /// @notice Returns the WETH contract address
    function weth() external view returns (address);

    /// @notice Sorts two token addresses
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return token0 The smaller address
    /// @return token1 The larger address
    function sortTokens(address tokenA, address tokenB)
        external
        pure
        returns (address token0, address token1);

    /// @notice Returns the pool address for a given pair
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable True for stable pool, false for volatile
    /// @param _factory Factory address (use address(0) for default)
    /// @return pool The pool address
    function poolFor(address tokenA, address tokenB, bool stable, address _factory)
        external
        view
        returns (address pool);

    /// @notice Gets the reserves for a pool
    /// @param tokenA First token
    /// @param tokenB Second token
    /// @param stable True for stable pool, false for volatile
    /// @param _factory Factory address (use address(0) for default)
    /// @return reserveA Reserve of tokenA
    /// @return reserveB Reserve of tokenB
    function getReserves(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory
    ) external view returns (uint256 reserveA, uint256 reserveB);

    /// @notice Performs chained getAmountOut calculations on any number of pools
    /// @param amountIn Amount of input tokens
    /// @param routes Array of Route structs defining the swap path
    /// @return amounts Array of amounts for each step of the swap
    function getAmountsOut(uint256 amountIn, Route[] memory routes)
        external
        view
        returns (uint256[] memory amounts);

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens to receive
    /// @param routes Array of Route structs defining the swap path
    /// @param to Recipient of the output tokens
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps an exact amount of ETH for as many output tokens as possible
    /// @param amountOutMin The minimum amount of output tokens to receive
    /// @param routes Array of Route structs defining the swap path (must start with WETH)
    /// @param to Recipient of the output tokens
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactETHForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /// @notice Swaps an exact amount of tokens for as much ETH as possible
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of ETH to receive
    /// @param routes Array of Route structs defining the swap path (must end with WETH)
    /// @param to Recipient of the ETH
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
