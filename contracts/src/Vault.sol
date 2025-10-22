// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {ICLGauge} from "./interfaces/ICLGauge.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";

import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @title AboreanVault
 * @notice ERC-4626 compliant vault that auto-compounds yield from WETH/PENGU Concentrated Liquidity pool on Aborean
 * @dev Accepts WETH deposits, provides liquidity to Aborean WETH/PENGU CL pool, stakes in gauge, and compounds rewards
 */
contract AboreanVault is ERC4626, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum deposit amount (0.01 ETH in WETH terms)
    uint256 public constant MIN_DEPOSIT = 0.01 ether;

    /// @notice Maximum slippage allowed on swaps in basis points (50 = 0.5%)
    uint256 public constant MAX_SLIPPAGE_BPS = 50;

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

    /// @notice Tick spacing for CL200 pool
    int24 public constant TICK_SPACING = 200;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The NFT token ID for our staked Concentrated Liquidity position
    /// @dev 0 means no position exists yet
    uint256 public nftTokenId;

    /// @notice The veABX NFT token ID for our locked governance position
    /// @dev 0 means no veABX position exists yet
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
     */
    constructor(
        address _weth,
        address _pengu,
        address _positionManager,
        address _gauge,
        address _router,
        address _pool,
        address _pyth
    )
        ERC4626(IERC20(_weth))
        ERC20("Aborean WETH/PENGU Vault", "aborWETH-PENGU")
        Ownable(msg.sender)
    {
        require(_weth != address(0), "Invalid WETH address");
        require(_pengu != address(0), "Invalid PENGU address");
        require(_positionManager != address(0), "Invalid Position Manager");
        require(_gauge != address(0), "Invalid Gauge");
        require(_router != address(0), "Invalid Router");
        require(_pool != address(0), "Invalid Pool");
        require(_pyth != address(0), "Invalid Pyth address");

        weth = IWETH(_weth);
        pengu = IERC20(_pengu);
        positionManager = INonfungiblePositionManager(_positionManager);
        gauge = ICLGauge(_gauge);
        router = IRouter(_router);
        pool = _pool;
        pyth = IPyth(_pyth);
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

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
     * @notice Mint a new CL position NFT
     * @param wethAmount Amount of WETH to add
     * @param penguAmount Amount of PENGU to add
     */
    function _mintNewPosition(uint256 wethAmount, uint256 penguAmount) internal {
        // Calculate tick range (±20% from current price)
        (int24 tickLower, int24 tickUpper) = _calculateTickRange();

        // Approve Position Manager to spend tokens
        weth.approve(address(positionManager), wethAmount);
        pengu.approve(address(positionManager), penguAmount);

        // Calculate minimum amounts with slippage protection
        uint256 amount0Min = (wethAmount * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;
        uint256 amount1Min = (penguAmount * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;

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
        // Approve Position Manager to spend tokens
        weth.approve(address(positionManager), wethAmount);
        pengu.approve(address(positionManager), penguAmount);

        // Calculate minimum amounts with slippage protection
        uint256 amount0Min = (wethAmount * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;
        uint256 amount1Min = (penguAmount * (BPS_SCALE - MAX_SLIPPAGE_BPS)) / BPS_SCALE;

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
        // Get current price from pool
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        // Convert current sqrtPriceX96 to tick
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

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
        if (rounded < TickMath.MIN_TICK) {
            return ((TickMath.MIN_TICK / tickSpacing) + 1) * tickSpacing;
        } else if (rounded > TickMath.MAX_TICK) {
            return ((TickMath.MAX_TICK / tickSpacing) - 1) * tickSpacing;
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
    function _getPositionAmounts() internal view returns (uint256 wethAmount, uint256 penguAmount) {
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
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        // Convert tick boundaries to sqrtPriceX96 format
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

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
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
    event ABXLocked(uint256 amount, uint256 veABXTokenId);
    event Voted(uint256 veABXTokenId, address indexed pool, uint256 votingPower);
    event Rebalanced(int24 newTickLower, int24 newTickUpper, uint256 timestamp);
}
