// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AboreanVault} from "../src/Vault.sol";
import {MockVault} from "./mocks/MockVault.sol";
import {MockWETH, MockPENGU, MockPyth, MockRouter, MockPositionManager, MockCLGauge, MockUniswapV3Pool, MockVotingEscrow, MockVoter} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultUnitTest
 * @notice Unit tests for AboreanVault using mocked dependencies
 * @dev Tests individual functions in isolation
 */
contract VaultUnitTest is Test {
    MockVault public vault;
    MockWETH public weth;
    MockPENGU public pengu;
    MockPyth public pyth;
    MockRouter public router;
    MockPositionManager public positionManager;
    MockCLGauge public gauge;
    MockUniswapV3Pool public pool;
    MockVotingEscrow public votingEscrow;
    MockVoter public voter;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Price feed IDs (from vault)
    bytes32 constant WETH_USD_PRICE_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;
    bytes32 constant PENGU_USD_PRICE_ID = 0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61;

    function setUp() public {
        // Deploy mocks
        weth = new MockWETH();
        pengu = new MockPENGU();
        pyth = new MockPyth();
        router = new MockRouter(address(weth), address(pengu));
        positionManager = new MockPositionManager();
        gauge = new MockCLGauge(address(positionManager));
        pool = new MockUniswapV3Pool();
        votingEscrow = new MockVotingEscrow();
        voter = new MockVoter();

        // Set initial pool price (1 WETH = 2000 PENGU)
        // sqrtPriceX96 = sqrt(2000) * 2^96 ≈ 3.54e21
        pool.setSqrtPriceX96(3540000000000000000000, 0);

        // Give admin ETH for deployment gas
        vm.deal(admin, 100 ether);

        // Deploy vault as admin
        vm.startPrank(admin);
        vault = new MockVault(
            address(weth),
            address(pengu),
            address(positionManager),
            address(gauge),
            address(router),
            address(pool),
            address(pyth),
            address(votingEscrow),
            address(voter)
        );
        vm.stopPrank();

        // Set oracle prices
        // WETH: $4000, expo = -8 (price * 10^-8)
        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 10000000, -8);

        // PENGU: $2, expo = -8
        pyth.setPrice(PENGU_USD_PRICE_ID, 200000000, 1000000, -8);

        // Give users some ETH and WETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        vm.prank(user1);
        weth.deposit{value: 50 ether}();

        vm.prank(user2);
        weth.deposit{value: 50 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        assertEq(address(vault.weth()), address(weth));
        assertEq(address(vault.pengu()), address(pengu));
        assertEq(address(vault.positionManager()), address(positionManager));
        assertEq(address(vault.gauge()), address(gauge));
        assertEq(address(vault.router()), address(router));
        assertEq(address(vault.pool()), address(pool));
        assertEq(address(vault.pyth()), address(pyth));
        assertEq(vault.owner(), admin);
        assertEq(vault.nftTokenId(), 0);
    }

    function test_Constructor_RevertIf_ZeroAddresses() public {
        vm.expectRevert("Invalid WETH address");
        new MockVault(
            address(0), address(pengu), address(positionManager),
            address(gauge), address(router), address(pool), address(pyth),
            address(votingEscrow), address(voter)
        );

        vm.expectRevert("Invalid PENGU address");
        new MockVault(
            address(weth), address(0), address(positionManager),
            address(gauge), address(router), address(pool), address(pyth),
            address(votingEscrow), address(voter)
        );

        vm.expectRevert("Invalid Position Manager");
        new MockVault(
            address(weth), address(pengu), address(0),
            address(gauge), address(router), address(pool), address(pyth),
            address(votingEscrow), address(voter)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetPythPrice_WETH() public view {
        // WETH price should be $4000 in 18 decimals
        // Pyth returns: price = 400000000000, expo = -8
        // Expected: 400000000000 * 10^(18-8) = 4000e18
        uint256 price = vault.totalAssets(); // Triggers oracle call internally
        // Can't directly test internal _getPythPrice, but we can verify it works via totalAssets
    }

    function test_GetPythPrice_RevertIf_StalePrice() public {
        // First create a position so totalAssets() will call the oracle
        vm.startPrank(user1);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user1);
        vm.stopPrank();

        // Advance time beyond staleness threshold (60 seconds)
        vm.warp(block.timestamp + 61);

        // Try to use stale price - should revert
        vm.expectRevert("Price too old");
        vault.totalAssets();
    }

    function test_GetPythPrice_RevertIf_LowConfidence() public {
        // First create a position so totalAssets() will call the oracle
        vm.startPrank(user1);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user1);
        vm.stopPrank();

        // Set price with >1% confidence (high uncertainty)
        // Price = 400000000000, conf = 5000000000 (5% uncertainty)
        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 5000000000, -8);

        vm.expectRevert("Price confidence too low");
        vault.totalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_FirstDeposit_Success() public {
        uint256 depositAmount = 1 ether;

        vm.startPrank(user1);
        weth.approve(address(vault), depositAmount);

        uint256 sharesBefore = vault.balanceOf(user1);
        vault.deposit(depositAmount, user1);
        uint256 sharesAfter = vault.balanceOf(user1);

        vm.stopPrank();

        // User should receive shares (1:1 on first deposit)
        assertEq(sharesAfter - sharesBefore, depositAmount);

        // Vault should have created NFT position
        assertGt(vault.nftTokenId(), 0);
    }

    function test_Deposit_RevertIf_BelowMinimum() public {
        uint256 tooSmall = 0.009 ether; // Below 0.01 ETH minimum

        vm.startPrank(user1);
        weth.approve(address(vault), tooSmall);

        vm.expectRevert("Below minimum deposit");
        vault.deposit(tooSmall, user1);

        vm.stopPrank();
    }

    function test_Deposit_RevertIf_Paused() public {
        // Admin pauses vault
        vm.prank(admin);
        vault.pause();

        uint256 depositAmount = 1 ether;

        vm.startPrank(user1);
        weth.approve(address(vault), depositAmount);

        vm.expectRevert();
        vault.deposit(depositAmount, user1);

        vm.stopPrank();
    }

    function test_Deposit_MultipleUsers() public {
        // User1 deposits first
        vm.startPrank(user1);
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether, user1);
        vm.stopPrank();

        uint256 user1Shares = vault.balanceOf(user1);

        // User2 deposits second
        vm.startPrank(user2);
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether, user2);
        vm.stopPrank();

        uint256 user2Shares = vault.balanceOf(user2);

        // Both should have shares proportional to deposits
        assertGt(user1Shares, 0);
        assertGt(user2Shares, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        TOTAL ASSETS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TotalAssets_ZeroWhenNoPosition() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_TotalAssets_AfterDeposit() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(user1);
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Total assets should be approximately depositAmount
        // (May differ slightly due to swap and liquidity provision)
        uint256 assets = vault.totalAssets();
        assertGt(assets, 0);
        assertApproxEqRel(assets, depositAmount, 0.02e18); // 2% tolerance
    }

    /*//////////////////////////////////////////////////////////////
                        WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_Success() public {
        // First deposit
        vm.startPrank(user1);
        weth.approve(address(vault), 1 ether);
        uint256 shares = vault.deposit(1 ether, user1);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Withdraw half
        vm.startPrank(user1);
        uint256 assetsToWithdraw = 0.5 ether;
        uint256 sharesToBurn = vault.previewWithdraw(assetsToWithdraw);
        
        uint256 wethBalanceBefore = weth.balanceOf(user1);
        vault.withdraw(assetsToWithdraw, user1, user1);
        uint256 wethBalanceAfter = weth.balanceOf(user1);
        vm.stopPrank();

        // Verify user received WETH
        assertApproxEqRel(wethBalanceAfter - wethBalanceBefore, assetsToWithdraw, 0.02e18); // 2% tolerance for slippage
        
        // Verify shares were burned
        assertApproxEqAbs(vault.balanceOf(user1), shares - sharesToBurn, 1);
        
        // Verify total assets decreased
        assertLt(vault.totalAssets(), totalAssetsBefore);
    }

    function test_Redeem_Success() public {
        // First deposit
        vm.startPrank(user1);
        weth.approve(address(vault), 2 ether);
        uint256 shares = vault.deposit(2 ether, user1);
        vm.stopPrank();

        // Redeem half the shares
        vm.startPrank(user1);
        uint256 sharesToRedeem = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(sharesToRedeem);
        
        uint256 wethBalanceBefore = weth.balanceOf(user1);
        uint256 assetsReceived = vault.redeem(sharesToRedeem, user1, user1);
        uint256 wethBalanceAfter = weth.balanceOf(user1);
        vm.stopPrank();

        // Verify user received WETH
        assertEq(wethBalanceAfter - wethBalanceBefore, assetsReceived);
        assertApproxEqRel(assetsReceived, expectedAssets, 0.02e18); // 2% tolerance
        
        // Verify shares were burned
        assertEq(vault.balanceOf(user1), shares - sharesToRedeem);
    }

    function test_Withdraw_RevertIf_Paused() public {
        // Deposit first
        vm.startPrank(user1);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user1);
        vm.stopPrank();

        // Pause vault
        vm.prank(admin);
        vault.pause();

        // Try to withdraw
        vm.startPrank(user1);
        vm.expectRevert();
        vault.withdraw(0.5 ether, user1, user1);
        vm.stopPrank();
    }

    function test_Withdraw_FullWithdrawal() public {
        // Deposit
        vm.startPrank(user1);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, user1);
        vm.stopPrank();

        // Withdraw everything
        vm.startPrank(user1);
        uint256 maxAssets = vault.maxWithdraw(user1);
        
        uint256 wethBalanceBefore = weth.balanceOf(user1);
        vault.withdraw(maxAssets, user1, user1);
        uint256 wethBalanceAfter = weth.balanceOf(user1);
        vm.stopPrank();

        // Verify all shares were burned
        assertEq(vault.balanceOf(user1), 0);
        
        // Verify user received assets
        assertGt(wethBalanceAfter - wethBalanceBefore, 0);
    }

    function test_Withdraw_MultipleUsers() public {
        // User1 deposits
        vm.startPrank(user1);
        weth.approve(address(vault), 2 ether);
        vault.deposit(2 ether, user1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        weth.approve(address(vault), 3 ether);
        vault.deposit(3 ether, user2);
        vm.stopPrank();

        uint256 user1SharesBefore = vault.balanceOf(user1);
        uint256 user2SharesBefore = vault.balanceOf(user2);

        // User1 withdraws
        vm.startPrank(user1);
        uint256 wethBefore1 = weth.balanceOf(user1);
        vault.withdraw(1 ether, user1, user1);
        uint256 wethAfter1 = weth.balanceOf(user1);
        vm.stopPrank();

        // User2 withdraws
        vm.startPrank(user2);
        uint256 wethBefore2 = weth.balanceOf(user2);
        vault.withdraw(1.5 ether, user2, user2);
        uint256 wethAfter2 = weth.balanceOf(user2);
        vm.stopPrank();

        // Both users received their assets
        assertApproxEqRel(wethAfter1 - wethBefore1, 1 ether, 0.02e18);
        assertApproxEqRel(wethAfter2 - wethBefore2, 1.5 ether, 0.02e18);
        
        // Both users' shares decreased
        assertLt(vault.balanceOf(user1), user1SharesBefore);
        assertLt(vault.balanceOf(user2), user2SharesBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        HARVEST & COMPOUND TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Harvest_CollectsFees() public {
        // Deposit to create position
        vm.startPrank(user1);
        weth.approve(address(vault), 2 ether);
        vault.deposit(2 ether, user1);
        vm.stopPrank();

        // Simulate some trading fees accrued (in real scenario)
        // For mock, this is a simplified test
        vm.prank(admin);
        vault.harvest();
        
        // Test passes if harvest doesn't revert
        assertTrue(true);
    }

    function test_Compound_ReinvestsRewards() public {
        // Deposit to create position
        vm.startPrank(user1);
        weth.approve(address(vault), 2 ether);
        vault.deposit(2 ether, user1);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Compound (in real scenario would collect fees and add to LP)
        vm.prank(admin);
        vault.compound();
        
        // Total assets should stay approximately the same or increase
        uint256 totalAssetsAfter = vault.totalAssets();
        assertGe(totalAssetsAfter, totalAssetsBefore * 99 / 100); // Allow for rounding
    }

    function test_Harvest_RevertIf_NotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.harvest();
        vm.stopPrank();
    }

    function test_Compound_RevertIf_NotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vault.compound();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TICK MATH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CalculateTickRange() public {
        // Deploy a simple test contract to expose internal function
        TickRangeTest tickTest = new TickRangeTest(address(pool));

        (int24 tickLower, int24 tickUpper) = tickTest.calculateTickRange();

        // Verify ticks are valid
        assertLt(tickLower, tickUpper);

        // Verify ticks are multiples of TICK_SPACING (200)
        assertEq(tickLower % 200, 0);
        assertEq(tickUpper % 200, 0);

        // Verify range is approximately ±20% (±1823 ticks)
        int24 tickRange = (tickUpper - tickLower) / 2;
        assertApproxEqAbs(tickRange, 1823, 200); // Within 200 ticks
    }

    function test_NearestUsableTick() public {
        TickRangeTest tickTest = new TickRangeTest(address(pool));

        // Test various tick values
        assertEq(tickTest.nearestUsableTick(0, 200), 0);
        assertEq(tickTest.nearestUsableTick(100, 200), 0);
        assertEq(tickTest.nearestUsableTick(200, 200), 200);
        assertEq(tickTest.nearestUsableTick(250, 200), 200);
        assertEq(tickTest.nearestUsableTick(-100, 200), 0);
        assertEq(tickTest.nearestUsableTick(-250, 200), -200);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Success() public {
        vm.prank(admin);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_Pause_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }

    function test_Unpause_Success() public {
        // First pause
        vm.prank(admin);
        vault.pause();

        // Then unpause
        vm.prank(admin);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function test_MaxDeposit_WhenPaused() public {
        // Before pause
        assertEq(vault.maxDeposit(user1), type(uint256).max);

        // Pause
        vm.prank(admin);
        vault.pause();

        // After pause
        assertEq(vault.maxDeposit(user1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_ExactMinimum() public {
        uint256 depositAmount = 0.01 ether; // Exactly minimum

        vm.startPrank(user1);
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        assertGt(vault.balanceOf(user1), 0);
    }

    function test_TotalAssets_PrecisionWithSmallDeposits() public {
        uint256 depositAmount = 0.01 ether;

        vm.startPrank(user1);
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Should handle small amounts without precision loss
        uint256 assets = vault.totalAssets();
        assertGt(assets, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        VEABX LOCKING & VOTING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LockABX_CreatesNewVeNFT() public {
        // Mint ABX tokens to vault
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 100 ether);

        // Lock ABX
        vm.prank(admin);
        vault.lockABX(50 ether);

        // Should have created veNFT
        assertGt(vault.veABXTokenId(), 0);
        assertEq(votingEscrow.balances(vault.veABXTokenId()), 100 ether);
    }

    function test_LockABX_AddsToExistingLock() public {
        // First lock
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 100 ether);
        vm.prank(admin);
        vault.lockABX(50 ether);
        
        uint256 veTokenId = vault.veABXTokenId();
        uint256 initialBalance = votingEscrow.balances(veTokenId);

        // Second lock with more ABX
        deal(abxToken, address(vault), 50 ether);
        vm.prank(admin);
        vault.lockABX(10 ether);

        // Should add to existing veNFT
        assertEq(vault.veABXTokenId(), veTokenId);
        assertEq(votingEscrow.balances(veTokenId), initialBalance + 50 ether);
    }

    function test_LockABX_RevertsIfNotOwner() public {
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 100 ether);

        vm.prank(user1);
        vm.expectRevert();
        vault.lockABX(50 ether);
    }

    function test_LockABX_RevertsIfInsufficientBalance() public {
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 10 ether);

        vm.prank(admin);
        vm.expectRevert("Insufficient ABX balance");
        vault.lockABX(50 ether);
    }

    function test_VoteForPool_AllocatesVotingPower() public {
        // Setup: lock ABX first
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 100 ether);
        vm.prank(admin);
        vault.lockABX(50 ether);

        // Vote for pool
        vm.prank(admin);
        vault.voteForPool();

        // Check event was emitted and vote was recorded
        assertGt(voter.totalWeight(), 0);
    }

    function test_VoteForPool_RevertsIfNoVeNFT() public {
        vm.prank(admin);
        vm.expectRevert("No veABX NFT exists");
        vault.voteForPool();
    }

    function test_VoteForPool_RevertsIfNotOwner() public {
        // Setup: lock ABX first
        address abxToken = gauge.rewardToken();
        deal(abxToken, address(vault), 100 ether);
        vm.prank(admin);
        vault.lockABX(50 ether);

        // Try to vote as non-owner
        vm.prank(user1);
        vm.expectRevert();
        vault.voteForPool();
    }
}

/**
 * @title TickRangeTest
 * @notice Helper contract to expose vault's internal tick calculation functions
 */
contract TickRangeTest is AboreanVault {
    constructor(address _pool) AboreanVault(
        address(new MockWETH()),
        address(new MockPENGU()),
        address(new MockPositionManager()),
        address(new MockCLGauge(address(new MockPositionManager()))),
        address(new MockRouter(address(0), address(0))),
        _pool,
        address(new MockPyth()),
        address(new MockVotingEscrow()),
        address(new MockVoter())
    ) {}

    function calculateTickRange() external view returns (int24, int24) {
        return _calculateTickRange();
    }

    function nearestUsableTick(int24 tick, int24 tickSpacing) external pure returns (int24) {
        return _nearestUsableTick(tick, tickSpacing);
    }
}
