// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ICLGauge} from "../../src/interfaces/ICLGauge.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {PythStructs} from "@pythnetwork/PythStructs.sol";

/**
 * @title MockWETH
 * @notice Mock WETH contract for testing
 */
contract MockWETH is ERC20, IWETH {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/**
 * @title MockPENGU
 * @notice Mock PENGU token for testing
 */
contract MockPENGU is ERC20 {
    constructor() ERC20("Pudgy Penguins", "PENGU") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockPyth
 * @notice Mock Pyth oracle for testing
 */
contract MockPyth is IPyth {
    struct StoredPrice {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    mapping(bytes32 => StoredPrice) public prices;

    function setPrice(bytes32 id, int64 price, uint64 conf, int32 expo) external {
        prices[id] = StoredPrice({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: block.timestamp
        });
    }

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (PythStructs.Price memory) {
        StoredPrice memory stored = prices[id];
        require(block.timestamp - stored.publishTime <= age, "Price too old");

        return PythStructs.Price({
            price: stored.price,
            conf: stored.conf,
            expo: stored.expo,
            publishTime: stored.publishTime
        });
    }

    // Implement other IPyth functions
    function getPrice(bytes32) external pure returns (PythStructs.Price memory) {
        revert("Use getPriceNoOlderThan");
    }

    function getEmaPrice(bytes32) external pure returns (PythStructs.Price memory) {
        revert("Not implemented");
    }

    function getEmaPriceUnsafe(bytes32) external pure returns (PythStructs.Price memory) {
        revert("Not implemented");
    }

    function getEmaPriceNoOlderThan(bytes32, uint256) external pure returns (PythStructs.Price memory) {
        revert("Not implemented");
    }

    function getPriceUnsafe(bytes32) external pure returns (PythStructs.Price memory) {
        revert("Not implemented");
    }

    function getUpdateFee(bytes[] calldata) external pure returns (uint256) {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {}

    function updatePriceFeedsIfNecessary(bytes[] calldata, bytes32[] calldata, uint64[] calldata) external payable {}

    function parsePriceFeedUpdates(
        bytes[] calldata,
        bytes32[] calldata,
        uint64,
        uint64
    ) external payable returns (PythStructs.PriceFeed[] memory) {
        return new PythStructs.PriceFeed[](0);
    }

    function getValidTimePeriod() external pure returns (uint256) {
        return 60;
    }
}

/**
 * @title MockRouter
 * @notice Mock Aborean Router for testing swaps
 */
contract MockRouter is IRouter {
    address public immutable wethAddr;
    address public immutable penguAddr;

    // Mock exchange rate: 1 WETH = 2000 PENGU
    uint256 public constant EXCHANGE_RATE = 2000;

    constructor(address _weth, address _pengu) {
        wethAddr = _weth;
        penguAddr = _pengu;
    }

    function weth() external view returns (address) {
        return wethAddr;
    }

    function voter() external pure returns (address) {
        return address(0);
    }

    function factoryRegistry() external pure returns (address) {
        return address(0);
    }

    function defaultFactory() external pure returns (address) {
        return address(0);
    }

    function sortTokens(address tokenA, address tokenB)
        external
        pure
        returns (address token0, address token1)
    {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function poolFor(address, address, bool, address) external pure returns (address) {
        return address(0);
    }

    function getReserves(address, address, bool, address)
        external
        pure
        returns (uint256, uint256)
    {
        return (0, 0);
    }

    function getAmountsOut(uint256 amountIn, Route[] memory) external pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * EXCHANGE_RATE;
        return amounts;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] memory routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Expired");
        require(routes.length > 0, "No routes");

        Route memory route = routes[0];

        // Transfer input token from sender
        IERC20(route.from).transferFrom(msg.sender, address(this), amountIn);

        // Calculate output amount
        uint256 amountOut = amountIn * EXCHANGE_RATE;
        require(amountOut >= amountOutMin, "Slippage");

        // Mint output tokens to recipient (for testing)
        MockPENGU(penguAddr).mint(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    // Other router functions not needed for basic tests
    function swapExactETHForTokens(uint256, Route[] memory, address, uint256) external payable returns (uint256[] memory) {
        revert("Not implemented");
    }

    function swapExactTokensForETH(uint256, uint256, Route[] memory, address, uint256) external returns (uint256[] memory) {
        revert("Not implemented");
    }

    function addLiquidity(
        address, address, bool, uint256, uint256, uint256, uint256, address, uint256
    ) external returns (uint256, uint256, uint256) {
        revert("Not implemented");
    }

    function removeLiquidity(
        address, address, bool, uint256, uint256, uint256, address, uint256
    ) external returns (uint256, uint256) {
        revert("Not implemented");
    }
}

/**
 * @title MockPositionManager
 * @notice Mock Concentrated Liquidity Position Manager (NFT)
 */
contract MockPositionManager is ERC721 {
    uint256 private _nextTokenId = 1;

    struct Position {
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    mapping(uint256 => Position) public positionData;

    constructor() ERC721("Mock CL Position", "MOCK-POS") {}

    function WETH9() external pure returns (address) {
        return address(0);
    }

    function mint(INonfungiblePositionManager.MintParams calldata params) external payable returns (
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        tokenId = _nextTokenId++;

        // Simple mock liquidity calculation
        liquidity = uint128(params.amount0Desired + params.amount1Desired);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        // Store position data
        positionData[tokenId] = Position({
            token0: params.token0,
            token1: params.token1,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity
        });

        // Mint NFT to recipient
        _mint(params.recipient, tokenId);

        // Transfer tokens from sender
        IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);

        return (tokenId, liquidity, amount0, amount1);
    }

    function increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params) external payable returns (
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) {
        require(_ownerOf(params.tokenId) == msg.sender || getApproved(params.tokenId) == msg.sender, "Not authorized");

        Position storage pos = positionData[params.tokenId];

        // Simple mock: add amounts to liquidity
        liquidity = uint128(params.amount0Desired + params.amount1Desired);
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        pos.liquidity += liquidity;

        // Transfer tokens from sender
        IERC20(pos.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(pos.token1).transferFrom(msg.sender, address(this), amount1);

        return (liquidity, amount0, amount1);
    }

    function positions(uint256 tokenId) external view returns (
        uint96 nonce,
        address operator,
        address token0,
        address token1,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        Position memory pos = positionData[tokenId];
        return (
            0, // nonce
            address(0), // operator
            pos.token0,
            pos.token1,
            200, // tickSpacing (CL200)
            pos.tickLower,
            pos.tickUpper,
            pos.liquidity,
            0, // feeGrowthInside0LastX128
            0, // feeGrowthInside1LastX128
            0, // tokensOwed0
            0  // tokensOwed1
        );
    }

    // Implement other required functions as no-ops
    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata) external payable returns (uint256, uint256) {
        revert("Not implemented");
    }

    function collect(INonfungiblePositionManager.CollectParams calldata) external payable returns (uint256, uint256) {
        revert("Not implemented");
    }

    function burn(uint256) external payable {
        revert("Not implemented");
    }

    function createAndInitializePoolIfNecessary(
        address, address, int24, uint160
    ) external payable returns (address) {
        revert("Not implemented");
    }
}

/**
 * @title MockCLGauge
 * @notice Mock Concentrated Liquidity Gauge for testing staking
 */
contract MockCLGauge is ICLGauge {
    mapping(uint256 => address) public stakedNFTs;
    address public positionManager;

    constructor(address _positionManager) {
        positionManager = _positionManager;
    }

    function nft() external view returns (address) {
        return positionManager;
    }

    function pool() external pure returns (address) {
        return address(0);
    }

    function rewardToken() external pure returns (address) {
        return address(0);
    }

    function feesVotingReward() external pure returns (address) {
        return address(0);
    }

    function deposit(uint256 tokenId) external {
        // Transfer NFT from sender to gauge
        ERC721(positionManager).transferFrom(msg.sender, address(this), tokenId);
        stakedNFTs[tokenId] = msg.sender;
    }

    function withdraw(uint256 tokenId) external {
        require(stakedNFTs[tokenId] == msg.sender, "Not owner");

        // Transfer NFT back to sender
        ERC721(positionManager).transferFrom(address(this), msg.sender, tokenId);
        delete stakedNFTs[tokenId];
    }

    function getReward(uint256) external pure {
        // No-op for now
    }

    function getReward(address) external pure {
        // No-op for now
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function earned(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function stakedValues(address) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function stakedByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function stakedContains(address, uint256) external pure returns (bool) {
        return false;
    }

    function stakedLength(address) external pure returns (uint256) {
        return 0;
    }

    function isPool() external pure returns (bool) {
        return false;
    }

    function token0() external pure returns (address) {
        return address(0);
    }

    function token1() external pure returns (address) {
        return address(0);
    }

    function tickSpacing() external pure returns (int24) {
        return 200;
    }

    function fees0() external pure returns (uint256) {
        return 0;
    }

    function fees1() external pure returns (uint256) {
        return 0;
    }
}

/**
 * @title MockUniswapV3Pool
 * @notice Mock pool for slot0() price queries
 */
contract MockUniswapV3Pool {
    uint160 public sqrtPriceX96;
    int24 public tick;

    function setSqrtPriceX96(uint160 _price, int24 _tick) external {
        sqrtPriceX96 = _price;
        tick = _tick;
    }

    function slot0() external view returns (
        uint160 _sqrtPriceX96,
        int24 _tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, true);
    }
}
