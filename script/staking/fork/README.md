# Fork Deployment Setup

This guide explains how to set up Anvil for fork testing and deploy the staking feature upgrades.

## Prerequisites

- Foundry installed
- Access to a Mainnet RPC URL (set as `$MAINNET_RPC`)
- The deployment scripts in this directory

## Step 1: Initial Anvil Setup with State Dump

First, start Anvil with fork configuration and dump the initial state:

```bash
anvil --fork-url $MAINNET_RPC \
        --fork-block-number 22496625 \
        --chain-id 1337 \
        --dump-state script/staking/fork/template.json
```

This creates a template state file that we'll modify and reload.

## Step 2: Governor Address Overrides

With Anvil running, execute these commands in a separate terminal to override the governor addresses with the default Anvil test account (`0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266`):

```bash
# Override governor addresses for all relevant contracts
cast rpc anvil_setStorageAt 0x1cB489ef513E1Cc35C4657c91853A2E6fF1957dE 0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266

cast rpc anvil_setStorageAt 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266

cast rpc anvil_setStorageAt 0xD2b8c78A5Eb18A5F3b0392c5479BB45c77D02ff5 0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266

cast rpc anvil_setStorageAt 0xfDD930c22708c7572278cf74D64f3721Eedc18Ad 0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266
```

**Note:** These commands set the governor storage slot for various contracts to use the first Anvil test account, allowing the deployment script to execute governance functions.

## Step 3: Restart Anvil with Modified State

Stop the current Anvil instance and restart it with the modified state:

```bash
anvil --fork-url $MAINNET_RPC \
        --fork-block-number 22496625 \
        --chain-id 1337 \
        --load-state script/staking/fork/template.json
```

## Step 4: Deploy the Fork Upgrades

Execute the deployment script:

```bash
forge script script/staking/fork/DeployFork.s.sol --rpc-url http://localhost:8545 --broadcast -vvvv
```

This script will:
- Deploy new LRTSquared implementations with token classification support
- Deploy new strategy contracts (SEthFiStrategy, EEigenStrategy)
- Upgrade the proxy to use new implementations
- Configure token types (Native/Staked)
- Set up strategy configurations

## Step 5: Validate Deployment

Verify the deployment was successful using these validation commands:

### Check Proxy Implementations

```bash
# Core Implementation
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url http://127.0.0.1:8545

# Admin Implementation  
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f --rpc-url http://127.0.0.1:8545
```

**Expected Results:**
- Core Implementation: Should return a new contract address (not the original implementation)
- Admin Implementation: Should return a new contract address for the admin logic

### Verify Token Configurations

Check that all tokens are properly registered with correct types:

```bash
# EIGEN (Native)
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 --rpc-url http://127.0.0.1:8545

# ETHFI (Native)
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB --rpc-url http://127.0.0.1:8545

# WETH (Native)
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 --rpc-url http://127.0.0.1:8545

# sETHFI (Staked)
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0x86B5780b606940Eb59A062aA85a07959518c0161 --rpc-url http://127.0.0.1:8545

# eEIGEN (Staked) 
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0xE77076518A813616315EaAba6cA8e595E845EeE9 --rpc-url http://127.0.0.1:8545

# SWELL (Native)
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenInfos(address)" 0x0a6E7Ba5042B38349e437ec6Db6214AEC7B35676 --rpc-url http://127.0.0.1:8545
```

**Expected Results:**
Each token should return a struct with the following format:
```
registered: true (0x0000000000000000000000000000000000000000000000000000000000000001)
whitelisted: true (0x0000000000000000000000000000000000000000000000000000000000000001)
tokenType: 0 for Native tokens (EIGEN, ETHFI, WETH, SWELL), 1 for Staked tokens (sETHFI, eEIGEN)
positionWeightLimit: Non-zero value (e.g., 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000 for 1e18)
depositLimit: Configured limit value
dailyDepositLimit: Configured daily limit
```

### Verify Strategy Configurations

Check that strategies are properly configured:

```bash
# ETHFI Strategy Config
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenStrategyConfig(address)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB --rpc-url http://127.0.0.1:8545

# EIGEN Strategy Config
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenStrategyConfig(address)" 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 --rpc-url http://127.0.0.1:8545
```

**Expected Results:**
Each strategy config should return:
```
strategyAdapter: Address of deployed strategy contract (SEthFiStrategy for ETHFI, EEigenStrategy for EIGEN)
maxSlippageInBps: 0x0000000000000000000000000000000000000000000000000000000000000001 (1 bps)
```

## Running Tests

Once deployed, you can run the fork integration tests:

```bash
# Run all fork tests
forge test --match-path "test/Fork/staking-feature/*.t.sol" --fork-url http://localhost:8545 -vvv

# Run specific test contracts
forge test --match-contract "DeploymentVerification" --fork-url http://localhost:8545 -vvv
forge test --match-contract "StrategyDeposits" --fork-url http://localhost:8545 -vvv
forge test --match-contract "Redemptions" --fork-url http://localhost:8545 -vvv
```

## Manual Strategy Testing

Test strategy functionality manually using cast commands:

### Deposit to Strategy

```bash
# Check ETHFI balance before
cast call 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB "balanceOf(address)" 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 --rpc-url http://127.0.0.1:8545

# Deposit ETHFI to strategy (requires governor)
cast send 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "depositToStrategy(address,uint256)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB 1000000000000000000 --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Check sETHFI balance after
cast call 0x86B5780b606940Eb59A062aA85a07959518c0161 "balanceOf(address)" 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 --rpc-url http://127.0.0.1:8545
```

### Withdraw from Strategy

```bash
# Check current sETHFI balance
cast call 0x86B5780b606940Eb59A062aA85a07959518c0161 "balanceOf(address)" 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 --rpc-url http://127.0.0.1:8545

# Initiate withdrawal from strategy (requires governor)
cast send 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "withdrawFromStrategy(address,uint256)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB 500000000000000000 --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Note: withdrawFromStrategy initiates atomic withdrawal request
# Actual token receipt depends on withdrawal queue processing
```

**Note:** Both `depositToStrategy` and `withdrawFromStrategy` require governor privileges. In the fork environment, the test account `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` has governor access.

## Troubleshooting

- **Governor override not working**: Ensure Anvil is running and the storage slot is correct
- **Deployment fails**: Check that all addresses in DeploymentConstants.sol are correct for the fork block
- **Validation commands return empty**: Verify the proxy address and that deployment completed successfully
- **Tests fail**: Ensure Anvil is still running with the loaded state

## Architecture Notes

This deployment implements:
- **Token Classification System**: Native vs Staked token types for proper redemption handling
- **Two-tier Redemption Logic**: Prioritizes liquid native tokens before staked tokens
- **Strategy Integration**: Automated staking from native to staked tokens via external protocols
- **Withdrawal Queue Support**: Handles locked staked tokens through withdrawal mechanisms
- **Unified Strategy Interface**: All strategy operations (`depositToStrategy`, `withdrawFromStrategy`) go through LRTSquaredAdmin for consistent access control