You are an expert in building modern crypto/web3 web applications using Foundry, the Abstract Layer 2 blockchain, Abstract Global Wallet, Next.js, shadcn/ui, and Tailwind CSS.

<general_rules>
General rules that you should abide by:
  - Use pnpm for all commands
  - Use the latest version of all technologies mentioned in the <tech_stack> section.

  <types>
      - Always reuse existing types where available. Before creating any new type:
      - Search for existing types that match your needs.
      - Only create a new tye if no suitable type exists
      - Never duplicate or recreate types that already exists.
  </types>

  <duplicate_code>
    1. You should NEVER write duplicate code. Try to maintain DRY (Don't Repeat Yourself) principles.
    2. Actively REMOVE duplicate code when it's identified even when the user is pushing you to build. Prioritize removing duplicate code above all else.
  </duplicate_code>

  <avoid_doing>
    - Do not use the "any" type or "unknown" type.
    - Do not apply any placeholders or temporary solutions to the code. You are building a production ready application.
    - Do not install any new dependencies without asking.
    - Do not create unnecessary new readme files
  </avoid_doing>

</general_rules>

<tech_stack>
    This project uses the following technologies:

    <frontend>
      - pnpm (package manager)
      - Next.js (React framework)
      - shadcn/ui (UI component library)
      - Tailwind CSS (styling)
      - TypeScript
      - Vercel (deployment)
      - Abstract Global Wallet (https://docs.abs.xyz/) - wallet built for Abstract L2
      - build.abs.xyz - shadcn/ui components for Abstract Global Wallet integration
      - Subgraphs (via "The Graph" or "The Graph Protocol") to query Aborean data:
        * Pool metrics: TVL, APR, swap fees, volume, liquidity depth
        * Pool positions: LP token balances, staked positions, earned rewards
        * Real-time data for reallocation decisions without direct blockchain queries

      <agw_batch_calls>
        Abstract Global Wallet supports batch transactions (EIP-5792) via sendCalls:
        - Documentation: https://docs.abs.xyz/abstract-global-wallet/agw-client/actions/sendCalls
        - Usage: useSendCalls() hook from wagmi
        - Benefits: Submit multiple transactions in a single call (e.g., approve + deposit)
        - Frontend can batch: ETH wrap + WETH approval + vault deposit
        - atomicRequired: true = all calls revert if any fails (safer for users)
        - Supports paymaster for gasless transactions (optional)

        Example frontend deposit flow with batch calls:
        1. Wrap ETH → WETH
        2. Approve vault to spend WETH
        3. Call vault.deposit(wethAmount, receiver)
        All in a single transaction bundle.
      </agw_batch_calls>
    </frontend>

    <smart_contracts>
      - Foundry (smart contract development framework)
      - foundry-zksync fork (https://github.com/matter-labs/foundry-zksync) - required for Abstract L2
      - Solidity ^0.8.24 (smart contract language)
      - Abstract L2 (ZKsync-based Layer 2)
      - Compilation: forge build --zksync (uses zksolc compiler)
      - Testing: forge test --zksync
      - Deployment:
        * Testnet RPC: https://api.testnet.abs.xyz (chain ID 11124)
        * Mainnet RPC: https://api.mainnet.abs.xyz (chain ID 2741)
      - Verification: Abscan (Etherscan-compatible explorer)
      - Note: Compiled contracts output to zkout/ directory (not out/)

      <foundry_config>
        Required foundry.toml configuration:
        ```toml
        [profile.default]
        src = 'src'
        libs = ['lib']
        fallback_oz = true

        [profile.default.zksync]
        enable_eravm_extensions = true # Required for system contract calls

        [etherscan]
        abstractTestnet = { chain = "11124", url = "https://api-sepolia.abscan.org/api", key = "TACK2D1RGYX9U7MC31SZWWQ7FCWRYQ96AD"}
        abstractMainnet = { chain = "2741", url = "", key = ""}
        ```
      </foundry_config>

      <testing_considerations>
        - Cheatcodes can only be used at the root level of test contracts (not inside contracts being tested)
        - ZKsync VM cheatcodes available: zkVm, zkVmSkip, zkRegisterContract, zkUsePaymaster, zkUseFactoryDep
        - Fork testing: forge test --zksync --fork-url https://api.testnet.abs.xyz
        - Local node: anvil-zksync (runs on http://localhost:8011)
      </testing_considerations>
    </smart_contracts>
</tech_stack>

<keep_in_mind>
    - The user is already running the "pnpm run dev" command that starts the development server. You should not start it again.
    - The local dev server is running on http://localhost:3000.
</keep_in_mind>

<project_structure>

</project_structure>

<aborean_protocol>
  <overview>
    Aborean is a DeFi protocol on the Abstract L2 chain that optimizes capital efficiency through:
    - Liquidity provisioning with vote-escrowed governance (veABX)
    - ABX token emissions to incentivize liquidity providers
    - veABX voting system that directs emissions to specific pools
    - Dynamic swap fees (0.04% - 1% depending on pool type)
    - Multiple pool types: Stable, Volatile, and Concentrated Liquidity pools
    - Architecture inspired by Solidly and Aerodrome Finance
    - Source code: https://github.com/Aborean-Finance/aborean-contracts
  </overview>

  <deployed_contracts>
    <abstract_mainnet>
      <core_protocol>
        - Abx (ERC-20): 0x4C68E4102c0F120cce9F08625bd12079806b7C4D
        - VotingEscrow (veABX ERC-721): 0x27B04370D8087e714a9f557c1EFF7901cea6bB63
        - Router: 0xE8142D2f82036B6FC1e79E4aE85cF53FBFfDC998
        - PoolFactory: 0xF6cDfFf7Ad51caaD860e7A35d6D4075d74039a6B
        - Voter: 0xC0F53703e9f4b79fA2FB09a2aeBA487FA97729c9
        - Minter: 0x58564Fcfc5a0C57887eFC0beDeC3EB5Ec37f1626
        - GaugeFactory: 0x29BfEd845b1C10e427766b21d4533800B6f4e111
        - RewardsDistributor: 0x36cbf77D8F8355D7A077d670C29E290E41367072
        - FactoryRegistry: 0x5927E0C4b307Af16260327DE3276CE17d8A4aB49
        - Forwarder: 0x3f91b806F1968Fca85C08A7eE9A7262D7207A9c1
        - ManagedRewardsFactory: 0x889d93f9c3586ec7CD287eE4e7C96E544985Ee95
        - VotingRewardsFactory: 0xCEf48ee1b2F7c0833D6F097c69D1ed4159b60958
        - VeArtProxy: 0x53AF068205CB466d7Ce6e55fD1E64eB9eBcB7ce0
        - AirdropDistributor: 0xd29d05bFfb2F0AfBB76ed217d726Ff5922253086
      </core_protocol>

      <concentrated_liquidity_slipstream>
        - WETH/PENGU CL Pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
        - Slipstream Position NFT Manager: 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F
        - WETH/PENGU CL Gauge: 0x125c13e12bD40BC7EB4F129d3f8443091D443B7E (NFT staking gauge)
      </concentrated_liquidity_slipstream>

      <token_addresses>
        - WETH: 0x3439153eb7af838ad19d56e1571fbd09333c2809
        - PENGU: 0x9ebe3a824ca958e4b3da772d2065518f009cba62
      </token_addresses>
    </abstract_mainnet>
  </deployed_contracts>

  <contract_architecture>
    <amm_contracts>
      - Pool.sol: AMM implementation supporting multiple pool types
        * Basic Volatile: Constant-product (x*y=k) for uncorrelated assets
        * Concentrated Liquidity: Tick-based liquidity (Uniswap V3-style) for higher capital efficiency
      - Router.sol: Multi-pool swaps, deposit/withdrawal (Uniswap V2 Router-style)
      - PoolFees.sol: Trading fee storage (separate from reserves)
      - ProtocolLibrary.sol: Router helpers for price-impact calculations
      - FactoryRegistry.sol: Registry for approved pool/gauge/bribe/reward factories
    </amm_contracts>

    <tokenomics_contracts>
      - Abx.sol: Protocol ERC-20 token
      - VotingEscrow.sol: ERC-721 veNFT (vote-escrow lock with merge/split capability)
      - Minter.sol: Emission distributor to Voter + rebases to RewardsDistributor
      - RewardsDistributor.sol: Handles rebase distribution for veNFT lockers
      - VeArtProxy.sol: veNFT art proxy (upgradeable)
      - AirdropDistributor.sol: Distributes permanently locked veNFTs
    </tokenomics_contracts>

    <protocol_mechanics>
      - Voter.sol: Handles epoch votes, gauge/reward creation, emission distribution
      - Gauge.sol: Receives votes, distributes proportional emissions to LP stakers
        * Deposits: LP tokens from pools
        * Rewards: Protocol token emissions
        * Fee mechanism: Claims on pool fees relinquished to gauge

      <rewards_system>
        - Reward.sol: Base reward contract for staker distributions
        - VotingReward.sol: Epoch-based rewards for pool/gauge voters
        - FeesVotingReward.sol: LP fee distribution (from gauge via PoolFees)
        - BribeVotingReward.sol: External incentives for voters (deposited weekly)
        - ManagedReward.sol: Staking for managed veNFTs (delegated voting)
        - LockedManagedReward.sol: Locked rewards (ABX emissions/rebases compounded)
        - FreeManagedReward.sol: Unlocked rewards for managed NFT depositors
      </rewards_system>
    </protocol_mechanics>

    <governance_contracts>
      - ProtocolGovernor.sol: OpenZeppelin Governor for protocol-wide access control
        * Whitelist tokens for trading
        * Update minting emissions
        * Create managed veNFTs
      - EpochGovernor.sol: Epoch-based governance for emission adjustments
    </governance_contracts>
  </contract_architecture>

  <key_mechanics>
    <tokens>
      - ABX: ERC-20 utility token for liquidity incentives
      - veABX: ERC-721 NFT governance token (vote-escrowed ABX)
      - Locking ABX for up to 4 years grants veABX voting power (linear: 100 ABX locked 4 years = 100 veABX, 1 year = 25 veABX)
    </tokens>
    <emissions>
      - Phase 1 (Weeks 1-14): 10M ABX/week, growing 3% weekly to ~14.76M peak
      - Phase 2 (Week 15+): 1% weekly decay until reaching 8.97M ABX
      - Phase 3 (Tail): Perpetual 0.67% annual emissions (adjustable 0.01%-1%)
      - 5% of emissions allocated to team
      - veABX holders vote to direct emissions to specific liquidity pools
    </emissions>
    <pool_types>
      - Stable Pools: For correlated assets (stablecoins), minimal slippage using formula: a³b + b³a ≥ z
      - Volatile Pools: For uncorrelated assets (ETH, ABX, etc.)
      - Concentrated Liquidity (CL): Tick-based liquidity with different spacing:
        * CL1 (0.01% tick): Highly correlated (wstETH/WETH)
        * CL50 (0.5% tick): Stable pairs (USDC pools)
        * CL200 (2% tick): Volatile pairs (ETH, ABX)
        * CL2000 (20% tick): New/developing tokens
    </pool_types>
    <rewards_flow>
      1. LPs deposit tokens into pools and stake LP tokens
      2. veABX holders vote on which pools receive emissions
      3. Pools earn ABX emissions based on veABX votes
      4. LPs earn: ABX emissions + trading fees from their pool
      5. veABX voters earn: bribes (incentives from protocols) + share of trading fees
      6. Rewards claimable at epoch transitions (Thursdays 00:00 UTC)
    </rewards_flow>
  </key_mechanics>
</aborean_protocol>

<vault_project>
  <concept>
    Building an ERC-4626 compliant vault that automatically compounds yield from the WETH/PENGU pool on Aborean.
  </concept>

  <design_decisions>
    <deposit_tokens>
      - Vault accepts ETH only (ERC-4626 asset)
      - Wraps to WETH internally for LP operations
      - Unwraps to ETH on withdrawal
      - Frontend can optionally accept PENGU/USDC and convert to WETH before depositing
    </deposit_tokens>

    <deposit_behavior>
      - User deposits ETH → Vault wraps to WETH
      - Vault swaps 50% WETH → PENGU
      - Adds liquidity to WETH/PENGU pool
      - Stakes LP tokens in gauge
      - Capital starts earning immediately
      - Slippage tolerance: 0.5% max on all swaps (protects vault from excessive slippage losses)
    </deposit_behavior>

    <withdrawal_behavior>
      - Calculate required amount of LP to be withdrawn
      - Unstakes required amount of LP tokens
      - Withdraw liquidity (receives WETH + PENGU)
      - Swaps PENGU → WETH
      - Unwraps WETH → ETH
      - Returns ETH to user
      - Slippage tolerance: 0.5% max on swaps
    </withdrawal_behavior>

    <fee_structure>
      - No management fees
      - No performance fees
      - No deposit/withdrawal fees
      - Vault is free to use (only pay gas + slippage on swaps)
    </fee_structure>

    <minimum_deposit>
      - Minimum deposit: 0.01 ETH (~$40 at $4000/ETH)
      - Protects against inflation attack (prevents first depositor from manipulating share price)
      - Reasonable amount that doesn't exclude small depositors
      - Applied to ALL deposits (not just first)
    </minimum_deposit>

    <admin_controls>
      - Admin: Single EOA (externally owned account)
      - Admin can:
        * Pause/unpause deposits and withdrawals (emergency only)
        * Execute harvesting (claim ABX rewards + trading fees)
        * Execute compounding (reinvest fees back into LP)
        * Execute veABX voting (vote for WETH/PENGU pool emissions)
        * Rebalance concentrated liquidity range (if price moves out of range)
      - Admin CANNOT:
        * Withdraw user funds
        * Change fee structure
        * Upgrade contract logic (non-upgradeable)
      - Future: Transition to multisig or DAO governance
    </admin_controls>

    <automation>
      - Backend cronjob runs hourly to trigger admin functions

      <harvest_function>
        Admin-callable harvest() function:
        1. Call gauge.claimRewards() to claim ABX emissions
        2. Call gauge.claim() to claim trading fees (WETH + PENGU)
        3. Store claimed tokens in vault for next compound cycle

        Note: Can claim without unstaking NFT position
      </harvest_function>

      <compound_function>
        Admin-callable compound() function:
        1. Take harvested WETH + PENGU fees
        2. Swap to achieve 50/50 ratio (using Router)
        3. Withdraw NFT from gauge temporarily (auto-claims any pending rewards)
        4. Increase liquidity on existing NFT position (Position Manager)
        5. Re-stake NFT in gauge
        6. totalAssets() increases, existing vault shares appreciate

        Gas optimization: Only compound when fees > threshold
      </compound_function>

      <lock_abx_function>
        Contract: VotingEscrow at 0x27B04370D8087e714a9f557c1EFF7901cea6bB63
        Transaction example: 0xc3e159755cafd490777701ebb129f4990e5a251ea38caf6dbdca8631a8f716b7

        Admin-callable lockABX() function implementation:
        1. Harvest ABX from gauge (via harvest())
        2. Approve VotingEscrow to spend ABX
           - ABX.approve(0x27B04370D8087e714a9f557c1EFF7901cea6bB63, amount)
        3. Call VotingEscrow to create veABX NFT (exact function name TBD)
           - Likely: createLock(uint256 value, uint256 lockDuration) or similar
           - Parameters from example:
             * value: 100000000000000000 wei (0.1 ABX)
             * locktime: 1886371200 (Unix timestamp - lock end date)
             * depositType: 1 (enum value, likely CREATE_LOCK_TYPE)
        4. Events emitted:
           - Transfer(from=user, to=VotingEscrow, value=0.1 ABX) [ABX token]
           - Transfer(from=0x0, to=user, tokenId=8214) [veNFT minted]
           - Deposit(provider, tokenId=8214, depositType=1, value=100000000000000000, locktime=1886371200, ts=1760933707)
           - Supply(prevSupply, supply) [total veABX supply updated]
        5. Vault receives veABX NFT tokenId

        Lock duration calculation:
        - locktime: 1886371200 (Unix timestamp)
        - ts (current time): 1760933707
        - Lock duration: 1886371200 - 1760933707 = 125437493 seconds (~3.98 years, close to 4 year max)
        - For 4 year max lock: locktime = block.timestamp + (4 * 365 * 24 * 60 * 60)

        TODO:
        - Verify exact function signature (likely createLock or create_lock)
        - Check if increaseAmount() exists to add ABX to existing veNFT
        - If increaseAmount() exists, use it instead of creating multiple NFTs
        - Otherwise, create new NFTs and use merge() function to consolidate
      </lock_abx_function>

      <vote_function>
        Contract: Voter at 0xC0F53703e9f4b79fA2FB09a2aeBA487FA97729c9
        Transaction example: (voting for pool 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC)

        Admin-callable vote() function implementation:
        1. Vault holds veABX NFT (e.g., tokenId 8214 from lockABX())
        2. Call Voter contract to vote (exact function name TBD)
           - Likely: vote(uint256 tokenId, address[] pools, uint256[] weights)
           - Or: vote(uint256 tokenId, address pool, uint256 weight)
           - Parameters from example:
             * tokenId: 8039 (veABX NFT owned by voter)
             * pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC (WETH/PENGU CL Pool!)
             * weight: 2989518502560113438 (voting power allocated to pool)

        3. Events emitted:
           - Deposit events on gauge contracts (multiple):
             * Deposit(user=Voter, pid=8039, amount=2989518502560113438)
             * From gauges: 0xdf8f48d5e62a555869329e1494dfa47cd4d687f8, 0xf3870e7db88146ee1eeee24696fa53bda8d28b2c
           - Voted(voter, pool, tokenId, weight, totalWeight, timestamp)
             * voter: 0x06639F064b82595F3BE7621F607F8e8726852fCf
             * pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC (WETH/PENGU CL!)
             * tokenId: 8039
             * weight: 2989518502560113438 (voting power)
             * totalWeight: 37117409018778313142814592 (total protocol votes)
             * timestamp: 1760667926

        4. Voting mechanics:
           - Each veABX NFT has voting power based on locked ABX amount and lock duration
           - Can vote for multiple pools by passing arrays of pools + weights
           - Weight is distributed proportionally to pools
           - For vault: Allocate 100% weight to WETH/PENGU CL pool (0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC)
           - Votes can be updated each epoch (Thursdays 00:00 UTC)
           - Pool receives proportional share of emissions based on votes

        CRITICAL: The pool address in Voted event (0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC) is the WETH/PENGU CL Pool!
        This confirms we vote for the pool contract address, not the gauge address.

        TODO:
        - Verify exact function signature (likely vote(uint256, address[], uint256[]))
        - Check if can vote for single pool or must use arrays
        - Understand weight calculation (likely = veABX balance of tokenId)
      </vote_function>

      <rebalance_function>
        Admin-callable rebalanceRange() function:
        1. Check if current price is outside tick range (using Pyth oracle)
        2. If out of range: withdraw NFT from gauge
        3. Decrease liquidity to 0 (withdraw all WETH + PENGU)
        4. Calculate new tickLower/tickUpper centered on current price (±20%)
        5. Increase liquidity with new tick range
        6. Re-stake NFT in gauge

        Gas optimization: Only rebalance when out of range
      </rebalance_function>
    </automation>
    <rewards_handling>
      - Vault earns ABX emissions by staking LP tokens in Aborean WETH/PENGU gauge (~272% APR)
      - 100% ABX Lock Strategy:
        * 100% of ABX → Lock as veABX (4 year max lock)
        * Users earn trading fees only (no ABX distribution)
        * Zero ABX sell pressure (maximum bullish for ABX)

      - veABX NFT Management:
        * veABX is an ERC-721 NFT (each lock = 1 NFT)
        * Strategy: Create single veABX NFT on first harvest
        * Future harvests: Extend existing NFT lock (if possible) OR create new NFTs and merge
        * INVESTIGATION NEEDED: Check if VotingEscrow supports adding ABX to existing NFT
        * Fallback: Use VotingEscrow's merge() function to consolidate multiple NFTs periodically

      - veABX Usage:
        * Vote for WETH/PENGU Concentrated pool to increase its emissions
        * Earn fees and bribes from voting (via FeesVotingReward + BribeVotingReward)
        * Flywheel: More votes → More emissions → Higher pool APR → More volume → Higher fee APR

      - What Users Actually Earn:
        * Trading fees from WETH/PENGU swaps (part of ~272% total APR)
        * Fee APR grows over time as vault's votes attract more volume
        * Auto-compounded (fees reinvested into LP)
        * Convenience (no manual claiming, voting, or managing)

      - Benefits:
        * Zero ABX sell pressure (100% locked, ultra-bullish for ABX)
        * Vault becomes governance whale in Aborean ecosystem
        * Pool becomes more attractive over time (more emissions = more LPs = more volume = more fees)
        * Passive yield for PENGU/WETH holders who want "set and forget"

      - Trade-offs:
        * Users give up ABX emissions (vault locks them)
        * Lower APR than LP'ing directly (fee-only APR vs ~272% with ABX emissions)
        * Value prop is convenience + growing APR + supporting ABX ecosystem + zero sell pressure

      - totalAssets() calculation:
        * CRITICAL: Must use Pyth oracles to prevent flash loan manipulation
        * Calculate LP position value using Pyth prices (WETH/USD + PENGU/USD)
        * Include accrued trading fees (part of LP position value)
        * Do NOT include veABX (locked governance, not withdrawable)
        * Do NOT include unharvested ABX (will be locked, not distributed)
        * Return total value denominated in WETH (the vault's asset)

        ```solidity
        function totalAssets() public view returns (uint256) {
            // Get LP balance staked in gauge
            uint256 lpBalance = gauge.balanceOf(address(this));
            if (lpBalance == 0) return 0;

            // Calculate underlying WETH + PENGU amounts from LP position
            (uint256 wethAmount, uint256 penguAmount) = _calculateLPValue(lpBalance);

            // Get oracle prices (flash loan resistant)
            uint256 wethPriceUSD = _getPythPrice(WETH_PRICE_ID);
            uint256 penguPriceUSD = _getPythPrice(PENGU_PRICE_ID);

            // Calculate total value in USD
            uint256 totalValueUSD = (wethAmount * wethPriceUSD) + (penguAmount * penguPriceUSD);

            // Convert back to WETH terms (ERC-4626 asset)
            return totalValueUSD / wethPriceUSD;
        }
        ```
    </rewards_handling>
    <price_oracles>
      - Use Pyth Network oracles (available on Abstract)
      - Pyth provides manipulation-resistant prices from real exchanges
      - Available price feeds on Abstract:
        * WETH/USD (0x9d4294bbcd1174d6f2003ec365831e64cc31d9f6f15a2b85399db8d5000960f6)
        * USDT/USD (0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b)
        * PENGU/USD (0xbed3097008b9b5e3c93bec20be79cb43986b85a996475589351a21e67bae9b61)
      - ABX/USD feed NOT available - must use alternative pricing
    </price_oracles>
    <single_pool_strategy>
      <pool_selection>
        WETH/PENGU has two pool options on Aborean:

        1. **Concentrated Liquidity (0.30% fee)** - CHOSEN FOR VAULT
           - TVL: $11.8M
           - Liquidity: 2939.19 WETH + 496,175,668.68 PENGU
           - Volume (24h): $981.9K
           - APR: ~272.48%
           - Benefits: Higher capital efficiency, better APR, deeper liquidity
           - Pool Address: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
           - Position Manager (NFT): 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F (Slipstream Position NFT v1)

        2. Basic Volatile (0.30% fee) - NOT USED
           - TVL: $1.4M
           - Liquidity: 353.44 WETH + 59,833,373.14 PENGU
           - Volume (24h): $1.2M
           - APR: ~75.66%
           - Lower liquidity and APR vs concentrated pool

        **Decision**: Use Concentrated Liquidity pool for maximum APR and capital efficiency
      </pool_selection>

      <concentrated_liquidity_implementation>
        - Pool type: Concentrated Liquidity (Slipstream - Uniswap V3-style)
        - Pool contract: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
        - Position Manager: 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F (ERC-721 NFT)
        - Fee tier: 0.30%
        - Positions are ERC-721 NFTs (like Uniswap V3)
        - Both tokens have Pyth oracle feeds (WETH/USD + PENGU/USD) for secure pricing

        <deposit_flow>
          1. User deposits ETH → Vault wraps to WETH
          2. Swap 50% WETH → PENGU via Router (slippage: 0.5% max)
          3. Approve Position Manager to spend WETH + PENGU
          4. Call Position Manager to mint new NFT position or increase liquidity on existing NFT
             - tickLower/tickUpper: Calculated from current price ±20%
             - Mint/IncreaseLiquidity event emitted with tokenId
          5. Approve Gauge to transfer NFT
          6. Transfer NFT to Gauge (gauge.deposit event emitted)
             - Gauge receives NFT ownership
             - User credited with staking position
          7. Mint vault shares to user
        </deposit_flow>

        <withdrawal_flow>
          1. Burn user's vault shares
          2. Withdraw NFT from Gauge (gauge.withdraw)
             - NFT transferred back to vault
          3. Collect any accrued fees from position (Position Manager)
          4. Decrease liquidity from NFT (Position Manager)
             - Collect WETH + PENGU from position
          5. Swap PENGU → WETH via Router (slippage: 0.5% max)
          6. Unwrap WETH → ETH
          7. Return ETH to user
        </withdrawal_flow>

        <gauge_staking_mechanism>
          Based on transaction logs, the CL Gauge (0x125c13e12bD40BC7EB4F129d3f8443091D443B7E) works as follows:

          <staking_process_exact>
            Contracts involved:
            - Position Manager (NFT): 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F
            - Gauge: 0x125c13e12bD40BC7EB4F129d3f8443091D443B7E

            Steps:
            1. User calls approve() on Position Manager NFT contract
               - approve(address operator=0x125c13e12bD40BC7EB4F129d3f8443091D443B7E, uint256 tokenId=7235)
               - Event: Approval(owner, approved=Gauge, tokenId)

            2. User calls deposit/stake function on Gauge (exact function name TBD)
               - Likely: deposit(uint256 tokenId) or stake(uint256 tokenId)
               - NFT transferred from user to Gauge
               - Event: Transfer(from=user, to=Gauge, tokenId=7235)
               - Event: Deposit(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake)
               - Example: Deposit(0x06639F064b82595F3BE7621F607F8e8726852fCf, 7235, 306901971618912264)

            TODO: Inspect Gauge ABI for exact staking function signature
          </staking_process_exact>

          <unstaking_process_exact>
            Contract: Gauge at 0x125c13e12bD40BC7EB4F129d3f8443091D443B7E
            Transaction example: 0xfb9da87ff4a9d008a1b3790d9e0a42b4b1fcd151751045192997c4e782e88c7d

            User calls withdraw/unstake function (exact name TBD - likely withdraw(uint256 tokenId))

            Events emitted in order:
            1. Burn(owner=Gauge, tickLower=119400, tickUpper=122400, amount=0, amount0=0, amount1=0)
               - From Pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
            2. Collect(owner=Gauge, recipient=user, tickLower=119400, tickUpper=122400, amount0=0, amount1=0)
               - From Pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
            3. Collect(tokenId=7235, recipient=user, amount0=0, amount1=0)
               - From Position Manager: 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F
            4. Transfer(from=Gauge, to=user, value=235415327933444) [ABX token]
               - From ABX: 0x4C68E4102c0F120cce9F08625bd12079806b7C4D
            5. ClaimRewards(from=user, amount=235415327933444)
               - From Gauge
            6. Transfer(from=Gauge, to=user, tokenId=7235) [NFT]
               - From Position Manager: 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F
            7. Withdraw(user, tokenId=7235, liquidityToStake=306901971618912264)
               - From Gauge

            CRITICAL: Single withdraw() call handles everything automatically!

            TODO: Inspect Gauge ABI for exact withdrawal function signature
          </unstaking_process_exact>

          <claiming_rewards_exact_calls>
            Contract: WETH/PENGU CL Gauge at 0x125c13e12bD40BC7EB4F129d3f8443091D443B7E

            Claim ABX emissions:
            - User calls function on Gauge (exact function name TBD - need to inspect ABI)
            - Event emitted: ClaimRewards(address indexed from, uint256 amount)
            - Transfer event: ABX token (0x4C68E4102c0F120cce9F08625bd12079806b7C4D) from Gauge to user
            - Example transaction: 0xa1af9c5c9e37d387f9db10b020e1715f2c7a3af1ea1fe3e64d1000ec9e508a96
            - Claimed: 277014823632526 wei ABX
            - Does NOT unstake NFT

            Claim trading fees:
            - User calls function on Gauge (exact function name TBD)
            - Event emitted: Claim(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1)
            - Transfers both pool tokens (WETH + PENGU) to recipient
            - Example from WETH/BIG gauge (0x5b4789AfEC36e61a74C15f898a3E45316B104cd7):
              * Transaction: 0x8477a6e87763d66d94565c7caab1328ca9ebc8056d687fde88ca9e0b45a6db72
              * amount0: 30039920080796 wei WETH
              * amount1: 270466498298001824 wei BIG
            - Does NOT unstake NFT

            TODO: Need to inspect Gauge ABI to get exact function names:
            - Likely: getReward() or claimRewards() for ABX
            - Likely: claimFees() or claim() for trading fees
          </claiming_rewards_exact_calls>
        </gauge_staking_mechanism>

        <range_management>
          - Initial range: Set to ±20% from current price (covers normal volatility)
          - Rebalancing trigger: Position goes out of range (price < tickLower OR price > tickUpper)
          - Rebalancing function: Admin-callable `rebalanceRange()`
          - Rebalancing process:
            1. Unstake NFT from gauge
            2. Decrease liquidity to 0 on NFT (withdraw all WETH + PENGU)
            3. Calculate new tickLower/tickUpper centered on current price (using Pyth oracle)
            4. Add liquidity back to NFT with new tick range (or mint new NFT)
            5. Re-stake NFT in gauge
          - Slippage protection: 0.5% max on any required swaps
          - Automation: Hourly cronjob checks if rebalancing needed, calls function if so
          - Gas optimization: Only rebalance when out of range (not preemptively)
        </range_management>

        <position_nft_exact_operations>
          Contract: Slipstream Position NFT Manager at 0xa4890B89dC628baE614780079ACc951Fb0ECdC5F
          Pool: WETH/PENGU CL at 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC

          Minting a new position (exact function TBD - likely mint()):
          - Events emitted:
            1. Transfer(from=Pool, to=user, wad) [WETH token approval/transfer]
            2. Transfer(from=Pool, to=user, value) [PENGU token approval/transfer]
            3. Mint(sender, owner, int24 tickLower, int24 tickUpper, uint128 amount, uint256 amount0, uint256 amount1)
               - From Pool: 0xB3131C7F642be362acbEe0dd0b3e0acc6f05fcDC
               - Example: Mint(sender=NFTManager, owner=NFTManager, tickLower=119400, tickUpper=122400, amount=306901971618912264, amount0=49216873271620, amount1=9953009482752532520)
            4. Transfer(from=0x0, to=user, tokenId=7235) [NFT minted]
            5. IncreaseLiquidity(tokenId=7235, liquidity=306901971618912264, amount0=49216873271620, amount1=9953009482752532520)

          Increasing liquidity on existing position (exact function TBD - likely increaseLiquidity()):
          - Parameters: (uint256 tokenId, uint256 amount0Desired, uint256 amount1Desired, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
          - Events: Same as minting but uses existing tokenId

          Decreasing liquidity (exact function TBD - likely decreaseLiquidity()):
          - Parameters: (uint256 tokenId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline)
          - Withdraws tokens from position without burning NFT

          Collecting fees (exact function TBD - likely collect()):
          - Parameters: (uint256 tokenId, address recipient, uint128 amount0Max, uint128 amount1Max)
          - Events:
            1. Collect(owner=NFTManager, recipient, tickLower, tickUpper, amount0, amount1) [from Pool]
            2. Collect(tokenId, recipient, amount0, amount1) [from NFT Manager]
          - Example: Collected 10205621665 wei WETH + 0 PENGU

          Burning position (exact function TBD - likely burn()):
          - Destroys NFT after removing all liquidity

          TODO: Inspect Position Manager ABI for exact function signatures and parameters
        </position_nft_exact_operations>
      </concentrated_liquidity_implementation>
    </single_pool_strategy>
    <security_measures>
      - Use Pyth oracles for all price data (prevents flash loan manipulation)
      - Only allocate to pools where both tokens have Pyth feeds OR one is a stablecoin
      - Emergency pause mechanism
      - Admin-controlled pool whitelist
    </security_measures>
  </design_decisions>
  <price_feeds>
    - https://docs.pyth.network/price-feeds/core/push-feeds/evm#abstract-mainnet
  </price_feeds>

</vault_project>