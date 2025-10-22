# Aborean Vault Test Suite

Comprehensive testing suite for the Aborean WETH/PENGU auto-compounding vault.

## Test Structure

### 1. **Unit Tests** (`VaultUnit.t.sol`)
Tests individual functions in isolation with mocked dependencies.

**Coverage:**
- Constructor validation
- Oracle price calculations (Pyth integration)
- Tick math and range calculations
- Position amount calculations
- Admin functions (pause/unpause)
- Edge cases (minimum deposits, precision)

**Run:**
```bash
forge test --match-contract VaultUnitTest --zksync -vvv
```

### 2. **Integration Tests** (`VaultIntegration.t.sol`)
Tests complete user workflows and interactions between components.

**Coverage:**
- First depositor flow (create position → stake)
- Multiple sequential depositors
- Pause/unpause workflows
- Price change handling
- Total supply and asset accounting
- Share price evolution
- Event emissions

**Run:**
```bash
forge test --match-contract VaultIntegrationTest --zksync -vvv
```

### 3. **Security Tests** (`VaultSecurity.t.sol`)
Tests common exploits and attack vectors.

**Coverage:**
- **Inflation Attacks:** First depositor manipulation, donation attacks
- **Reentrancy:** Deposit/withdraw reentrancy protection
- **Oracle Manipulation:** Flash loan attacks, stale prices, low confidence
- **Slippage Exploitation:** Swap manipulation attempts
- **Admin Privileges:** Verify admin cannot steal funds
- **Precision Attacks:** Rounding errors, dust deposits
- **Share Manipulation:** First depositor advantage, share price manipulation

**Run:**
```bash
forge test --match-contract VaultSecurityTest --zksync -vvv
```

### 4. **Fuzz Tests** (`VaultFuzz.t.sol`)
Property-based testing with random inputs.

**Coverage:**
- Deposit amount fuzzing (valid/invalid ranges)
- Multiple deposits with random amounts
- Tick calculations with random prices
- Oracle prices with random values
- Invariant: totalSupply equals sum of balances
- Invariant: totalAssets never decreases on deposit
- Invariant: Share price remains stable or increases
- Boundary testing (minimum deposits, large deposits)

**Run:**
```bash
forge test --match-contract VaultFuzzTest --zksync -vvv
```

### 5. **Fork Tests** (`VaultFork.t.sol`)
Tests against live Abstract mainnet contracts.

**Coverage:**
- Real WETH/PENGU pool interactions
- Real Pyth oracle price feeds
- Real CL position creation and staking
- Real swap routing through Aborean Router
- Gas benchmarks (first deposit, subsequent deposits)
- Real market price handling
- Slippage protection on real swaps
- Large deposits on real pool (stress test)

**Run:**
```bash
forge test --match-contract VaultForkTest --fork-url https://api.mainnet.abs.xyz --zksync -vvv
```

**Note:** Fork tests require RPC access to Abstract mainnet and may incur rate limits.

## Test Helpers

### `Helpers.sol`
Shared utilities for all tests:
- **TestHelpers:** Share calculations, price impact, formatting
- **BaseVaultTest:** Common setup, user funding, logging
- **FuzzHelpers:** Input bounding for fuzz tests
- **MockDataHelpers:** Realistic mock data generation

### `mocks/Mocks.sol`
Mock contracts for unit/integration tests:
- **MockWETH:** WETH with deposit/withdraw
- **MockPENGU:** ERC20 token with mint
- **MockPyth:** Pyth oracle with configurable prices
- **MockRouter:** Aborean router with fixed exchange rate
- **MockPositionManager:** CL position NFT manager
- **MockCLGauge:** Gauge for staking CL positions
- **MockUniswapV3Pool:** Pool for slot0() price queries

## Running All Tests

### Run all tests (except fork tests):
```bash
forge test --zksync -vvv
```

### Run all tests including fork tests:
```bash
forge test --fork-url https://api.mainnet.abs.xyz --zksync -vvv
```

### Run specific test file:
```bash
forge test --match-contract VaultSecurityTest --zksync -vvv
```

### Run specific test function:
```bash
forge test --match-test test_InflationAttack_PreventedByMinDeposit --zksync -vvv
```

### Run with gas reporting:
```bash
forge test --gas-report --zksync
```

### Run with coverage:
```bash
forge coverage --zksync
```

## Test Categories by Security Focus

### Critical Security Tests
1. **Inflation Attack Prevention** (`VaultSecurity.t.sol::test_InflationAttack_PreventedByMinDeposit`)
   - Verifies minimum deposit prevents first depositor manipulation

2. **Reentrancy Protection** (`VaultSecurity.t.sol::test_ReentrancyAttack_OnDeposit_Prevented`)
   - Verifies ReentrancyGuard works correctly

3. **Oracle Manipulation** (`VaultSecurity.t.sol::test_FlashLoanAttack_PreventedByOracle`)
   - Verifies Pyth oracle prevents flash loan attacks

4. **Stale Price Protection** (`VaultSecurity.t.sol::test_StaleOracle_Reverts`)
   - Verifies vault rejects stale oracle prices

5. **Low Confidence Protection** (`VaultSecurity.t.sol::test_LowConfidenceOracle_Reverts`)
   - Verifies vault rejects low-confidence prices

### Core Functionality Tests
1. **First Deposit Flow** (`VaultIntegration.t.sol::test_Integration_FirstDepositorFlow`)
   - Complete first deposit: approve → deposit → create position → stake

2. **Multiple Depositors** (`VaultIntegration.t.sol::test_Integration_MultipleDepositors`)
   - Sequential deposits with fair share allocation

3. **Share Accounting** (`VaultIntegration.t.sol::test_Integration_TotalSupplyAccounting`)
   - Verifies totalSupply always equals sum of balances

4. **Asset Valuation** (`VaultUnit.t.sol::test_TotalAssets_AfterDeposit`)
   - Verifies oracle-based asset valuation

### Edge Case Tests
1. **Minimum Deposit Boundary** (`VaultFuzz.t.sol::testFuzz_MinimumDeposit_Boundary`)
   - Exactly 0.01 ETH deposit

2. **Large Deposits** (`VaultFuzz.t.sol::testFuzz_LargeDeposit_Accounting`)
   - Up to 10,000 ETH without overflow

3. **Precision Loss** (`VaultSecurity.t.sol::test_RoundingErrors_NoAccumulation`)
   - Multiple small deposits don't create exploitable rounding

## Expected Test Results

All tests should pass with the following assertions:
- ✅ Constructor validates all addresses
- ✅ Minimum deposit (0.01 ETH) is enforced
- ✅ Oracle prices are validated (staleness + confidence)
- ✅ Deposits create/increase CL positions correctly
- ✅ NFT positions are staked in gauge
- ✅ Share accounting is precise
- ✅ totalAssets uses oracle prices (not balances)
- ✅ Admin cannot steal user funds
- ✅ Reentrancy is blocked
- ✅ Pause/unpause works correctly

## Common Issues

### 1. ZKsync Compiler Errors
**Problem:** `forge: not found` or ZKsync compilation fails

**Solution:**
```bash
# Ensure foundry-zksync is installed
foundryup-zksync

# Verify installation
forge --version  # Should show "zksync" in version
```

### 2. Fork Tests Fail
**Problem:** Fork tests timeout or fail to connect

**Solution:**
```bash
# Check RPC endpoint
curl https://api.mainnet.abs.xyz

# Use local fork if rate-limited
anvil-zksync --fork-url https://api.mainnet.abs.xyz
forge test --fork-url http://localhost:8011 --zksync
```

### 3. Gas Estimation Errors
**Problem:** "Intrinsic gas too low" or gas estimation fails

**Solution:**
- Increase gas limit in foundry.toml
- Check that contracts compile with `--zksync` flag
- Verify `enable_eravm_extensions = true` in foundry.toml

### 4. Mock Contract Issues
**Problem:** Mock contracts don't behave as expected

**Solution:**
- Check that mocks implement all required interface functions
- Verify mock state is reset in `setUp()`
- Use `vm.prank()` to call from correct address

## Coverage Goals

Target coverage by contract:
- **Vault.sol:** >95% line coverage
  - All deposit flows covered
  - All oracle calls covered
  - All admin functions covered
  - Edge cases (paused, minimum deposit, etc.)

- **Critical Security:** 100% coverage
  - All attack vectors tested
  - All protection mechanisms verified

## Adding New Tests

### Template for New Test:
```solidity
function test_NewFeature_Description() public {
    // Setup
    uint256 depositAmount = 1 ether;

    // Execute
    vm.startPrank(alice);
    weth.approve(address(vault), depositAmount);
    vault.deposit(depositAmount, alice);
    vm.stopPrank();

    // Assert
    assertGt(vault.balanceOf(alice), 0);
}
```

### Naming Convention:
- `test_Feature_Condition()` - Standard test
- `testFuzz_Feature_Property()` - Fuzz test
- `test_Fork_Feature_RealContract()` - Fork test
- `test_RevertIf_Condition()` - Negative test

## CI/CD Integration

### GitHub Actions (example):
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Foundry
        run: |
          curl -L https://foundry.paradigm.xyz | bash
          foundryup-zksync
      - name: Run tests
        run: forge test --zksync -vvv
```

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Foundry-ZKsync Docs](https://github.com/matter-labs/foundry-zksync)
- [Abstract Docs](https://docs.abs.xyz/)
- [Aborean Protocol](https://github.com/Aborean-Finance/aborean-contracts)
- [ERC-4626 Standard](https://eips.ethereum.org/EIPS/eip-4626)
- [Pyth Network](https://docs.pyth.network/)
