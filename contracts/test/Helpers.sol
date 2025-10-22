// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AboreanVault} from "../src/Vault.sol";
import {MockWETH, MockPENGU} from "./mocks/Mocks.sol";

/**
 * @title TestHelpers
 * @notice Shared utilities and helper functions for vault tests
 */
library TestHelpers {
    /**
     * @notice Calculate expected shares for a deposit
     * @dev Uses ERC4626 formula: shares = assets * totalSupply / totalAssets
     * @param assets Amount of assets to deposit
     * @param totalSupply Current total supply of shares
     * @param totalAssets Current total assets in vault
     * @return Expected shares to receive
     */
    function calculateExpectedShares(
        uint256 assets,
        uint256 totalSupply,
        uint256 totalAssets
    ) internal pure returns (uint256) {
        if (totalSupply == 0 || totalAssets == 0) {
            return assets; // First deposit: 1:1 ratio
        }
        return (assets * totalSupply) / totalAssets;
    }

    /**
     * @notice Calculate share price
     * @param totalAssets Total assets in vault
     * @param totalSupply Total supply of shares
     * @return Share price in 18 decimals
     */
    function calculateSharePrice(
        uint256 totalAssets,
        uint256 totalSupply
    ) internal pure returns (uint256) {
        if (totalSupply == 0) return 0;
        return (totalAssets * 1e18) / totalSupply;
    }

    /**
     * @notice Calculate price impact of a swap
     * @param inputAmount Amount of input token
     * @param outputAmount Amount of output token received
     * @param expectedRate Expected exchange rate
     * @return Price impact in basis points
     */
    function calculatePriceImpact(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 expectedRate
    ) internal pure returns (uint256) {
        uint256 expectedOutput = inputAmount * expectedRate;
        if (expectedOutput == 0) return 0;

        if (outputAmount >= expectedOutput) {
            return 0; // No negative impact
        }

        uint256 difference = expectedOutput - outputAmount;
        return (difference * 10000) / expectedOutput; // Return in bps
    }

    /**
     * @notice Format WETH amount for display
     */
    function formatWETH(uint256 amount) internal pure returns (string memory) {
        return string(abi.encodePacked(uintToString(amount / 1e18), " WETH"));
    }

    /**
     * @notice Convert uint to string
     */
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    /**
     * @notice Assert values are approximately equal (within percentage tolerance)
     * @param actual Actual value
     * @param expected Expected value
     * @param toleranceBps Tolerance in basis points (e.g., 100 = 1%)
     */
    function assertApproxEqBps(
        uint256 actual,
        uint256 expected,
        uint256 toleranceBps,
        string memory message
    ) internal pure {
        if (expected == 0) {
            require(actual == 0, message);
            return;
        }

        uint256 diff = actual > expected ? actual - expected : expected - actual;
        uint256 maxDiff = (expected * toleranceBps) / 10000;

        require(diff <= maxDiff, message);
    }
}

/**
 * @title BaseVaultTest
 * @notice Base test contract with common setup
 */
abstract contract BaseVaultTest is Test {
    using TestHelpers for *;

    AboreanVault public vault;
    MockWETH public weth;
    MockPENGU public pengu;

    address public admin = address(0x1);
    address public alice = address(0x11);
    address public bob = address(0x22);
    address public charlie = address(0x33);

    /**
     * @notice Fund user with ETH and wrap to WETH
     */
    function fundUser(address user, uint256 ethAmount) internal {
        vm.deal(user, ethAmount);
        vm.prank(user);
        weth.deposit{value: ethAmount}();
    }

    /**
     * @notice Deposit into vault on behalf of user
     */
    function depositAsUser(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        weth.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /**
     * @notice Get user's share of total assets
     */
    function getUserAssetValue(address user) internal view returns (uint256) {
        uint256 userShares = vault.balanceOf(user);
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply == 0) return 0;
        return (userShares * totalAssets) / totalSupply;
    }

    /**
     * @notice Get vault state for debugging
     * @dev Override in child contracts to add console logging
     */
    function getVaultState() internal view returns (
        uint256 totalSupply,
        uint256 totalAssets,
        uint256 nftTokenId,
        uint256 sharePrice
    ) {
        totalSupply = vault.totalSupply();
        totalAssets = vault.totalAssets();
        nftTokenId = vault.nftTokenId();

        if (totalSupply > 0) {
            sharePrice = TestHelpers.calculateSharePrice(totalAssets, totalSupply);
        }
    }

    /**
     * @notice Get user balances for debugging
     * @dev Override in child contracts to add console logging
     */
    function getUserBalances(address user) internal view returns (
        uint256 wethBalance,
        uint256 vaultShares,
        uint256 assetValue
    ) {
        wethBalance = weth.balanceOf(user);
        vaultShares = vault.balanceOf(user);
        assetValue = getUserAssetValue(user);
    }
}

/**
 * @title FuzzHelpers
 * @notice Helpers for fuzz testing
 */
library FuzzHelpers {
    /**
     * @notice Bound deposit amount to valid range
     */
    function boundDeposit(uint256 amount, uint256 minDeposit) internal pure returns (uint256) {
        return bound(amount, minDeposit, 10000 ether);
    }

    /**
     * @notice Bound price to reasonable range
     */
    function boundPrice(int64 price) internal pure returns (int64) {
        return int64(bound(int256(price), 1e6, 1e14)); // $0.01 to $1M
    }

    /**
     * @notice Bound confidence to valid range (< 1% of price)
     */
    function boundConfidence(uint64 conf, int64 price) internal pure returns (uint64) {
        uint64 maxConf = uint64(price) / 101; // Just under 1%
        return uint64(bound(conf, 0, maxConf));
    }

    /**
     * @notice Bound tick to valid range
     */
    function boundTick(int24 tick) internal pure returns (int24) {
        return int24(bound(int256(tick), -887272, 887272));
    }

    /**
     * @notice Bound sqrtPriceX96 to valid range
     */
    function boundSqrtPrice(uint160 sqrtPrice) internal pure returns (uint160) {
        return uint160(bound(sqrtPrice, 1e15, type(uint128).max));
    }

    // Helper to use bound() from Test contract
    function bound(uint256 x, uint256 min, uint256 max) private pure returns (uint256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }

    function bound(int256 x, int256 min, int256 max) private pure returns (int256) {
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}

/**
 * @title MockDataHelpers
 * @notice Helpers for creating mock data
 */
library MockDataHelpers {
    /**
     * @notice Get realistic WETH price (in Pyth format)
     */
    function getRealisticWETHPrice() internal pure returns (int64 price, uint64 conf, int32 expo) {
        price = 400000000000; // $4000
        conf = 10000000;      // Low confidence
        expo = -8;            // Price * 10^-8
    }

    /**
     * @notice Get realistic PENGU price (in Pyth format)
     */
    function getRealisticPENGUPrice() internal pure returns (int64 price, uint64 conf, int32 expo) {
        price = 200000000;    // $2
        conf = 1000000;       // Low confidence
        expo = -8;
    }

    /**
     * @notice Get realistic pool sqrtPriceX96
     * @dev Based on 1 WETH = 2000 PENGU
     */
    function getRealisticPoolPrice() internal pure returns (uint160 sqrtPriceX96, int24 tick) {
        sqrtPriceX96 = 3540000000000000000000; // sqrt(2000) * 2^96
        tick = 0; // Approximate tick
    }

    /**
     * @notice Get valid tick range for CL200 pool
     */
    function getValidTickRange() internal pure returns (int24 tickLower, int24 tickUpper) {
        tickLower = -2000; // Multiple of 200
        tickUpper = 2000;  // Multiple of 200
    }
}
