# Mainnet Deployment Guide - Staking Feature

This guide provides step-by-step instructions for deploying the staking feature to mainnet using Safe multi-sig wallet.

## Overview

The staking feature deployment is split into **4 phases** for maximum safety:

1. **Contract Deployment** - Deploy new implementations and strategies (no risk)
2. **Validation** - Verify all contracts deployed correctly
3. **Transaction Generation** - Create Safe transaction files
4. **Multi-sig Execution** - Execute transactions through Safe

## Prerequisites

### Required Setup
- [ ] Foundry installed and updated
- [ ] Access to mainnet RPC URL (set as `$MAINNET_RPC`)
- [ ] Deployer private key (set as `$PRIVATE_KEY`)
- [ ] Safe multi-sig wallet access
- [ ] Etherscan API key for contract verification (optional)

### Pre-deployment Checklist
- [ ] Confirm mainnet RPC is working: `cast block latest --rpc-url $MAINNET_RPC`
- [ ] Verify deployer has sufficient ETH for gas
- [ ] Confirm Safe multi-sig signers are available
- [ ] Review all contract addresses in `MainnetConstants.sol`
- [ ] Ensure current LRTSquared proxy is functional
- [ ] **CRITICAL**: Complete pre-deployment backup (see section below)
- [ ] Test rollback procedures on fork (see Emergency Rollback section)

## Phase 1: Contract Deployment

Deploy new contract implementations and strategies.

### Commands

```bash
# Deploy all contracts
forge script script/staking/mainnet/01_DeployContracts.s.sol \
    --rpc-url $MAINNET_RPC \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY

# Alternative without verification
forge script script/staking/mainnet/01_DeployContracts.s.sol \
    --rpc-url $MAINNET_RPC \
    --broadcast
```

### Expected Output

```
=== Mainnet Contract Deployment ===
Deployer: 0x...
Chain ID: 1

--- Deploying Implementations ---
LRTSquaredCore deployed: 0x...
LRTSquaredAdmin deployed: 0x...

--- Deploying Strategies ---
SEthFiStrategy deployed: 0x...
EEigenStrategy deployed: 0x...

=== DEPLOYMENT SUMMARY ===
Core Implementation: 0x...
Admin Implementation: 0x...
SEthFi Strategy: 0x...
EEigen Strategy: 0x...
```

### What This Does
- Deploys new `LRTSquaredCore` implementation with staking support
- Deploys new `LRTSquaredAdmin` implementation with strategy management
- Deploys `SEthFiStrategy` for ETHFI → sETHFI staking
- Deploys `EEigenStrategy` for EIGEN → eEIGEN staking
- Saves addresses to `deployments/1/deployments.json`

### Validation Steps
- [ ] All 4 contracts deployed successfully
- [ ] Contract addresses saved to deployment file
- [ ] Contracts verified on Etherscan (if using `--verify`)
- [ ] Gas usage reasonable (should be < 0.1 ETH total)

## Phase 2: Validation

Verify all contracts deployed correctly before proceeding to governance operations.

### Commands

```bash
# Validate deployment
forge script script/staking/mainnet/02_ValidateDeployment.s.sol \
    --rpc-url $MAINNET_RPC
```

### Expected Output

```
=== Mainnet Deployment Validation ===

--- Validating Implementations ---
✅ LRTSquaredCore implementation valid
✅ LRTSquaredAdmin implementation valid

--- Validating Strategies ---
✅ SEthFiStrategy valid
✅ EEigenStrategy valid

--- Validating External Integrations ---
✅ Token contracts valid
✅ Price provider valid
✅ Withdrawal queues valid

--- Validating Current LRTSquared State ---
Current TVL: 123456789000000000000000 wei
✅ Current LRTSquared state valid
✅ Governance configuration ready

=== VALIDATION COMPLETE ===
✅ All contracts deployed correctly
✅ Ready for governance operations
```

### What This Does
- Verifies implementation contracts have correct bytecode
- Tests strategy contract configurations
- Validates external contract integrations
- Checks current LRTSquared proxy state
- Confirms readiness for governance operations

### Validation Steps
- [ ] All validations pass with ✅
- [ ] No error messages or failures
- [ ] Current TVL is reasonable (> 0)
- [ ] Strategy configurations match expected values

## Phase 3: Transaction Generation

Generate Safe Transaction Builder JSON files for multi-sig execution.

### Commands

```bash
# Generate Safe transactions
forge script script/staking/mainnet/03_GenerateUpgradeTxns.s.sol
```

### Expected Output

```
=== Generating Safe Transactions ===

--- Generating Upgrade Transactions ---
✅ Generated upgrade.json

--- Generating Configuration Transactions ---
✅ Generated configure.json

--- Generating Migration Transactions ---
✅ Generated migrate.json

=== TRANSACTION GENERATION COMPLETE ===
Generated files in script/staking/mainnet/transactions/:
- upgrade.json: Proxy upgrades
- configure.json: Strategy configurations  
- migrate.json: Token type migration
```

### Generated Files

**upgrade.json**
- Upgrade LRTSquared proxy to new Core implementation
- Set new Admin implementation

**configure.json**
- Configure ETHFI strategy for staking
- Configure EIGEN strategy for staking

**migrate.json**
- Migrate token types (Native vs Staked classification)

### Validation Steps
- [ ] 3 JSON files generated successfully
- [ ] Files exist in `script/staking/mainnet/transactions/`
- [ ] JSON files are valid format (can open in text editor)

## Phase 4: Multi-sig Execution

Execute transactions through Safe multi-sig wallet.

### 4.1: Import Transactions

1. Open [Safe Transaction Builder](https://app.safe.global/apps/open?safe=eth:0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5&appUrl=https%3A%2F%2Fapps-portal.safe.global%2Ftx-builder)

2. Import each JSON file **in order**:
   - First: `upgrade.json`
   - Second: `configure.json` 
   - Third: `migrate.json`

3. For each file:
   - Click "Upload JSON"
   - Select the file
   - Review all transactions
   - Click "Create Batch"

### 4.2: Execute Upgrade Transactions

**CRITICAL: Execute in order and wait for confirmation between each batch**

#### Batch 1: Proxy Upgrades (upgrade.json)

```
Transaction 1: upgradeToAndCall(newCoreImpl, "")
Transaction 2: setAdminImpl(newAdminImpl)
```

**Before executing:**
- [ ] Verify target contract is LRTSquared proxy: `0x8F08B70456eb22f6109F57b8fafE862ED28E6040`
- [ ] Confirm implementation addresses match deployment output
- [ ] Ensure all signers are available

**After executing:**
- [ ] Both transactions confirmed on chain
- [ ] No reverted transactions
- [ ] Proxy still functional (check TVL)

#### Batch 2: Strategy Configuration (configure.json)

```
Transaction 1: setTokenStrategyConfig(ETHFI, sEthFiStrategy, 1bps)
Transaction 2: setTokenStrategyConfig(EIGEN, eEigenStrategy, 1bps)
```

**Before executing:**
- [ ] Verify strategy addresses match deployment
- [ ] Confirm slippage is 1 basis point (0.01%)

**After executing:**
- [ ] Strategy configurations set successfully
- [ ] Can query `tokenStrategyConfig(ETHFI)` and `tokenStrategyConfig(EIGEN)`

#### Batch 3: Token Type Migration (migrate.json)

```
Transaction 1: migrateTokenTypes([tokens], [types])
```

**Token Classifications:**
- Native: EIGEN, ETHFI, WETH, SWELL
- Staked: sETHFI, eEIGEN

**After executing:**
- [ ] Token types migrated successfully
- [ ] Can query `tokenInfos(token).tokenType` for each token
- [ ] Redemption logic uses new priority system

### 4.3: Post-Deployment Validation

After all transactions are executed, verify the system:

```bash
# Check current implementations
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
    --rpc-url $MAINNET_RPC

# Check admin implementation
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f \
    --rpc-url $MAINNET_RPC

# Check ETHFI strategy config
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenStrategyConfig(address)" \
    0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB \
    --rpc-url $MAINNET_RPC

# Check token types
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenInfos(address)" \
    0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB \
    --rpc-url $MAINNET_RPC
```

### Expected Results
- Implementation addresses should match deployed contracts
- Strategy configs should return deployed strategy addresses
- Token types: 0 = Native, 1 = Staked
- System should be fully functional

## Pre-Deployment Backup

**CRITICAL: Capture current state before ANY deployment steps**

### Backup Current Implementation Addresses

```bash
# Get current Core implementation
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
    --rpc-url $MAINNET_RPC

# Get current Admin implementation  
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f \
    --rpc-url $MAINNET_RPC
```

### Backup Current Strategy Configurations

```bash
# ETHFI current strategy
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenStrategyConfig(address)" \
    0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB \
    --rpc-url $MAINNET_RPC

# EIGEN current strategy  
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenStrategyConfig(address)" \
    0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 \
    --rpc-url $MAINNET_RPC
```

### Backup Current Token Types

```bash
# Check all token types
for token in 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 0x86B5780b606940Eb59A062aA85a07959518c0161 0xE77076518A813616315EaAba6cA8e595E845EeE9 0x0a6E7Ba5042B38349e437ec6Db6214AEC7B35676; do
  echo "Token $token:"
  cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenInfos(address)" \
    $token \
    --rpc-url $MAINNET_RPC
done
```

**Save all output to a file for rollback reference!**

## Emergency Rollback Procedures

### Can We Rollback? YES! ✅

**The deployment is FULLY REVERSIBLE because:**
- Proxy upgrades can be reverted to original implementations
- Strategy configurations can be reset to previous values  
- Token type classifications can be migrated back
- No irreversible ownership or governance changes occur

### Rollback Decision Matrix

| Scenario | Rollback Required? | Risk Level | Action |
|----------|-------------------|------------|---------|
| Deployment fails (Phase 1) | No | Low | Re-run deployment |
| Validation fails (Phase 2) | No | Low | Fix and redeploy |
| Single batch fails (Phase 4) | Maybe | Medium | Complete or rollback |
| Multiple batches fail | Yes | High | Full rollback |
| System not functional | Yes | Critical | Emergency rollback |

### Rollback Procedures by Phase

#### Phase 1-2 Failures (Low Risk)
**No rollback needed** - original system unchanged.

#### Phase 4 Partial Failures

**If only Batch 1 (Upgrade) executed:**
- New implementations active but no strategies configured
- System should function normally
- **Decision**: Complete deployment OR rollback implementations

**If Batch 1 + 2 (Upgrade + Configure) executed:**
- Strategies configured but token types not migrated
- Redemptions may not use new priority logic  
- **Decision**: Complete migration OR rollback everything

### Full Emergency Rollback Procedure

**Use this if the system is broken after deployment**

#### Step 1: Prepare Rollback Transactions

Create Safe transactions to revert ALL changes:

```json
{
  "version": "1.0",
  "chainId": "1", 
  "transactions": [
    {
      "to": "0x8F08B70456eb22f6109F57b8fafE862ED28E6040",
      "value": "0",
      "data": "[upgradeToAndCall calldata with ORIGINAL_CORE_IMPL]",
      "description": "EMERGENCY: Rollback Core implementation"
    },
    {
      "to": "0x8F08B70456eb22f6109F57b8fafE862ED28E6040", 
      "value": "0",
      "data": "[setAdminImpl calldata with ORIGINAL_ADMIN_IMPL]",
      "description": "EMERGENCY: Rollback Admin implementation"
    },
    {
      "to": "0x8F08B70456eb22f6109F57b8fafE862ED28E6040",
      "value": "0", 
      "data": "[setTokenStrategyConfig calldata - remove ETHFI strategy]",
      "description": "EMERGENCY: Remove ETHFI strategy"
    },
    {
      "to": "0x8F08B70456eb22f6109F57b8fafE862ED28E6040",
      "value": "0",
      "data": "[setTokenStrategyConfig calldata - remove EIGEN strategy]", 
      "description": "EMERGENCY: Remove EIGEN strategy"
    },
    {
      "to": "0x8F08B70456eb22f6109F57b8fafE862ED28E6040",
      "value": "0",
      "data": "[migrateTokenTypes calldata - revert to original types]",
      "description": "EMERGENCY: Revert token type classifications"
    }
  ]
}
```

#### Step 2: Generate Rollback Calldata

```bash
# Generate exact calldata for rollback transactions
cast calldata "upgradeToAndCall(address,bytes)" \
    [ORIGINAL_CORE_IMPL] \
    0x

cast calldata "setAdminImpl(address)" \
    [ORIGINAL_ADMIN_IMPL]

# Remove strategy configurations (set to zero address)
cast calldata "setTokenStrategyConfig(address,(address,uint256))" \
    0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB \
    "0x0000000000000000000000000000000000000000,0"

cast calldata "setTokenStrategyConfig(address,(address,uint256))" \
    0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83 \
    "0x0000000000000000000000000000000000000000,0"

# Revert token types (set all to Native = 0)
cast calldata "migrateTokenTypes(address[],uint8[])" \
    "[0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83,0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB,0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,0x86B5780b606940Eb59A062aA85a07959518c0161,0xE77076518A813616315EaAba6cA8e595E845EeE9,0x0a6E7Ba5042B38349e437ec6Db6214AEC7B35676]" \
    "[0,0,0,0,0,0]"
```

#### Step 3: Execute Rollback

1. **IMMEDIATE ACTION** - Import rollback JSON into Safe Transaction Builder
2. **PRIORITY EXECUTION** - Get all signers to sign immediately
3. **VERIFY EACH STEP** - Check each transaction succeeds
4. **VALIDATE ROLLBACK** - Confirm system restored to original state

#### Step 4: Verify Rollback Success

```bash
# Verify implementations restored
cast storage 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
    --rpc-url $MAINNET_RPC
# Should match ORIGINAL_CORE_IMPL

# Verify strategies removed
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tokenStrategyConfig(address)" \
    0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB \
    --rpc-url $MAINNET_RPC  
# Should return (0x0000000000000000000000000000000000000000, 0)

# Test basic functionality
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    "tvl()" \
    --rpc-url $MAINNET_RPC
# Should return reasonable TVL value
```

### Rollback Testing (REQUIRED)

**Test rollback procedures on fork BEFORE mainnet deployment:**

```bash
# 1. Start fork with current mainnet state
anvil --fork-url $MAINNET_RPC --fork-block-number latest

# 2. Override governance  
cast rpc anvil_setStorageAt \
    0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 \
    0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266

# 3. Backup original state (simulate pre-deployment backup)
# [Run backup commands above]

# 4. Execute full deployment
# [Run all 4 phases]

# 5. TEST ROLLBACK - Execute rollback transactions
# [Use calldata generated above]

# 6. Verify rollback restored original state
# [Compare with backed up values]
```

### If Rollback Fails

**Recovery Options:**

1. **Partial Rollback**: Revert only problematic components
   - Example: Keep new implementations, remove only strategies

2. **Governance Override**: Deploy emergency admin
   - Only if Safe multisig is compromised
   - Requires deploying new governance contract

3. **Emergency Pause**: Use protocol pause mechanisms
   - Stops new deposits/withdrawals
   - Gives time to plan recovery

4. **External Recovery**: Contact external experts
   - OpenZeppelin, protocol auditors
   - Solidity debugging specialists

### Emergency Communication Plan

**If rollback is required:**

1. **Immediate**: Notify all Safe signers via secure channels
2. **Within 1 hour**: Update protocol status page
3. **Within 4 hours**: Public communication about incident
4. **Within 24 hours**: Post-mortem and recovery timeline

## Emergency Procedures

### If Deployment Fails (Phase 1)

**Low Risk** - No changes to live system yet.

1. Check gas price and network congestion
2. Verify deployer has sufficient ETH
3. Check for any contract compilation issues
4. Re-run deployment script

### If Validation Fails (Phase 2)

**Low Risk** - Contracts deployed but not connected.

1. Review validation error messages
2. Check if external integrations changed
3. Verify contract addresses in deployment file
4. May need to redeploy contracts

### If Multi-sig Execution Fails (Phase 4)

**High Risk** - System may be in partial upgrade state.

#### Partial Upgrade Recovery

If only upgrade transactions succeeded:
- System should still function with new implementations
- Strategy features not yet available
- Can complete deployment later

If upgrade + configuration succeeded:
- Strategies configured but token types not migrated
- Redemptions use old logic
- Complete migration ASAP

#### Full Rollback (Emergency Only)

**Only if system is completely broken:**

⚠️ **See "Emergency Rollback Procedures" section above for detailed rollback instructions**

**Quick Summary:**
1. Use pre-deployment backup to get original implementation addresses
2. Generate rollback transactions using provided templates
3. Execute through Safe Transaction Builder immediately
4. Verify system restored to original state

**Critical**: Follow the complete rollback procedure documented above - don't skip steps!

### Emergency Contacts

- **Lead Developer**: [Contact info]
- **Safe Signers**: [List of signers]
- **Emergency Multisig**: [Backup multisig if needed]

## Testing Strategy

### Fork Testing (Recommended)

Test the exact deployment on a fork before mainnet:

```bash
# Start anvil fork
anvil --fork-url $MAINNET_RPC --fork-block-number latest

# Override governance (in separate terminal)
cast rpc anvil_setStorageAt \
    0x8F08B70456eb22f6109F57b8fafE862ED28E6040 \
    0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87 \
    0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266

# Test deployment
forge script script/staking/mainnet/01_DeployContracts.s.sol --rpc-url http://localhost:8545 --broadcast
forge script script/staking/mainnet/02_ValidateDeployment.s.sol --rpc-url http://localhost:8545
forge script script/staking/mainnet/03_GenerateUpgradeTxns.s.sol --rpc-url http://localhost:8545

# Simulate multi-sig transactions
# [Use generated calldata to test upgrades]
```

### Transaction Simulation

Use [Tenderly](https://tenderly.co) or similar tools:

1. Import LRTSquared contract
2. Simulate each transaction from the multi-sig
3. Verify state changes are as expected
4. Check for any reverts or unexpected behavior

## Monitoring

After deployment, monitor:

### Key Metrics
- Total Value Locked (TVL)
- Strategy deposit/withdrawal volumes
- Token type classifications working correctly
- No reverted transactions in strategy operations

### Manual Strategy Testing

After deployment, test strategy functionality:

```bash
# Test depositToStrategy (Multi-sig required)
# 1. Generate calldata for Safe Transaction Builder:
cast calldata "depositToStrategy(address,uint256)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB 1000000000000000000

# 2. Create Safe transaction with:
# - To: 0x8F08B70456eb22f6109F57b8fafE862ED28E6040
# - Data: [generated calldata]
# - Value: 0

# Test withdrawFromStrategy (Multi-sig required)
# 1. Generate calldata for Safe Transaction Builder:
cast calldata "withdrawFromStrategy(address,uint256)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB 500000000000000000

# 2. Create Safe transaction with:
# - To: 0x8F08B70456eb22f6109F57b8fafE862ED28E6040  
# - Data: [generated calldata]
# - Value: 0

# Verify strategy operations
cast call 0x8F08B70456eb22f6109F57b8fafE862ED28E6040 "tokenStrategyConfig(address)" 0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB --rpc-url $MAINNET_RPC
```

**Note:** All strategy operations require multi-sig governance execution through Safe Transaction Builder.

### Dashboards
- Etherscan for transaction monitoring
- Safe app for multi-sig status
- Custom monitoring for strategy performance

### Alerts
- Set up alerts for:
  - Large TVL changes
  - Failed strategy operations
  - Unusual withdrawal patterns
  - Multi-sig pending transactions

## Conclusion

This deployment process is designed for maximum safety with multiple validation checkpoints. The phased approach allows for stopping and recovery at any stage.

**Key Principles:**
- ✅ Validate thoroughly at each phase
- ✅ Never rush multi-sig execution
- ✅ Test on fork first
- ✅ Have emergency procedures ready
- ✅ Monitor closely after deployment

For questions or issues during deployment, refer to the emergency contacts above.