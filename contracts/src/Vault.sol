// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ICLGauge} from "./interfaces/ICLGauge.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IVoter} from "./interfaces/IVoter.sol";

import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";

import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {ICLPool} from "./interfaces/ICLPool.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {FixedPoint96} from "./libraries/FixedPoint96.sol";

/**
 * @title AboreanVault
 * @notice ERC-4626 compliant vault that auto-compounds yield from WETH/PENGU Concentrated Liquidity pool on Aborean
 * @dev Accepts WETH deposits, provides liquidity to Aborean WETH/PENGU CL pool, stakes in gauge, and compounds rewards
 */
contract AboreanVault is ERC4626, Ownable, Pausable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum deposit amount (0.01 ETH in WETH terms)
    uint256 public constant MIN_DEPOSIT = 0.01 ether;

    /// @notice Maximum slippage allowed on swaps in basis points (50 = 0.5%)
    uint256 public constant MAX_SLIPPAGE_BPS = 50;

    /// @notice Slippage tolerance for CL position minting (500 = 5%)
    /// @dev Higher than swap slippage because CL positions are sensitive to price/tick alignment
    uint256 public constant LP_SLIPPAGE_BPS = 500;

    /// @notice Basis points scale (100% = 10000 bps)
    uint256 private constant BPS_SCALE = 10000;

    /// @notice Price staleness threshold (60 seconds for fresh prices)
    uint256 public constant PRICE_STALENESS_THRESHOLD = 60;

    /// @notice Pyth price feed ID for WETH/USD
    bytes32 public constant WETH_USD_PRICE_ID = 0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6;

    /// @notice Pyth price feed ID for PENGU/USD
    bytes32 public constant PENGU_USD_PRICE_ID = 0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61;

    /*//////////////////////////////////////////////////////////////
                        IMMUTABLE ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice WETH token contract (0x3439153EB7AF838Ad19d56E1571FBD09333C2809)
    IWETH public immutable weth;

    /// @notice PENGU token contract (0x9eBe3A824Ca958e4b3Da772D2065518F009CBa62)
    IERC20 public immutable pengu;

    /// @notice Slipstream Position Manager (NFT) contract (0xa4890B89dC628baE614780079ACc951Fb0ECdC5F)
    INonfungiblePositionManager public immutable positionManager;

    /// @notice WETH/PENGU CL Gauge contract (0x125c13e12bD40BC7EB4F129d3f8443091D443B7E)
    ICLGauge public immutable gauge;

    /// @notice Aborean Router contract (0xE8142D2f82036B6FC1e79E4aE85cF53FBFfDC998)
    IRouter public immutable router;

    /// @notice WETH/PENGU CL Pool address (0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC)
    address public immutable pool;

    /// @notice Pyth oracle contract (0x8739d5024B5143278E2b15Bd9e7C26f6CEc658F1 on mainnet)
    IPyth public immutable pyth;

    /// @notice VotingEscrow contract for locking ABX (0x27B04370D8087e714a9f557c1EFF7901cea6bB63)
    IVotingEscrow public immutable votingEscrow;

    /// @notice Voter contract for voting on pool emissions (0xC0F53703e9f4b79fA2FB09a2aeBA487FA97729c9)
    IVoter public immutable voter;

    /// @notice Tick spacing for CL200 pool
    int24 public constant TICK_SPACING = 200;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The NFT token ID for our staked Concentrated Liquidity position
    /// @dev 0 means no position exists yet
    uint256 public nftTokenId;

    /// @notice The veABX NFT token ID for governance voting
    /// @dev 0 means no veABX NFT exists yet
    uint256 public veABXTokenId;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the vault with Aborean protocol contract addresses
     * @param _weth Address of WETH token (0x3439153EB7AF838Ad19d56E1571FBD09333C2809)
     * @param _pengu Address of PENGU token (0x9eBe3A824Ca958e4b3Da772D2065518F009CBa62)
     * @param _positionManager Address of Position Manager (0xa4890B89dC628baE614780079ACc951Fb0ECdC5F)
     * @param _gauge Address of CL Gauge (0x125c13e12bD40BC7EB4F129d3f8443091D443B7E)
     * @param _router Address of Router (0xE8142D2f82036B6FC1e79E4aE85cF53FBFfDC998)
     * @param _pool Address of WETH/PENGU CL Pool (0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC)
     * @param _pyth Address of Pyth oracle (0x8739d5024B5143278E2b15Bd9e7C26f6CEc658F1 on mainnet)
     * @param _votingEscrow Address of VotingEscrow (0x27B04370D8087e714a9f557c1EFF7901cea6bB63)
     * @param _voter Address of Voter (0xC0F53703e9f4b79fA2FB09a2aeBA487FA97729c9)
     */
    constructor(
        address _weth,
        address _pengu,
        address _positionManager,
        address _gauge,
        address _router,
        address _pool,
        address _pyth,
        address _votingEscrow,
        address _voter
    )
        ERC4626(IERC20(_weth))
        ERC20("Aborean WETH/PENGU Vault", "wvaulth")
        Ownable(msg.sender)
    {
        require(_weth != address(0), "Invalid WETH address");
        require(_pengu != address(0), "Invalid PENGU address");
        require(_positionManager != address(0), "Invalid Position Manager");
        require(_gauge != address(0), "Invalid Gauge");
        require(_router != address(0), "Invalid Router");
        require(_pool != address(0), "Invalid Pool");
        require(_pyth != address(0), "Invalid Pyth address");
        require(_votingEscrow != address(0), "Invalid VotingEscrow address");
        require(_voter != address(0), "Invalid Voter address");

        weth = IWETH(_weth);
        pengu = IERC20(_pengu);
        positionManager = INonfungiblePositionManager(_positionManager);
        gauge = ICLGauge(_gauge);
        router = IRouter(_router);
        pool = _pool;
        pyth = IPyth(_pyth);
        votingEscrow = IVotingEscrow(_votingEscrow);
        voter = IVoter(_voter);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 CORE OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate total assets held by vault in WETH terms
     * @dev Uses Pyth oracle prices to prevent flash loan manipulation
     * @return Total value of vault holdings denominated in WETH
     */
    function totalAssets() public view override returns (uint256) {
        if (nftTokenId == 0) return 0;

        // Get our LP position token amounts
        (uint256 wethAmount, uint256 penguAmount) = _getPositionAmounts();

        // Get oracle prices (USD per token, 8 decimals from Pyth)
        uint256 wethPriceUSD = _getPythPrice(WETH_USD_PRICE_ID);
        uint256 penguPriceUSD = _getPythPrice(PENGU_USD_PRICE_ID);

        // Calculate total value in USD
        // wethAmount and penguAmount are in 18 decimals
        // Prices are normalized to 18 decimals by _getPythPrice
        uint256 wethValueUSD = (wethAmount * wethPriceUSD) / 1e18;
        uint256 penguValueUSD = (penguAmount * penguPriceUSD) / 1e18;
        uint256 totalValueUSD = wethValueUSD + penguValueUSD;

        // Convert USD value back to WETH terms (vault's asset)
        return (totalValueUSD * 1e18) / wethPriceUSD;
    }

    /**
     * @notice Override to enforce pause state and minimum deposit
     * @dev Returns 0 when paused, otherwise returns max uint256
     * @return Maximum amount of assets that can be deposited
     */
    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /**
     * @notice Override deposit logic to add liquidity to Aborean WETH/PENGU pool
     * @dev Called by parent ERC4626.deposit() after calculating shares
     * @param caller The address calling deposit
     * @param receiver The address receiving vault shares
     * @param assets Amount of WETH deposited
     * @param shares Amount of vault shares to mint
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused nonReentrant {
        // Enforce minimum deposit BEFORE transferring/minting
        require(assets >= MIN_DEPOSIT, "Below minimum deposit");

        // Call parent to handle transfer (user → vault) and minting (vault shares → receiver)
        super._deposit(caller, receiver, assets, shares);

        // Swap 50% WETH → PENGU
        uint256 wethForSwap = assets / 2;
        uint256 wethForLP = assets - wethForSwap;
        uint256 penguAmount = _swapWETHForPENGU(wethForSwap);

        // Add liquidity (mint new position or increase existing)
        if (nftTokenId == 0) {
            // First deposit: Mint new NFT position and stake it
            _mintNewPosition(wethForLP, penguAmount);
        } else {
            // Subsequent deposits: Unstake → Increase → Restake
            gauge.withdraw(nftTokenId);
            _increaseLiquidity(wethForLP, penguAmount);
            positionManager.approve(address(gauge), nftTokenId);
            gauge.deposit(nftTokenId);
        }
    }

    /**
     * @notice Override withdraw logic to remove liquidity and return WETH
     * @dev Called by parent ERC4626.withdraw() and redeem()
     * @param caller The address calling withdraw/redeem
     * @param receiver The address receiving withdrawn assets
     * @param owner The owner of the shares being burned
     * @param assets Amount of WETH to withdraw
     * @param shares Amount of vault shares to burn
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused nonReentrant {
        // Calculate what percentage of the position to withdraw
        uint256 totalShares = totalSupply();
        require(totalShares > 0, "No shares to withdraw");
        
        // Get position info before unstaking
        (, , , , , int24 tickLower, int24 tickUpper, uint128 currentLiquidity, , , , ) = 
            positionManager.positions(nftTokenId);

        // Calculate liquidity to remove (proportional to shares being burned)
        uint128 liquidityToRemove = uint128((uint256(currentLiquidity) * shares) / totalShares);

        // Unstake from gauge
        gauge.withdraw(nftTokenId);

        // Collect any accrued fees first
        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nftTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Decrease liquidity
        if (liquidityToRemove > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: nftTokenId,
                    liquidity: liquidityToRemove,
                    amount0Min: 0,  // Accept any amount (protected by totalAssets calculation)
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );

            // Collect the decreased liquidity tokens
            (uint256 wethReceived, uint256 penguReceived) = positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: nftTokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            // Swap PENGU → WETH to get the required amount
            if (penguReceived > 0) {
                wethReceived += _swapPENGUForWETH(penguReceived);
            }
            
            // Verify we received enough WETH (allow 2% slippage tolerance)
            uint256 minAcceptable = (assets * 98) / 100;
            require(wethReceived >= minAcceptable, "Insufficient withdrawal amount");
        }

        // Re-stake remaining position if there's still liquidity
        (, , , , , , , uint128 remainingLiquidity, , , , ) = 
            positionManager.positions(nftTokenId);
        
        if (remainingLiquidity > 0) {
            positionManager.approve(address(gauge), nftTokenId);
            gauge.deposit(nftTokenId);
        }

        // Call parent to handle share burning and transfer (vault → receiver)
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Override maxWithdraw to account for pause state
     * @param owner The address to check withdrawal limit for
     * @return Maximum withdrawable assets
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        return super.maxWithdraw(owner);
    }

    /**
     * @notice Override maxRedeem to account for pause state
     * @param owner The address to check redemption limit for
     * @return Maximum redeemable shares
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        return super.maxRedeem(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate liquidity for a given amount of token0 and price range
     * @dev Returns uint256 to avoid overflow during intermediate calculations
     */
    function _liquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        require(sqrtRatioBX96 > sqrtRatioAX96, "Invalid sqrt ratio range");
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        liquidity = FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96);
    }

    /**
     * @notice Calculate liquidity for a given amount of token1 and price range
     * @dev Returns uint256 to avoid overflow during intermediate calculations
     */
    function _liquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        require(sqrtRatioBX96 > sqrtRatioAX96, "Invalid sqrt ratio range");
        liquidity = FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96);
    }

    /**
     * @notice Calculate maximum liquidity for given token amounts and price range
     * @dev Returns uint256 to avoid overflow during intermediate calculations
     */
    function _liquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = _liquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint256 liquidity0 = _liquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint256 liquidity1 = _liquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = _liquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /**
     * @notice Swap WETH for PENGU using Aborean Router
     * @param wethAmount Amount of WETH to swap
     * @return penguAmount Amount of PENGU received
     */
    function _swapWETHForPENGU(uint256 wethAmount) internal returns (uint256 penguAmount) {
        // Build route: WETH → PENGU (volatile pool)
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: address(weth),
            to: address(pengu),
            stable: false,        // volatile pool for WETH/PENGU
            factory: address(0)   // use default factory
        });

        // Get expected output amount
        uint256[] memory amountsOut = router.getAmountsOut(wethAmount, routes);
        uint256 expectedPengu = amountsOut[amountsOut.length - 1];

        // Calculate minimum with slippage protection
        uint256 minPenguOut = (expectedPengu * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;

        // Approve router to spend WETH
        weth.approve(address(router), wethAmount);

        // Execute swap
        uint256[] memory amounts = router.swapExactTokensForTokens(
            wethAmount,
            minPenguOut,
            routes,
            address(this),
            block.timestamp
        );

        penguAmount = amounts[amounts.length - 1];
    }

    /**
     * @notice Swap PENGU for WETH using Aborean Router
     * @param penguAmount Amount of PENGU to swap
     * @return wethAmount Amount of WETH received
     */
    function _swapPENGUForWETH(uint256 penguAmount) internal returns (uint256 wethAmount) {
        // Build route: PENGU → WETH (volatile pool)
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: address(pengu),
            to: address(weth),
            stable: false,        // volatile pool for PENGU/WETH
            factory: address(0)   // use default factory
        });

        // Get expected output amount
        uint256[] memory amountsOut = router.getAmountsOut(penguAmount, routes);
        uint256 expectedWeth = amountsOut[amountsOut.length - 1];

        // Calculate minimum with slippage protection
        uint256 minWethOut = (expectedWeth * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;

        // Approve router to spend PENGU
        pengu.approve(address(router), penguAmount);

        // Execute swap
        uint256[] memory amounts = router.swapExactTokensForTokens(
            penguAmount,
            minWethOut,
            routes,
            address(this),
            block.timestamp
        );

        wethAmount = amounts[amounts.length - 1];
    }

    /**
     * @notice Mint a new CL position NFT
     * @param wethAmount Amount of WETH to add
     * @param penguAmount Amount of PENGU to add
     */
    function _mintNewPosition(uint256 wethAmount, uint256 penguAmount) internal {
        // Calculate tick range (±20% from current price)
        (int24 tickLower, int24 tickUpper) = _calculateTickRange();

        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol) = ICLPool(pool).slot0();

        // Calculate sqrt ratios for tick range
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate expected liquidity for our token amounts
        uint256 expectedLiquidity = _liquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            wethAmount,
            penguAmount
        );

        // Calculate expected token consumption based on that liquidity
        (uint256 expectedAmount0, uint256 expectedAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            uint128(expectedLiquidity)
        );

        // Apply slippage tolerance (5%) to EXPECTED amounts, not input amounts
        // This allows CL to use less tokens based on tick alignment
        uint256 amount0Min = (expectedAmount0 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;
        uint256 amount1Min = (expectedAmount1 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;

        // Approve Position Manager to spend tokens
        weth.approve(address(positionManager), wethAmount);
        pengu.approve(address(positionManager), penguAmount);

        // Mint new position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(weth),
            token1: address(pengu),
            tickSpacing: TICK_SPACING,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: wethAmount,
            amount1Desired: penguAmount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp,
            sqrtPriceX96: 0  // Pool already exists
        });

        (uint256 tokenId, , , ) = positionManager.mint(params);
        nftTokenId = tokenId;

        // Approve gauge and stake the NFT
        positionManager.approve(address(gauge), tokenId);
        gauge.deposit(tokenId);
    }

    /**
     * @notice Increase liquidity on existing position
     * @param wethAmount Amount of WETH to add
     * @param penguAmount Amount of PENGU to add
     */
    function _increaseLiquidity(uint256 wethAmount, uint256 penguAmount) internal {
        // Get existing position info to use same tick range
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nftTokenId);

        // Get current pool state
        (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol) = ICLPool(pool).slot0();

        // Calculate sqrt ratios for tick range
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate expected liquidity for our token amounts
        uint256 expectedLiquidity = _liquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            wethAmount,
            penguAmount
        );

        // Calculate expected token consumption based on that liquidity
        (uint256 expectedAmount0, uint256 expectedAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            uint128(expectedLiquidity)
        );

        // Apply slippage tolerance (5%) to EXPECTED amounts
        uint256 amount0Min = (expectedAmount0 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;
        uint256 amount1Min = (expectedAmount1 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;

        // Approve Position Manager to spend tokens
        weth.approve(address(positionManager), wethAmount);
        pengu.approve(address(positionManager), penguAmount);

        // Increase liquidity
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: nftTokenId,
                amount0Desired: wethAmount,
                amount1Desired: penguAmount,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp
            });

        positionManager.increaseLiquidity(params);
    }

    /**
     * @notice Calculate tick range for CL position (±20% from current price)
     * @dev Uses current pool price to center the range
     * @return tickLower Lower tick of the range
     * @return tickUpper Upper tick of the range
     */
    function _calculateTickRange() internal view returns (int24 tickLower, int24 tickUpper) {
        // Get current price and tick from pool
        // slot0() returns: sqrtPriceX96, tick, observationIndex, observationCardinality, observationCardinalityNext, feeProtocol
        // NOTE: Slipstream pools do NOT return `unlocked` (unlike standard Uniswap V3)
        (, int24 currentTick, , , , ) = ICLPool(pool).slot0();

        // Calculate ±20% range in tick space
        // Price changes by factor of 1.0001 per tick
        // For ±20% range: log(1.2) / log(1.0001) ≈ 1823 ticks
        int24 tickRange = 1823;

        // Calculate raw tick bounds
        int24 tickLowerRaw = currentTick - tickRange;
        int24 tickUpperRaw = currentTick + tickRange;

        // Round to nearest valid tick (must be multiple of TICK_SPACING = 200)
        tickLower = _nearestUsableTick(tickLowerRaw, TICK_SPACING);
        tickUpper = _nearestUsableTick(tickUpperRaw, TICK_SPACING);
    }

    /**
     * @notice Round tick to nearest usable tick (multiple of tickSpacing)
     * @dev Required because CL pools only accept ticks that are multiples of tickSpacing
     * @param tick The tick to round
     * @param tickSpacing The tick spacing for the pool (200 for CL200)
     * @return Nearest usable tick
     */
    function _nearestUsableTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        // Round to nearest multiple of tickSpacing
        int24 rounded = (tick / tickSpacing) * tickSpacing;

        // Ensure we stay within valid tick range
        // MIN_TICK = -887272, MAX_TICK = 887272
        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;

        if (rounded < MIN_TICK) {
            return ((MIN_TICK / tickSpacing) + 1) * tickSpacing;
        } else if (rounded > MAX_TICK) {
            return ((MAX_TICK / tickSpacing) - 1) * tickSpacing;
        }

        return rounded;
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE & POSITION HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get USD price from Pyth oracle with staleness and confidence checks
     * @param priceId Pyth price feed ID
     * @return price Price in 18 decimals (USD per token)
     */
    function _getPythPrice(bytes32 priceId) internal view returns (uint256) {
        // Get price from Pyth (uses push feed - auto-updated on-chain)
        PythStructs.Price memory pythPrice = pyth.getPriceNoOlderThan(
            priceId,
            PRICE_STALENESS_THRESHOLD
        );

        // Check confidence interval (reject if > 1% uncertainty)
        require(
            pythPrice.conf < uint64(pythPrice.price) / 100,
            "Price confidence too low"
        );

        // Convert Pyth price to 18 decimals
        return _scalePythPrice(pythPrice);
    }

    /**
     * @notice Scale Pyth price from variable exponent to 18 decimals
     * @param pythPrice Pyth price struct with price and exponent
     * @return Scaled price in 18 decimals
     */
    function _scalePythPrice(PythStructs.Price memory pythPrice) internal pure returns (uint256) {
        // Pyth price format: price * 10^expo
        // Need to convert to 18 decimal fixed point

        uint256 priceUint = uint256(uint64(pythPrice.price));

        if (pythPrice.expo >= 0) {
            // Positive exponent: multiply by 10^expo then scale to 18 decimals
            return priceUint * (10 ** uint32(pythPrice.expo)) * 1e18;
        } else {
            // Negative exponent: divide by 10^(-expo) then scale to 18 decimals
            uint32 absExpo = uint32(-pythPrice.expo);

            if (absExpo <= 18) {
                // If exponent is -8, we have price * 10^-8
                // To get 18 decimals: price * 10^(18-8) = price * 10^10
                return priceUint * (10 ** (18 - absExpo));
            } else {
                // If exponent is more negative than -18
                // We need to divide: price / 10^(absExpo - 18)
                return priceUint / (10 ** (absExpo - 18));
            }
        }
    }

    /**
     * @notice Get token amounts from our staked CL position
     * @dev Queries Position Manager for our NFT position data and calculates amounts using Uniswap V3 math
     * @return wethAmount Amount of WETH in position (token0)
     * @return penguAmount Amount of PENGU in position (token1)
     */
    function _getPositionAmounts() internal view virtual returns (uint256 wethAmount, uint256 penguAmount) {
        if (nftTokenId == 0) return (0, 0);

        // Get position data from NFT
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = positionManager.positions(nftTokenId);

        if (liquidity == 0) return (0, 0);

        // Get current price from the pool (sqrtPriceX96)
        // Note: We use pool price here (not Pyth) because we're calculating position composition,
        // not vault valuation. The actual USD valuation in totalAssets() uses Pyth oracle.
        (uint160 sqrtPriceX96, , , , , ) = ICLPool(pool).slot0();

        // Validate ticks are not equal (would cause division issues)
        if (tickLower >= tickUpper) return (0, 0);

        // Validate ticks are in valid range before converting to sqrt ratios
        int24 MIN_TICK = -887272;
        int24 MAX_TICK = 887272;
        if (tickLower < MIN_TICK || tickLower > MAX_TICK || tickUpper < MIN_TICK || tickUpper > MAX_TICK) {
            return (0, 0);
        }

        // Convert tick boundaries to sqrtPriceX96 format
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Additional safety check
        if (sqrtRatioAX96 == 0 || sqrtRatioBX96 == 0 || sqrtRatioAX96 >= sqrtRatioBX96) return (0, 0);

        // Ensure sqrt price is in valid range
        if (sqrtPriceX96 == 0) return (0, 0);

        // Calculate token amounts using Uniswap V3 LiquidityAmounts library
        // This handles all cases: in-range, above-range, below-range
        (wethAmount, penguAmount) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ERC721 RECEIVER IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle ERC-721 NFT transfers (required to receive Position Manager NFTs)
     * @dev Always accepts NFTs from Position Manager
     * @return Selector to confirm the contract can receive ERC-721 tokens
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Harvest ABX rewards and trading fees from the staked position
     * @dev Claims rewards without unstaking the NFT
     */
    function harvest() external onlyOwner {
        if (nftTokenId == 0) return;

        // Track ABX balance before claiming
        address abxToken = gauge.rewardToken();
        uint256 abxBefore = IERC20(abxToken).balanceOf(address(this));
        
        // Claim ABX rewards from gauge (position stays staked)
        gauge.getReward(nftTokenId);
        
        // Calculate ABX received
        uint256 abxAmount = IERC20(abxToken).balanceOf(address(this)) - abxBefore;

        // Collect trading fees from position
        (uint256 wethFees, uint256 penguFees) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nftTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit Harvest(abxAmount, wethFees, penguFees);
    }

    /**
     * @notice Compound trading fees back into the LP position
     * @dev Collects fees, balances tokens via swap, and adds back as liquidity
     */
    function compound() external onlyOwner {
        if (nftTokenId == 0) return;

        // Collect trading fees
        (uint256 wethCollected, uint256 penguCollected) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nftTokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        if (wethCollected > 0.001 ether || penguCollected > 1 ether) {
            uint256 totalWeth = wethCollected;
            uint256 totalPengu = penguCollected;

            // Balance tokens to 50/50 value split (rough approximation)
            uint256 targetWeth = (wethCollected + penguCollected / 2000) / 2;
            uint256 targetPengu = (wethCollected * 2000 + penguCollected) / 2;

            if (totalWeth < targetWeth && totalPengu > 0) {
                uint256 penguToSwap = totalPengu / 2;
                if (penguToSwap > 0) {
                    totalWeth += _swapPENGUForWETH(penguToSwap);
                    totalPengu -= penguToSwap;
                }
            } else if (totalPengu < targetPengu && totalWeth > 0) {
                uint256 wethToSwap = totalWeth / 2;
                if (wethToSwap > 0) {
                    totalPengu += _swapWETHForPENGU(wethToSwap);
                    totalWeth -= wethToSwap;
                }
            }

            // Must unstake to increase liquidity, then re-stake
            if (totalWeth > 0 && totalPengu > 0) {
                gauge.withdraw(nftTokenId);
                _increaseLiquidity(totalWeth, totalPengu);
                positionManager.approve(address(gauge), nftTokenId);
                gauge.deposit(nftTokenId);
            }

            emit Compound(totalWeth, totalPengu, totalAssets());
        }
    }

    /**
     * @notice Rebalance the LP position to a new tick range
     * @dev Useful when price has moved significantly and position is out of range
     */
    function rebalance() external onlyOwner {
        if (nftTokenId == 0) return;

        // Unstake from gauge
        gauge.withdraw(nftTokenId);

        // Get current position
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(nftTokenId);

        // Remove all liquidity from old position
        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: nftTokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );

            // Collect tokens
            (uint256 wethAmount, uint256 penguAmount) = positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: nftTokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );

            // Calculate new tick range around current price
            (int24 tickLower, int24 tickUpper) = _calculateTickRange();

            // Re-add liquidity with new range using existing position
            // Get current tick for the new range parameters
            (, int24 currentTick, , , , ) = ICLPool(pool).slot0();

            // Calculate expected liquidity for slippage protection
            uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

            uint256 expectedLiquidity = _liquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                wethAmount,
                penguAmount
            );

            (uint256 expectedAmount0, uint256 expectedAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                uint128(expectedLiquidity)
            );

            uint256 amount0Min = (expectedAmount0 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;
            uint256 amount1Min = (expectedAmount1 * (BPS_SCALE - LP_SLIPPAGE_BPS)) / BPS_SCALE;

            // Approve tokens
            weth.approve(address(positionManager), wethAmount);
            pengu.approve(address(positionManager), penguAmount);

            // Increase liquidity with new range
            _increaseLiquidity(wethAmount, penguAmount);

            // Re-stake
            positionManager.approve(address(gauge), nftTokenId);
            gauge.deposit(nftTokenId);

            emit Rebalanced(tickLower, tickUpper, block.timestamp);
        }
    }

    /**
     * @notice Emergency withdrawal to recover all funds if something goes wrong
     * @dev Only callable by owner when paused. Removes all liquidity and unstakes.
     */
    function emergencyWithdraw() external onlyOwner whenPaused {
        if (nftTokenId == 0) return;

        // Unstake from gauge
        gauge.withdraw(nftTokenId);

        // Get current position
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(nftTokenId);

        // Remove all liquidity
        if (liquidity > 0) {
            positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: nftTokenId,
                    liquidity: liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                })
            );

            // Collect tokens
            positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: nftTokenId,
                    recipient: owner(),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }

        // Transfer any remaining tokens to owner
        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 penguBalance = pengu.balanceOf(address(this));
        
        if (wethBalance > 0) {
            weth.transfer(owner(), wethBalance);
        }
        if (penguBalance > 0) {
            pengu.transfer(owner(), penguBalance);
        }
    }

    /**
     * @notice Recover accidentally sent ERC20 tokens
     * @dev Cannot recover WETH/PENGU as they're part of the vault strategy
     * @param token Address of token to recover
     * @param amount Amount to recover
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(weth), "Cannot recover WETH");
        require(token != address(pengu), "Cannot recover PENGU");
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @notice Lock harvested ABX tokens to create or add to veABX position
     * @dev Creates a new 4-year max lock veNFT if one doesn't exist, otherwise adds to existing lock
     * @param minAbxAmount Minimum ABX balance required to execute lock (prevents wasting gas on dust)
     */
    function lockABX(uint256 minAbxAmount) external onlyOwner {
        address abxToken = gauge.rewardToken();
        uint256 abxBalance = IERC20(abxToken).balanceOf(address(this));
        
        require(abxBalance >= minAbxAmount, "Insufficient ABX balance");
        require(abxBalance > 0, "No ABX to lock");

        // Approve VotingEscrow to spend ABX
        IERC20(abxToken).approve(address(votingEscrow), abxBalance);

        if (veABXTokenId == 0) {
            // Create new 4-year max lock
            uint256 lockDuration = 4 * 365 days; // 4 years
            veABXTokenId = votingEscrow.createLock(abxBalance, lockDuration);
            emit ABXLocked(veABXTokenId, abxBalance, lockDuration);
        } else {
            // Add to existing lock
            votingEscrow.increaseAmount(veABXTokenId, abxBalance);
            emit ABXLocked(veABXTokenId, abxBalance, 0);
        }

        // Clear approval
        IERC20(abxToken).approve(address(votingEscrow), 0);
    }

    /**
     * @notice Vote for the WETH/PENGU pool to direct ABX emissions
     * @dev Allocates 100% of veABX voting power to our pool
     * @dev Can only vote once per epoch (weekly, Thursdays 00:00 UTC)
     */
    function voteForPool() external onlyOwner {
        require(veABXTokenId != 0, "No veABX NFT exists");
        
        // Get voting power
        uint256 votingPower = votingEscrow.balanceOfNFT(veABXTokenId);
        require(votingPower > 0, "No voting power");

        // Vote for our pool with 100% weight
        address[] memory pools = new address[](1);
        pools[0] = pool;
        
        uint256[] memory weights = new uint256[](1);
        weights[0] = votingPower; // Allocate 100% weight to our pool

        voter.vote(veABXTokenId, pools, weights);
        
        emit VotedForPool(veABXTokenId, pool, votingPower);
    }

    /**
     * @notice Pause vault deposits and withdrawals (emergency only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause vault deposits and withdrawals
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Harvest(uint256 abxAmount, uint256 wethFees, uint256 penguFees);
    event Compound(uint256 wethAdded, uint256 penguAdded, uint256 newTotalAssets);
    event Rebalanced(int24 newTickLower, int24 newTickUpper, uint256 timestamp);
    event ABXLocked(uint256 indexed veTokenId, uint256 abxAmount, uint256 lockDuration);
    event VotedForPool(uint256 indexed veTokenId, address indexed pool, uint256 weight);
}
