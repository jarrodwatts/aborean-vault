// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AboreanVault} from "../../src/Vault.sol";
import {MockPositionManager} from "./Mocks.sol";

/**
 * @title MockVault
 * @notice Test version of AboreanVault that works with mock contracts
 * @dev Overrides _getPositionAmounts() to use mock's stored amounts instead of Uniswap math
 */
contract MockVault is AboreanVault {
    constructor(
        address _weth,
        address _pengu,
        address _positionManager,
        address _gauge,
        address _router,
        address _pool,
        address _pyth
    ) AboreanVault(_weth, _pengu, _positionManager, _gauge, _router, _pool, _pyth) {}

    /**
     * @notice Override to get amounts from mock instead of calculating from liquidity
     * @dev MockPositionManager stores actual deposited amounts
     */
    function _getPositionAmounts() internal view override returns (uint256 wethAmount, uint256 penguAmount) {
        if (nftTokenId == 0) return (0, 0);

        // Get stored amounts from mock position manager
        return MockPositionManager(address(positionManager)).getDepositedAmounts(nftTokenId);
    }
}
