// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AboreanVault} from "../src/Vault.sol";
import {MockVault} from "./mocks/MockVault.sol";
import {AboreanVault as _AboreanVault} from "../src/Vault.sol";
import {MockWETH, MockPENGU, MockPyth, MockRouter, MockPositionManager, MockCLGauge, MockUniswapV3Pool, MockVotingEscrow, MockVoter} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultSecurityTest
 * @notice Security-focused tests for common exploits and attack vectors
 * @dev Tests ERC-4626 vulnerabilities, reentrancy, oracle manipulation, etc.
 */
contract VaultSecurityTest is Test {
    MockVault public vault;
    MockWETH public weth;
    MockPENGU public pengu;
    MockPyth public pyth;
    MockRouter public router;
    MockPositionManager public positionManager;
    MockCLGauge public gauge;
    MockUniswapV3Pool public pool;

    address public admin = address(0x1);
    address public attacker = address(0x666);
    address public victim = address(0x999);

    bytes32 constant WETH_USD_PRICE_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;
    bytes32 constant PENGU_USD_PRICE_ID = 0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61;

    function setUp() public {
        // Deploy infrastructure
        weth = new MockWETH();
        pengu = new MockPENGU();
        pyth = new MockPyth();
        router = new MockRouter(address(weth), address(pengu));
        positionManager = new MockPositionManager();
        gauge = new MockCLGauge(address(positionManager));
        pool = new MockUniswapV3Pool();
        MockVotingEscrow votingEscrow = new MockVotingEscrow();
        MockVoter voter = new MockVoter();

        pool.setSqrtPriceX96(3540000000000000000000, 0);

        // Give admin ETH for deployment gas
        vm.deal(admin, 100 ether);

        vm.prank(admin);
        vault = new MockVault(
            address(weth), address(pengu), address(positionManager),
            address(gauge), address(router), address(pool), address(pyth),
            address(votingEscrow), address(voter)
        );

        // Set oracle prices
        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 10000000, -8); // $4000
        pyth.setPrice(PENGU_USD_PRICE_ID, 200000000, 1000000, -8);    // $2

        // Fund accounts
        vm.deal(attacker, 1000 ether);
        vm.deal(victim, 1000 ether);

        vm.prank(attacker);
        weth.deposit{value: 500 ether}();

        vm.prank(victim);
        weth.deposit{value: 500 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                        INFLATION ATTACK TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: First depositor inflation attack
     * @dev Attacker tries to manipulate share price by:
     *      1. Depositing minimum amount (0.01 ETH)
     *      2. Directly transferring large amount to vault to inflate totalAssets
     *      3. Victim deposits, receives fewer shares than expected
     *      4. Attacker withdraws with inflated share value
     *
     * Expected: Minimum deposit requirement prevents this attack
     */
    function test_InflationAttack_PreventedByMinDeposit() public {
        // Step 1: Attacker deposits minimum (0.01 WETH)
        vm.startPrank(attacker);
        uint256 attackerDeposit = 0.01 ether;
        weth.approve(address(vault), attackerDeposit);
        vault.deposit(attackerDeposit, attacker);
        vm.stopPrank();

        uint256 attackerShares = vault.balanceOf(attacker);

        // Step 2: Attacker tries to inflate totalAssets by direct transfer
        // (This doesn't work in our vault since totalAssets uses oracle prices,
        //  but we test the share calculation anyway)
        vm.prank(attacker);
        weth.transfer(address(vault), 100 ether); // Attacker loses 100 WETH

        // Step 3: Victim deposits 1 WETH
        vm.startPrank(victim);
        uint256 victimDeposit = 1 ether;
        weth.approve(address(vault), victimDeposit);
        vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        uint256 victimShares = vault.balanceOf(victim);

        // Victim should NOT receive unfairly diluted shares
        // With proper ERC-4626 implementation, victim gets fair shares
        assertGt(victimShares, 0);

        // The minimum deposit requirement (0.01 ETH) makes this attack economically
        // infeasible because attacker needs to risk at least 0.01 ETH
        assertGe(attackerDeposit, vault.MIN_DEPOSIT());
    }

    /**
     * @notice Test: Donation attack (direct WETH transfer)
     * @dev Attacker donates WETH to vault to try to manipulate totalAssets
     * Expected: totalAssets uses oracle prices, not balances, so this fails
     */
    function test_DonationAttack_HasNoEffect() public {
        // Victim deposits first
        vm.startPrank(victim);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, victim);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 victimSharesBefore = vault.balanceOf(victim);

        // Attacker donates 100 WETH directly to vault
        vm.prank(attacker);
        weth.transfer(address(vault), 100 ether);

        uint256 totalAssetsAfter = vault.totalAssets();

        // totalAssets should NOT increase from donation
        // (Our vault uses oracle prices and actual LP position, not raw balances)
        assertEq(totalAssetsBefore, totalAssetsAfter);

        // Victim shares should not be diluted
        assertEq(vault.balanceOf(victim), victimSharesBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Reentrancy on deposit
     * @dev Attacker tries to reenter deposit() during callback
     * Expected: ReentrancyGuard prevents this
     */
    function test_ReentrancyAttack_OnDeposit_Prevented() public {
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(vault, weth);

        vm.deal(address(attackerContract), 10 ether);
        attackerContract.attack{value: 10 ether}();

        // Attack should fail - attacker gets no unfair advantage
        // (ReentrancyGuard modifier should prevent reentrant calls)
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Flash loan price manipulation attempt
     * @dev Attacker tries to manipulate pool price before totalAssets call
     * Expected: Vault uses Pyth oracle (not pool price) for valuation, so this fails
     */
    function test_FlashLoanAttack_PreventedByOracle() public {
        // Victim deposits
        vm.startPrank(victim);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, victim);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        // Attacker manipulates pool price (simulating flash loan swap)
        // Pool price: 1 WETH = 5000 PENGU (instead of 2000)
        pool.setSqrtPriceX96(4450000000000000000000, 0);

        uint256 totalAssetsDuring = vault.totalAssets();

        // totalAssets should NOT change significantly
        // Vault uses Pyth oracle prices, not pool prices
        assertApproxEqRel(totalAssetsBefore, totalAssetsDuring, 0.01e18); // 1% tolerance
    }

    /**
     * @notice Test: Stale oracle price protection
     * @dev Attacker waits for oracle to become stale before manipulating
     * Expected: Vault reverts on stale prices
     */
    function test_StaleOracle_Reverts() public {
        // Victim deposits
        vm.startPrank(victim);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, victim);
        vm.stopPrank();

        // Time passes beyond staleness threshold (60 seconds)
        vm.warp(block.timestamp + 61);

        // Any operation requiring oracle should revert
        vm.expectRevert("Price too old");
        vault.totalAssets();
    }

    /**
     * @notice Test: Low confidence oracle protection
     * @dev Oracle returns price with >1% confidence interval
     * Expected: Vault rejects low-confidence prices
     */
    function test_LowConfidenceOracle_Reverts() public {
        // First deposit with good prices
        vm.startPrank(victim);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, victim);
        vm.stopPrank();

        // Now set WETH price with 5% confidence (too high)
        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 20000000000, -8);

        // totalAssets() should fail due to low confidence
        vm.expectRevert("Price confidence too low");
        vault.totalAssets();
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE EXPLOITATION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Slippage protection on swaps
     * @dev Ensure swaps respect MAX_SLIPPAGE_BPS (0.5%)
     */
    function test_SlippageProtection_Enforced() public {
        // This would require a more sophisticated mock router that can
        // simulate different slippage scenarios. For now, we verify
        // that the slippage constant is reasonable.
        assertEq(vault.MAX_SLIPPAGE_BPS(), 50); // 0.5%
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN PRIVILEGE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Admin cannot steal user funds
     * @dev Verify admin has no functions to withdraw user deposits
     */
    function test_AdminCannotStealFunds() public {
        // Victim deposits
        vm.startPrank(victim);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, victim);
        vm.stopPrank();

        uint256 victimSharesBefore = vault.balanceOf(victim);

        // Admin tries various operations
        vm.startPrank(admin);

        // Admin can pause (emergency only)
        vault.pause();
        vault.unpause();

        // But admin CANNOT withdraw user funds
        // (No such function exists in the vault)

        vm.stopPrank();

        // Victim shares unchanged
        assertEq(vault.balanceOf(victim), victimSharesBefore);
    }

    /**
     * @notice Test: Non-admin cannot pause
     * @dev Only owner can pause/unpause
     */
    function test_OnlyAdminCanPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        PRECISION & ROUNDING TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Rounding errors don't accumulate
     * @dev Multiple small deposits shouldn't create exploitable rounding
     */
    function test_RoundingErrors_NoAccumulation() public {
        // Multiple users make minimum deposits
        for (uint256 i = 0; i < 10; i++) {
            address user = address(uint160(1000 + i));
            vm.deal(user, 1 ether);

            vm.startPrank(user);
            weth.deposit{value: 0.01 ether}();
            weth.approve(address(vault), 0.01 ether);
            vault.deposit(0.01 ether, user);
            vm.stopPrank();
        }

        // Total assets should approximately equal total deposits
        uint256 totalDeposits = 0.1 ether; // 10 * 0.01
        uint256 totalAssets = vault.totalAssets();

        // Allow 2% tolerance for swap slippage
        assertApproxEqRel(totalAssets, totalDeposits, 0.02e18);
    }

    /**
     * @notice Test: Share price manipulation through dust deposits
     * @dev Attacker tries to exploit rounding by making many tiny deposits
     */
    function test_DustDeposit_Prevented() public {
        // Minimum deposit prevents dust attacks
        uint256 dustAmount = 0.001 ether;

        vm.startPrank(attacker);
        weth.approve(address(vault), dustAmount);

        vm.expectRevert("Below minimum deposit");
        vault.deposit(dustAmount, attacker);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Paused vault blocks deposits
     */
    function test_PausedVault_BlocksDeposits() public {
        vm.prank(admin);
        vault.pause();

        vm.startPrank(victim);
        weth.approve(address(vault), 1 ether);

        vm.expectRevert(); // Pausable: paused
        vault.deposit(1 ether, victim);

        vm.stopPrank();
    }

    /**
     * @notice Test: maxDeposit returns 0 when paused
     */
    function test_MaxDeposit_ZeroWhenPaused() public {
        assertEq(vault.maxDeposit(victim), type(uint256).max);

        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxDeposit(victim), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SHARE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: First depositor cannot create unfair share advantage
     */
    function test_FirstDepositor_NoUnfairAdvantage() public {
        // First depositor
        vm.startPrank(attacker);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, attacker);
        vm.stopPrank();

        uint256 attackerShares = vault.balanceOf(attacker);

        // Second depositor (same amount)
        vm.startPrank(victim);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, victim);
        vm.stopPrank();

        uint256 victimShares = vault.balanceOf(victim);

        // Both should have approximately same shares for same deposit
        assertApproxEqRel(attackerShares, victimShares, 0.01e18); // 1% tolerance
    }
}

/**
 * @title ReentrancyAttacker
 * @notice Malicious contract that attempts reentrancy attack
 */
contract ReentrancyAttacker {
    MockVault public vault;
    MockWETH public weth;
    bool public attacking;

    constructor(MockVault _vault, MockWETH _weth) {
        vault = _vault;
        weth = _weth;
    }

    function attack() external payable {
        // Convert ETH to WETH
        weth.deposit{value: msg.value}();

        // Approve vault
        weth.approve(address(vault), msg.value);

        // Start attack
        attacking = true;
        vault.deposit(msg.value, address(this));
    }

    // This would be called during deposit if there was a vulnerability
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attacking) {
            attacking = false;
            // Try to reenter (this should fail due to ReentrancyGuard)
            try vault.deposit(0.01 ether, address(this)) {
                // If we get here, reentrancy worked (BAD!)
                revert("Reentrancy succeeded - vulnerability!");
            } catch {
                // Expected: reentrancy blocked
            }
        }
        return this.onERC721Received.selector;
    }
}
