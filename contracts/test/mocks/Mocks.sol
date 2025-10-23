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
import {LiquidityAmounts} from "../../src/libraries/LiquidityAmounts.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";

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

    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts) {
        require(routes.length > 0, "No routes");
        Route memory route = routes[0];
        
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        
        // Handle both directions
        if (route.from == wethAddr && route.to == penguAddr) {
            // WETH → PENGU: 1 WETH = 2000 PENGU
            amounts[1] = amountIn * EXCHANGE_RATE;
        } else if (route.from == penguAddr && route.to == wethAddr) {
            // PENGU → WETH: 2000 PENGU = 1 WETH
            amounts[1] = amountIn / EXCHANGE_RATE;
        } else {
            revert("Unsupported route");
        }
        
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

        uint256 amountOut;
        
        // Handle both directions: WETH → PENGU and PENGU → WETH
        if (route.from == wethAddr && route.to == penguAddr) {
            // WETH → PENGU: 1 WETH = 2000 PENGU
            amountOut = amountIn * EXCHANGE_RATE;
            require(amountOut >= amountOutMin, "Slippage");
            MockPENGU(penguAddr).mint(to, amountOut);
        } else if (route.from == penguAddr && route.to == wethAddr) {
            // PENGU → WETH: 2000 PENGU = 1 WETH
            amountOut = amountIn / EXCHANGE_RATE;
            require(amountOut >= amountOutMin, "Slippage");
            IERC20(wethAddr).transfer(to, amountOut);
        } else {
            revert("Unsupported route");
        }

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
 * @dev Simplified mock that tracks actual token amounts deposited
 */
contract MockPositionManager is ERC721 {
    uint256 private _nextTokenId = 1;

    struct Position {
        address token0;
        address token1;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    mapping(uint256 => Position) public positionData;

    constructor() ERC721("Mock CL Position", "MOCK-POS") {}

    /// @notice Helper to get actual deposited amounts (for testing)
    function getDepositedAmounts(uint256 tokenId) external view returns (uint256 amount0, uint256 amount1) {
        Position memory pos = positionData[tokenId];
        return (pos.amount0, pos.amount1);
    }

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

        // For simplicity in mock: just store amounts and use a simple liquidity value
        // The vault will call getAmountsForLiquidity which will incorrectly reverse this,
        // so we need to store amounts directly for accurate testing
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        // Use a simple liquidity value - the position will store actual amounts
        liquidity = uint128(params.amount0Desired + params.amount1Desired);

        // Store position data
        positionData[tokenId] = Position({
            token0: params.token0,
            token1: params.token1,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1
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
        pos.amount0 += amount0;
        pos.amount1 += amount1;

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

    // Implement other required functions
    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        require(getApproved(params.tokenId) == msg.sender || ownerOf(params.tokenId) == msg.sender, "Not authorized");
        
        Position storage pos = positionData[params.tokenId];
        
        // Calculate proportional amounts to return
        if (pos.liquidity > 0) {
            amount0 = (pos.amount0 * params.liquidity) / pos.liquidity;
            amount1 = (pos.amount1 * params.liquidity) / pos.liquidity;
            
            // Update position
            pos.liquidity -= params.liquidity;
            pos.amount0 -= amount0;
            pos.amount1 -= amount1;
        }
        
        return (amount0, amount1);
    }

    function collect(INonfungiblePositionManager.CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        // Allow collection even if NFT is staked (gauge owns it)
        // In reality, the gauge would proxy this call
        
        Position storage pos = positionData[params.tokenId];
        
        // In a real implementation, this would collect accrued fees
        // For mock, we'll return any tokens that were withdrawn via decreaseLiquidity
        // but not yet collected
        amount0 = IERC20(pos.token0).balanceOf(address(this)) > pos.amount0 
            ? IERC20(pos.token0).balanceOf(address(this)) - pos.amount0 
            : 0;
        amount1 = IERC20(pos.token1).balanceOf(address(this)) > pos.amount1
            ? IERC20(pos.token1).balanceOf(address(this)) - pos.amount1
            : 0;
        
        // Transfer tokens to recipient
        if (amount0 > 0) {
            IERC20(pos.token0).transfer(params.recipient, amount0);
        }
        if (amount1 > 0) {
            IERC20(pos.token1).transfer(params.recipient, amount1);
        }
        
        return (amount0, amount1);
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
 * @title MockABX
 * @notice Mock ABX reward token
 */
contract MockABX is ERC20 {
    constructor() ERC20("Mock ABX", "ABX") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockCLGauge
 * @notice Mock Concentrated Liquidity Gauge for testing staking
 */
contract MockCLGauge is ICLGauge {
    mapping(uint256 => address) public stakedNFTs;
    address public positionManager;
    address public immutable abxToken;

    constructor(address _positionManager) {
        positionManager = _positionManager;
        abxToken = address(new MockABX());
    }

    function nft() external view returns (address) {
        return positionManager;
    }

    function pool() external pure returns (address) {
        return address(0);
    }

    function rewardToken() external view returns (address) {
        return abxToken;
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

    function getReward(uint256 tokenId) external {
        // Mint some reward tokens to the position owner
        address owner = stakedNFTs[tokenId];
        if (owner != address(0)) {
            // Mint 1 ABX as mock reward
            MockABX(abxToken).mint(msg.sender, 1 ether);
        }
    }

    function getReward(address account) external {
        // Mint some reward tokens to the account
        MockABX(abxToken).mint(account, 1 ether);
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

contract MockVotingEscrow {
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public balances;
    mapping(uint256 => uint256) public lockEnd;
    
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256) {
        uint256 tokenId = nextTokenId++;
        ownerOf[tokenId] = msg.sender;
        balances[tokenId] = _value;
        lockEnd[tokenId] = block.timestamp + _lockDuration;
        return tokenId;
    }
    
    function increaseAmount(uint256 _tokenId, uint256 _value) external {
        require(ownerOf[_tokenId] == msg.sender, "Not owner");
        balances[_tokenId] += _value;
    }
    
    function balanceOfNFT(uint256 _tokenId) external view returns (uint256) {
        return balances[_tokenId];
    }
    
    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return ownerOf[_tokenId] == _spender;
    }
    
    function approve(address /*_approved*/, uint256 /*_tokenId*/) external {
        // Mock: do nothing
    }
}

contract MockVoter {
    event Voted(
        address indexed voter,
        address indexed pool,
        uint256 indexed tokenId,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    
    mapping(address => address) public gauges;
    mapping(address => bool) public isAlive;
    uint256 public totalWeight;
    
    function vote(uint256 _tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external {
        require(_poolVote.length == _weights.length, "Length mismatch");
        
        for (uint256 i = 0; i < _poolVote.length; i++) {
            totalWeight += _weights[i];
            emit Voted(msg.sender, _poolVote[i], _tokenId, _weights[i], totalWeight, block.timestamp);
        }
    }
    
    function reset(uint256 /*_tokenId*/) external {
        // Mock: do nothing
    }
}
