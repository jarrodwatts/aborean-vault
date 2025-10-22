- The first time, if the position has not been created yet, we need to create a new position.
    - Call "mint" on 0xa4890b89dc628bae614780079acc951fb0ecdc5f contract
    - The params used in an example tx are:
        Function: mint((address,address,int24,int24,int24,uint256,uint256,uint256,uint256,address,uint256,uint160))
        Type	Data
        token0	address 0x3439153EB7AF838Ad19d56E1571FBD09333C2809
        token1	address 0x9eBe3A824Ca958e4b3Da772D2065518F009CBa62
        tickSpacing	int24 200
        tickLower	int24 119400
        tickUpper	int24 122400
        amount0Desired	uint256 100000000000000
        amount1Desired	uint256 20092358554762071616
        amount0Min	uint256 99000000000000
        amount1Min	uint256 19891434969214450899
        recipient	address 0x06639F064b82595F3BE7621F607F8e8726852fCf
        deadline	uint256 1761030002
        sqrtPriceX96	uint160 0
    - Note: 0x06639F064b82595F3BE7621F607F8e8726852fCf is my personal AGW, instead, it should be the vault address.
    - 0x3439153EB7AF838Ad19d56E1571FBD09333C2809 is WETH
    - 0x9eBe3A824Ca958e4b3Da772D2065518F009CBa62 is PENGU

- Subsequent calls once the position has been created, we need to increase the liquidity.
    - Call "increaseLiquidity" on 0xa4890b89dc628bae614780079acc951fb0ecdc5f contract
    - The params used in an example tx are:
        Function: increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))
        Type	Data
        tokenId	uint256 7724
        amount0Desired	uint256 100000000000000
        amount1Desired	uint256 20456966144163618491
        amount0Min	uint256 99000000000000
        amount1Min	uint256 20252396482721982306
        deadline	uint256 1761030175

- Immediately stake the position in the gauge

- Our vault will then need to stake the position in the gauge.