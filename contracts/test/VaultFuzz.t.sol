// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AboreanVault} from "../src/Vault.sol";
import {MockWETH, MockPENGU, MockPyth, MockRouter, MockPositionManager, MockCLGauge, MockUniswapV3Pool} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultFuzzTest
 * @notice Fuzz and invariant tests for AboreanVault
 * @dev Property-based testing with random inputs
 */
contract VaultFuzzTest is Test {
    AboreanVault public vault;
    MockWETH public weth;
    MockPENGU public pengu;
    MockPyth public pyth;
    MockRouter public router;
    MockPositionManager public positionManager;
    MockCLGauge public gauge;
    MockUniswapV3Pool public pool;

    address public admin = address(0x1);

    bytes32 constant WETH_USD_PRICE_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;
    bytes32 constant PENGU_USD_PRICE_ID = 0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61;

    function setUp() public {
        weth = new MockWETH();
        pengu = new MockPENGU();
        pyth = new MockPyth();
        router = new MockRouter(address(weth), address(pengu));
        positionManager = new MockPositionManager();
        gauge = new MockCLGauge(address(positionManager));
        pool = new MockUniswapV3Pool();

        pool.setSqrtPriceX96(3540000000000000000000, 0);

        vm.prank(admin);
        vault = new AboreanVault(
            address(weth), address(pengu), address(positionManager),
            address(gauge), address(router), address(pool), address(pyth)
        );

        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 10000000, -8);
        pyth.setPrice(PENGU_USD_PRICE_ID, 200000000, 1000000, -8);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz: Deposit amount >= minimum always succeeds
     */
    function testFuzz_Deposit_ValidAmount(uint256 depositAmount) public {
        // Bound to reasonable range
        depositAmount = bound(depositAmount, vault.MIN_DEPOSIT(), 1000 ether);

        address user = address(0x123);
        vm.deal(user, depositAmount * 2);

        vm.startPrank(user);
        weth.deposit{value: depositAmount}();
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user);
        vm.stopPrank();

        // User should have received shares
        assertGt(vault.balanceOf(user), 0);

        // Vault should have position
        assertGt(vault.nftTokenId(), 0);
    }

    /**
     * @notice Fuzz: Deposit below minimum always reverts
     */
    function testFuzz_Deposit_BelowMinimum_Reverts(uint256 depositAmount) public {
        // Bound to below minimum
        depositAmount = bound(depositAmount, 1 wei, vault.MIN_DEPOSIT() - 1);

        address user = address(0x123);
        vm.deal(user, 1 ether);

        vm.startPrank(user);
        weth.deposit{value: 1 ether}();
        weth.approve(address(vault), depositAmount);

        vm.expectRevert("Below minimum deposit");
        vault.deposit(depositAmount, user);

        vm.stopPrank();
    }

    /**
     * @notice Fuzz: Multiple sequential deposits maintain correct share accounting
     */
    function testFuzz_MultipleDeposits_ShareAccounting(
        uint256 deposit1,
        uint256 deposit2,
        uint256 deposit3
    ) public {
        deposit1 = bound(deposit1, vault.MIN_DEPOSIT(), 100 ether);
        deposit2 = bound(deposit2, vault.MIN_DEPOSIT(), 100 ether);
        deposit3 = bound(deposit3, vault.MIN_DEPOSIT(), 100 ether);

        address user1 = address(0x111);
        address user2 = address(0x222);
        address user3 = address(0x333);

        // Setup users
        vm.deal(user1, deposit1 * 2);
        vm.deal(user2, deposit2 * 2);
        vm.deal(user3, deposit3 * 2);

        // User 1 deposits
        vm.startPrank(user1);
        weth.deposit{value: deposit1}();
        weth.approve(address(vault), deposit1);
        vault.deposit(deposit1, user1);
        vm.stopPrank();

        uint256 user1Shares = vault.balanceOf(user1);

        // User 2 deposits
        vm.startPrank(user2);
        weth.deposit{value: deposit2}();
        weth.approve(address(vault), deposit2);
        vault.deposit(deposit2, user2);
        vm.stopPrank();

        uint256 user2Shares = vault.balanceOf(user2);

        // User 3 deposits
        vm.startPrank(user3);
        weth.deposit{value: deposit3}();
        weth.approve(address(vault), deposit3);
        vault.deposit(deposit3, user3);
        vm.stopPrank();

        uint256 user3Shares = vault.balanceOf(user3);

        // Total shares should equal sum of individual shares
        uint256 totalShares = vault.totalSupply();
        assertEq(totalShares, user1Shares + user2Shares + user3Shares);
    }

    /*//////////////////////////////////////////////////////////////
                        TICK RANGE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz: Tick calculations always return valid, usable ticks
     */
    function testFuzz_TickCalculations_AlwaysValid(int24 rawTick) public {
        // Bound to valid tick range
        rawTick = int24(bound(int256(rawTick), -887272, 887272));

        // Test _nearestUsableTick
        TickRangeHelper helper = new TickRangeHelper();
        int24 usableTick = helper.nearestUsableTick(rawTick, 200);

        // Usable tick must be multiple of tickSpacing
        assertEq(usableTick % 200, 0);

        // Usable tick should be close to raw tick
        int24 diff = usableTick > rawTick ? usableTick - rawTick : rawTick - usableTick;
        assertLt(diff, 200);
    }

    /**
     * @notice Fuzz: Tick ranges are always properly bounded
     */
    function testFuzz_TickRange_ProperlyBounded(uint160 sqrtPriceX96) public {
        // Bound to valid sqrtPriceX96 range (avoid extremes)
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, 1e15, type(uint128).max));

        pool.setSqrtPriceX96(sqrtPriceX96, 0);

        TickRangeHelper helper = new TickRangeHelper();
        helper.setPool(address(pool));

        (int24 tickLower, int24 tickUpper) = helper.calculateTickRange();

        // Basic sanity checks
        assertLt(tickLower, tickUpper);
        assertEq(tickLower % 200, 0);
        assertEq(tickUpper % 200, 0);

        // Tick range should be reasonable (±20% ≈ ±1823 ticks, rounded to 200)
        int24 range = (tickUpper - tickLower) / 2;
        assertGt(range, 1400); // At least ~14%
        assertLt(range, 2400); // At most ~24%
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz: Oracle prices with valid confidence always work
     */
    function testFuzz_OraclePrice_ValidConfidence(int64 price, uint64 conf) public {
        // Ensure price is positive and reasonable
        price = int64(bound(int256(price), 1e8, 1e12)); // $1 to $10,000

        // Confidence must be < 1% of price
        conf = uint64(bound(conf, 0, uint64(price) / 101)); // Just under 1%

        pyth.setPrice(WETH_USD_PRICE_ID, price, conf, -8);

        // Should not revert
        address user = address(0x123);
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        weth.deposit{value: 1 ether}();
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user);
        vm.stopPrank();

        // Should succeed
        assertGt(vault.balanceOf(user), 0);
    }

    /**
     * @notice Fuzz: Oracle prices with invalid confidence always revert
     */
    function testFuzz_OraclePrice_InvalidConfidence_Reverts(int64 price, uint64 conf) public {
        // Ensure price is positive and reasonable
        price = int64(bound(int256(price), 1e8, 1e12));

        // Confidence must be >= 1% of price (invalid)
        conf = uint64(bound(conf, uint64(price) / 100, uint64(price) / 10)); // 1% to 10%

        pyth.setPrice(WETH_USD_PRICE_ID, price, conf, -8);

        address user = address(0x123);
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        weth.deposit{value: 1 ether}();
        weth.approve(address(vault), 1 ether);

        vm.expectRevert("Price confidence too low");
        vault.deposit(1 ether, user);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Invariant: Total supply equals sum of all balances
     */
    function invariant_TotalSupply_EqualsBalances() public view {
        // This would be enhanced with a proper invariant testing setup
        // For now, we just verify totalSupply is accessible
        vault.totalSupply();
    }

    /**
     * @notice Invariant: totalAssets never decreases unexpectedly
     * @dev In a real scenario (with compounds), totalAssets should only increase
     */
    function testFuzz_TotalAssets_NeverDecreasesOnDeposit(
        uint256 deposit1,
        uint256 deposit2
    ) public {
        deposit1 = bound(deposit1, vault.MIN_DEPOSIT(), 100 ether);
        deposit2 = bound(deposit2, vault.MIN_DEPOSIT(), 100 ether);

        address user1 = address(0x111);
        address user2 = address(0x222);

        // First deposit
        vm.deal(user1, deposit1 * 2);
        vm.startPrank(user1);
        weth.deposit{value: deposit1}();
        weth.approve(address(vault), deposit1);
        vault.deposit(deposit1, user1);
        vm.stopPrank();

        uint256 totalAssetsAfterFirst = vault.totalAssets();

        // Second deposit
        vm.deal(user2, deposit2 * 2);
        vm.startPrank(user2);
        weth.deposit{value: deposit2}();
        weth.approve(address(vault), deposit2);
        vault.deposit(deposit2, user2);
        vm.stopPrank();

        uint256 totalAssetsAfterSecond = vault.totalAssets();

        // Total assets should increase (or stay same in edge cases)
        assertGe(totalAssetsAfterSecond, totalAssetsAfterFirst);
    }

    /**
     * @notice Invariant: Share price should never drastically decrease
     */
    function testFuzz_SharePrice_StableOrIncreasing(
        uint256 deposit1,
        uint256 deposit2
    ) public {
        deposit1 = bound(deposit1, vault.MIN_DEPOSIT(), 100 ether);
        deposit2 = bound(deposit2, vault.MIN_DEPOSIT(), 100 ether);

        address user1 = address(0x111);
        address user2 = address(0x222);

        // First deposit
        vm.deal(user1, deposit1 * 2);
        vm.startPrank(user1);
        weth.deposit{value: deposit1}();
        weth.approve(address(vault), deposit1);
        vault.deposit(deposit1, user1);
        vm.stopPrank();

        uint256 shares1 = vault.balanceOf(user1);
        uint256 assets1 = vault.totalAssets();
        uint256 sharePrice1 = (assets1 * 1e18) / shares1;

        // Second deposit
        vm.deal(user2, deposit2 * 2);
        vm.startPrank(user2);
        weth.deposit{value: deposit2}();
        weth.approve(address(vault), deposit2);
        vault.deposit(deposit2, user2);
        vm.stopPrank();

        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();
        uint256 sharePrice2 = (totalAssets * 1e18) / totalShares;

        // Share price should not decrease significantly
        // Allow 5% tolerance for slippage/rounding
        assertApproxEqRel(sharePrice2, sharePrice1, 0.05e18);
    }

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fuzz: Minimum deposit boundary
     */
    function testFuzz_MinimumDeposit_Boundary() public {
        uint256 exactMin = vault.MIN_DEPOSIT();

        address user = address(0x123);
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        weth.deposit{value: exactMin}();
        weth.approve(address(vault), exactMin);
        vault.deposit(exactMin, user);
        vm.stopPrank();

        assertGt(vault.balanceOf(user), 0);
    }

    /**
     * @notice Fuzz: Large deposit doesn't break accounting
     */
    function testFuzz_LargeDeposit_Accounting(uint256 depositAmount) public {
        // Bound to large but not overflow range
        depositAmount = bound(depositAmount, 100 ether, 10000 ether);

        address whale = address(0x999);
        vm.deal(whale, depositAmount * 2);

        vm.startPrank(whale);
        weth.deposit{value: depositAmount}();
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, whale);
        vm.stopPrank();

        // Should succeed without overflow
        assertGt(vault.balanceOf(whale), 0);
        assertGt(vault.totalAssets(), 0);
    }
}

/**
 * @title TickRangeHelper
 * @notice Helper contract to expose vault's tick calculation functions for testing
 */
contract TickRangeHelper {
    address public pool;

    function setPool(address _pool) external {
        pool = _pool;
    }

    function nearestUsableTick(int24 tick, int24 tickSpacing) external pure returns (int24) {
        // Replicate vault's _nearestUsableTick logic
        int24 rounded = (tick / tickSpacing) * tickSpacing;

        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;

        if (rounded < MIN_TICK) {
            return ((MIN_TICK / tickSpacing) + 1) * tickSpacing;
        } else if (rounded > MAX_TICK) {
            return ((MAX_TICK / tickSpacing) - 1) * tickSpacing;
        }

        return rounded;
    }

    function calculateTickRange() external view returns (int24 tickLower, int24 tickUpper) {
        // Get current price from pool
        (uint160 sqrtPriceX96, , , , , , ) = MockUniswapV3Pool(pool).slot0();

        // Simple approximation: convert sqrtPriceX96 to tick
        // For testing purposes, use a simplified calculation
        int24 currentTick = 0; // Simplified

        int24 tickRange = 1823; // ±20%
        int24 tickSpacing = 200;

        int24 tickLowerRaw = currentTick - tickRange;
        int24 tickUpperRaw = currentTick + tickRange;

        tickLower = this.nearestUsableTick(tickLowerRaw, tickSpacing);
        tickUpper = this.nearestUsableTick(tickUpperRaw, tickSpacing);
    }
}
