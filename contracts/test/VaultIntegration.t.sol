// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {AboreanVault} from "../src/Vault.sol";
import {MockVault} from "./mocks/MockVault.sol";
import {AboreanVault as _AboreanVault} from "../src/Vault.sol";
import {MockWETH, MockPENGU, MockPyth, MockRouter, MockPositionManager, MockCLGauge, MockUniswapV3Pool} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultIntegrationTest
 * @notice Integration tests for complete user workflows
 * @dev Tests end-to-end scenarios with mocked protocol contracts
 */
contract VaultIntegrationTest is Test {
    MockVault public vault;
    MockWETH public weth;
    MockPENGU public pengu;
    MockPyth public pyth;
    MockRouter public router;
    MockPositionManager public positionManager;
    MockCLGauge public gauge;
    MockUniswapV3Pool public pool;

    address public admin = address(0x1);
    address public alice = address(0x11);
    address public bob = address(0x22);
    address public charlie = address(0x33);

    bytes32 constant WETH_USD_PRICE_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;
    bytes32 constant PENGU_USD_PRICE_ID = 0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        // Deploy infrastructure
        weth = new MockWETH();
        pengu = new MockPENGU();
        pyth = new MockPyth();
        router = new MockRouter(address(weth), address(pengu));
        positionManager = new MockPositionManager();
        gauge = new MockCLGauge(address(positionManager));
        pool = new MockUniswapV3Pool();

        pool.setSqrtPriceX96(3540000000000000000000, 0);

        // Give admin ETH for deployment gas
        vm.deal(admin, 100 ether);

        vm.prank(admin);
        vault = new MockVault(
            address(weth), address(pengu), address(positionManager),
            address(gauge), address(router), address(pool), address(pyth)
        );

        // Set prices
        pyth.setPrice(WETH_USD_PRICE_ID, 400000000000, 10000000, -8);
        pyth.setPrice(PENGU_USD_PRICE_ID, 200000000, 1000000, -8);

        // Fund users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        vm.prank(alice);
        weth.deposit{value: 50 ether}();

        vm.prank(bob);
        weth.deposit{value: 50 ether}();

        vm.prank(charlie);
        weth.deposit{value: 50 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE USER FLOWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Complete first depositor flow
     * Flow: Alice deposits → Creates position → Stakes in gauge → Receives shares
     */
    function test_Integration_FirstDepositorFlow() public {
        uint256 depositAmount = 10 ether;

        // Step 1: Alice approves vault
        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);

        // Step 2: Alice deposits (creates position + stakes)
        uint256 sharesBefore = vault.balanceOf(alice);
        vault.deposit(depositAmount, alice);
        uint256 sharesAfter = vault.balanceOf(alice);

        vm.stopPrank();

        // Verify: Alice received shares
        uint256 sharesReceived = sharesAfter - sharesBefore;
        assertGt(sharesReceived, 0);

        // Verify: Vault created NFT position
        uint256 tokenId = vault.nftTokenId();
        assertGt(tokenId, 0);

        // Verify: Position is staked in gauge
        assertEq(gauge.stakedNFTs(tokenId), address(vault));

        // Verify: Total assets approximately equals deposit
        uint256 totalAssets = vault.totalAssets();
        assertApproxEqRel(totalAssets, depositAmount, 0.02e18); // 2% tolerance
    }

    /**
     * @notice Test: Multiple sequential depositors
     * Flow: Alice deposits → Bob deposits → Charlie deposits
     */
    function test_Integration_MultipleDepositors() public {
        // Alice deposits 5 ETH
        vm.startPrank(alice);
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether, alice);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 totalAssetsAfterAlice = vault.totalAssets();

        // Bob deposits 10 ETH
        vm.startPrank(bob);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, bob);
        vm.stopPrank();

        uint256 bobShares = vault.balanceOf(bob);
        uint256 totalAssetsAfterBob = vault.totalAssets();

        // Charlie deposits 15 ETH
        vm.startPrank(charlie);
        weth.approve(address(vault), 15 ether);
        vault.deposit(15 ether, charlie);
        vm.stopPrank();

        uint256 charlieShares = vault.balanceOf(charlie);
        uint256 totalAssetsAfterCharlie = vault.totalAssets();

        // Verify: All users have shares
        assertGt(aliceShares, 0);
        assertGt(bobShares, 0);
        assertGt(charlieShares, 0);

        // Verify: Total assets increased with each deposit
        assertGt(totalAssetsAfterBob, totalAssetsAfterAlice);
        assertGt(totalAssetsAfterCharlie, totalAssetsAfterBob);

        // Verify: Total supply equals sum of shares
        assertEq(vault.totalSupply(), aliceShares + bobShares + charlieShares);

        // Verify: Shares are proportional to deposits
        // Bob deposited 2x Alice, should have ~2x shares
        assertApproxEqRel(bobShares, aliceShares * 2, 0.05e18); // 5% tolerance
        // Charlie deposited 3x Alice, should have ~3x shares
        assertApproxEqRel(charlieShares, aliceShares * 3, 0.05e18);
    }

    /**
     * @notice Test: Deposit → Pause → Unpause → Deposit
     * Flow: Alice deposits → Admin pauses → Bob tries to deposit (fails) → Admin unpauses → Bob deposits
     */
    function test_Integration_PauseUnpauseFlow() public {
        // Step 1: Alice deposits successfully
        vm.startPrank(alice);
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether, alice);
        vm.stopPrank();

        assertGt(vault.balanceOf(alice), 0);

        // Step 2: Admin pauses vault
        vm.prank(admin);
        vault.pause();

        assertTrue(vault.paused());

        // Step 3: Bob tries to deposit (should fail)
        vm.startPrank(bob);
        weth.approve(address(vault), 5 ether);

        vm.expectRevert();
        vault.deposit(5 ether, bob);

        vm.stopPrank();

        // Bob should have no shares
        assertEq(vault.balanceOf(bob), 0);

        // Step 4: Admin unpauses
        vm.prank(admin);
        vault.unpause();

        assertFalse(vault.paused());

        // Step 5: Bob deposits successfully
        vm.startPrank(bob);
        vault.deposit(5 ether, bob);
        vm.stopPrank();

        assertGt(vault.balanceOf(bob), 0);
    }

    /**
     * @notice Test: Price change handling
     * Flow: Alice deposits → Price changes → Bob deposits → Verify fair share allocation
     */
    function test_Integration_PriceChangeFlow() public {
        // Step 1: Alice deposits at initial prices
        vm.startPrank(alice);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, alice);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 totalAssetsBeforePriceChange = vault.totalAssets();

        // Step 2: Prices change (WETH up 20%, PENGU down 10%)
        pyth.setPrice(WETH_USD_PRICE_ID, 480000000000, 10000000, -8); // $4800
        pyth.setPrice(PENGU_USD_PRICE_ID, 180000000, 1000000, -8);    // $1.80

        uint256 totalAssetsAfterPriceChange = vault.totalAssets();

        // Step 3: Bob deposits at new prices
        vm.startPrank(bob);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, bob);
        vm.stopPrank();

        uint256 bobShares = vault.balanceOf(bob);

        // Verify: Total assets changed due to price change
        assertNotEq(totalAssetsBeforePriceChange, totalAssetsAfterPriceChange);

        // Verify: Bob receives fair shares based on new price
        // When WETH price increases and PENGU decreases, the LP position is worth less in WETH terms
        // So totalAssets (in WETH) decreases, and Bob gets MORE shares for the same deposit
        assertGt(bobShares, aliceShares);
    }

    /**
     * @notice Test: Minimum deposit enforcement across multiple deposits
     */
    function test_Integration_MinimumDepositEnforcement() public {
        // Alice tries to deposit below minimum (should fail)
        vm.startPrank(alice);
        weth.approve(address(vault), 0.009 ether);

        vm.expectRevert("Below minimum deposit");
        vault.deposit(0.009 ether, alice);

        vm.stopPrank();

        // Alice deposits exactly minimum (should succeed)
        vm.startPrank(alice);
        weth.approve(address(vault), 0.01 ether);
        vault.deposit(0.01 ether, alice);
        vm.stopPrank();

        assertGt(vault.balanceOf(alice), 0);

        // Bob deposits above minimum (should succeed)
        vm.startPrank(bob);
        weth.approve(address(vault), 1 ether);
        vault.deposit(1 ether, bob);
        vm.stopPrank();

        assertGt(vault.balanceOf(bob), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Total supply accounting is always correct
     */
    function test_Integration_TotalSupplyAccounting() public {
        // Alice deposits
        vm.startPrank(alice);
        weth.approve(address(vault), 5 ether);
        vault.deposit(5 ether, alice);
        vm.stopPrank();

        assertEq(vault.totalSupply(), vault.balanceOf(alice));

        // Bob deposits
        vm.startPrank(bob);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, bob);
        vm.stopPrank();

        assertEq(vault.totalSupply(), vault.balanceOf(alice) + vault.balanceOf(bob));

        // Charlie deposits
        vm.startPrank(charlie);
        weth.approve(address(vault), 15 ether);
        vault.deposit(15 ether, charlie);
        vm.stopPrank();

        assertEq(vault.totalSupply(), vault.balanceOf(alice) + vault.balanceOf(bob) + vault.balanceOf(charlie));
    }

    /**
     * @notice Test: totalAssets accounting remains consistent
     */
    function test_Integration_TotalAssetsConsistency() public {
        uint256[] memory deposits = new uint256[](3);
        deposits[0] = 5 ether;
        deposits[1] = 10 ether;
        deposits[2] = 15 ether;

        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        uint256 expectedTotal = 0;

        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            weth.approve(address(vault), deposits[i]);
            vault.deposit(deposits[i], users[i]);
            vm.stopPrank();

            expectedTotal += deposits[i];

            // Total assets should approximately equal cumulative deposits
            uint256 actualTotal = vault.totalAssets();
            assertApproxEqRel(actualTotal, expectedTotal, 0.02e18); // 2% tolerance
        }
    }

    /*//////////////////////////////////////////////////////////////
                        SHARE PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Share price evolution
     */
    function test_Integration_SharePriceEvolution() public {
        // Alice deposits 10 ETH
        vm.startPrank(alice);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, alice);
        vm.stopPrank();

        // Calculate initial share price
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 totalAssets1 = vault.totalAssets();
        uint256 sharePrice1 = (totalAssets1 * 1e18) / aliceShares;

        // Bob deposits 10 ETH
        vm.startPrank(bob);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, bob);
        vm.stopPrank();

        // Calculate share price after Bob's deposit
        uint256 totalSupply2 = vault.totalSupply();
        uint256 totalAssets2 = vault.totalAssets();
        uint256 sharePrice2 = (totalAssets2 * 1e18) / totalSupply2;

        // Share price should remain stable (no yield compounded yet)
        assertApproxEqRel(sharePrice2, sharePrice1, 0.02e18); // 2% tolerance

        console2.log("Share price 1:", sharePrice1);
        console2.log("Share price 2:", sharePrice2);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE FLOWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Vault restart after full drain
     */
    function test_Integration_VaultRestart() public {
        // Alice deposits (first position)
        vm.startPrank(alice);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, alice);
        vm.stopPrank();

        uint256 firstTokenId = vault.nftTokenId();
        assertGt(firstTokenId, 0);

        // Note: Withdrawal not implemented yet, so we can't fully test drain
        // But we can test that subsequent deposits work

        // Bob deposits (increases existing position)
        vm.startPrank(bob);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, bob);
        vm.stopPrank();

        // NFT ID should remain the same (same position)
        assertEq(vault.nftTokenId(), firstTokenId);
    }

    /**
     * @notice Test: Large number of sequential deposits
     */
    function test_Integration_ManySequentialDeposits() public {
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(1000 + i));
            vm.deal(user, 10 ether);

            vm.startPrank(user);
            weth.deposit{value: 1 ether}();
            weth.approve(address(vault), 1 ether);
            vault.deposit(1 ether, user);
            vm.stopPrank();

            assertGt(vault.balanceOf(user), 0);
        }

        // Total supply should equal sum of all user balances
        uint256 totalUserShares = 0;
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(1000 + i));
            totalUserShares += vault.balanceOf(user);
        }

        assertEq(vault.totalSupply(), totalUserShares);
    }

    /*//////////////////////////////////////////////////////////////
                        EVENT EMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Deposit emits correct events
     */
    function test_Integration_DepositEvents() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);

        // Expect Deposit event from ERC4626
        vm.expectEmit(true, true, false, false);
        emit Deposit(alice, alice, depositAmount, 0); // shares amount will vary

        vault.deposit(depositAmount, alice);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SLIPPAGE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test: Slippage protection is applied on all swaps
     */
    function test_Integration_SlippageProtection() public {
        // Verify slippage constant
        assertEq(vault.MAX_SLIPPAGE_BPS(), 50); // 0.5%

        // Deposit triggers swap with slippage protection
        vm.startPrank(alice);
        weth.approve(address(vault), 10 ether);
        vault.deposit(10 ether, alice);
        vm.stopPrank();

        // Deposit should succeed (mock router respects slippage)
        assertGt(vault.balanceOf(alice), 0);
    }
}
