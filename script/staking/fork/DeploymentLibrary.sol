// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {LRTSquaredCore} from "../../../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../../../src/LRTSquared/LRTSquaredAdmin.sol";
import {LRTSquaredStorage} from "../../../src/LRTSquared/LRTSquaredStorage.sol";
import {SEthFiStrategy} from "../../../src/strategies/SEthFiStrategy.sol";
import {EEigenStrategy} from "../../../src/strategies/EEigenStrategy.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

library DeploymentLibrary {
    using DeploymentConstants for *;
    
    struct DeploymentResult {
        address lrtSquaredCoreImpl;
        address lrtSquaredAdminImpl;
        address newSEthFiStrategy;
        address newEEigenStrategy;
    }
    
    event DeploymentStep(string step, address deployedContract);
    event GovernanceOverride(address proxy, address newGovernor);
    event TokenTypeMigrated(address token, ILRTSquared.TokenType tokenType);
    
    function deployImplementations() internal returns (address coreImpl, address adminImpl) {
        // Deploy Core implementation
        coreImpl = address(new LRTSquaredCore());
        emit DeploymentStep("LRTSquaredCore", coreImpl);
        
        // Deploy Admin implementation
        adminImpl = address(new LRTSquaredAdmin());
        emit DeploymentStep("LRTSquaredAdmin", adminImpl);
        
        return (coreImpl, adminImpl);
    }
    
    function deployStrategies() internal returns (address sEthFiStrategy, address eEigenStrategy) {
        // Deploy new SEthFiStrategy with vault's price provider
        sEthFiStrategy = address(new SEthFiStrategy(
            DeploymentConstants.LRT_SQUARED_PROXY, 
            DeploymentConstants.PRICE_PROVIDER
        ));
        emit DeploymentStep("SEthFiStrategy", sEthFiStrategy);
        
        // Deploy new EEigenStrategy with vault's price provider
        eEigenStrategy = address(new EEigenStrategy(
            DeploymentConstants.LRT_SQUARED_PROXY, 
            DeploymentConstants.PRICE_PROVIDER
        ));
        emit DeploymentStep("EEigenStrategy", eEigenStrategy);
        
        return (sEthFiStrategy, eEigenStrategy);
    }
    
    function setupGovernanceOverride(Vm vm) internal {
        // Set deployer EOA as governor in the proxy for upgrade permissions
        vm.store(
            DeploymentConstants.LRT_SQUARED_PROXY, 
            DeploymentConstants.GOVERNOR_SLOT, 
            bytes32(uint256(uint160(DeploymentConstants.FORK_DEPLOYER)))
        );
        
        emit GovernanceOverride(DeploymentConstants.LRT_SQUARED_PROXY, DeploymentConstants.FORK_DEPLOYER);
    }
    
    
    function upgradeContracts(address coreImpl, address adminImpl) internal {
        // Upgrade to new Core implementation
        UUPSUpgradeable(DeploymentConstants.LRT_SQUARED_PROXY).upgradeToAndCall(coreImpl, "");
        
        // Set new Admin implementation
        LRTSquaredStorage(DeploymentConstants.LRT_SQUARED_PROXY).setAdminImpl(adminImpl);
    }
    
    function configureStrategies(address sEthFiStrategy, address eEigenStrategy) internal {
        ILRTSquared lrtSquared = ILRTSquared(DeploymentConstants.LRT_SQUARED_PROXY);
        
        // Configure strategy for ETHFI token
        lrtSquared.setTokenStrategyConfig(DeploymentConstants.ETHFI, ILRTSquared.StrategyConfig({
            strategyAdapter: sEthFiStrategy,
            maxSlippageInBps: 1
        }));
        
        // Configure strategy for EIGEN token
        lrtSquared.setTokenStrategyConfig(DeploymentConstants.EIGEN, ILRTSquared.StrategyConfig({
            strategyAdapter: eEigenStrategy,
            maxSlippageInBps: 1
        }));
    }
    
    function migrateTokenTypes() internal {
        // All 6 tokens in registration order
        address[] memory tokens = new address[](6);
        tokens[0] = DeploymentConstants.EIGEN;
        tokens[1] = DeploymentConstants.ETHFI;
        tokens[2] = DeploymentConstants.WETH;
        tokens[3] = DeploymentConstants.sETHFI;
        tokens[4] = DeploymentConstants.eEIGEN;
        tokens[5] = DeploymentConstants.SWELL;
        
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](6);
        types[0] = ILRTSquared.TokenType.Native;  // EIGEN
        types[1] = ILRTSquared.TokenType.Native;  // ETHFI
        types[2] = ILRTSquared.TokenType.Native;  // WETH
        types[3] = ILRTSquared.TokenType.Staked;  // sETHFI
        types[4] = ILRTSquared.TokenType.Staked;  // eEIGEN
        types[5] = ILRTSquared.TokenType.Native;  // SWELL
        
        ILRTSquared lrtSquared = ILRTSquared(DeploymentConstants.LRT_SQUARED_PROXY);
        lrtSquared.migrateTokenTypes(tokens, types);
        
        // Emit events for each token type migration
        for (uint256 i = 0; i < tokens.length; i++) {
            emit TokenTypeMigrated(tokens[i], types[i]);
        }
    }
    
    function getProxyImplementation(Vm vm, address proxy) internal view returns (address) {
        bytes32 value = vm.load(proxy, DeploymentConstants.IMPLEMENTATION_SLOT);
        return address(uint160(uint256(value)));
    }
    
    function getProxyAdminImpl(Vm vm, address proxy) internal view returns (address) {
        bytes32 value = vm.load(proxy, DeploymentConstants.ADMIN_IMPL_SLOT);
        return address(uint160(uint256(value)));
    }
    
    function performCompleteDeployment(Vm vm) internal returns (DeploymentResult memory result) {
        // Step 1: Deploy implementations
        (result.lrtSquaredCoreImpl, result.lrtSquaredAdminImpl) = deployImplementations();
        
        // Step 2: Deploy strategies
        (result.newSEthFiStrategy, result.newEEigenStrategy) = deployStrategies();
        
        // Step 3: Setup governance override
        setupGovernanceOverride(vm);
        
        // Step 4: Upgrade contracts
        upgradeContracts(result.lrtSquaredCoreImpl, result.lrtSquaredAdminImpl);
        
        // Step 5: Configure strategies
        configureStrategies(result.newSEthFiStrategy, result.newEEigenStrategy);
        
        // Step 6: Migrate token types
        migrateTokenTypes();
        
        
        return result;
    }
    
    function verifyDeployment(Vm vm, DeploymentResult memory deployment) internal view {
        ILRTSquared lrtSquared = ILRTSquared(DeploymentConstants.LRT_SQUARED_PROXY);
        
        // Verify implementations are set correctly
        address currentCoreImpl = getProxyImplementation(vm, DeploymentConstants.LRT_SQUARED_PROXY);
        address currentAdminImpl = getProxyAdminImpl(vm, DeploymentConstants.LRT_SQUARED_PROXY);
        
        require(currentCoreImpl == deployment.lrtSquaredCoreImpl, "Core implementation not set correctly");
        require(currentAdminImpl == deployment.lrtSquaredAdminImpl, "Admin implementation not set correctly");
        
        // Verify token types
        ILRTSquared.TokenInfo memory eigenInfo = lrtSquared.tokenInfos(DeploymentConstants.EIGEN);
        ILRTSquared.TokenInfo memory ethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.ETHFI);
        ILRTSquared.TokenInfo memory wethInfo = lrtSquared.tokenInfos(DeploymentConstants.WETH);
        ILRTSquared.TokenInfo memory sethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.sETHFI);
        ILRTSquared.TokenInfo memory eeigenInfo = lrtSquared.tokenInfos(DeploymentConstants.eEIGEN);
        ILRTSquared.TokenInfo memory swellInfo = lrtSquared.tokenInfos(DeploymentConstants.SWELL);
        
        require(eigenInfo.tokenType == ILRTSquared.TokenType.Native, "EIGEN should be Native");
        require(ethfiInfo.tokenType == ILRTSquared.TokenType.Native, "ETHFI should be Native");
        require(wethInfo.tokenType == ILRTSquared.TokenType.Native, "WETH should be Native");
        require(sethfiInfo.tokenType == ILRTSquared.TokenType.Staked, "sETHFI should be Staked");
        require(eeigenInfo.tokenType == ILRTSquared.TokenType.Staked, "eEIGEN should be Staked");
        require(swellInfo.tokenType == ILRTSquared.TokenType.Native, "SWELL should be Native");
        
        // Verify strategies
        ILRTSquared.StrategyConfig memory ethfiStrategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        ILRTSquared.StrategyConfig memory eigenStrategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        
        require(ethfiStrategyConfig.strategyAdapter == deployment.newSEthFiStrategy, "SEthFiStrategy not set correctly");
        require(eigenStrategyConfig.strategyAdapter == deployment.newEEigenStrategy, "EEigenStrategy not set correctly");
        require(ethfiStrategyConfig.maxSlippageInBps == 1, "ETHFI strategy slippage not set correctly");
        require(eigenStrategyConfig.maxSlippageInBps == 1, "EIGEN strategy slippage not set correctly");
        
        // Verify TVL calculation works
        (uint256 tvl,) = lrtSquared.tvl();
        require(tvl > 0, "TVL should be greater than 0");
    }
    
    function findWhale() internal view returns (address) {
        address[] memory candidates = new address[](5);
        candidates[0] = 0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64;
        candidates[1] = 0x8b2409ACCC5aA4D363257d87b194c8C526a56095;
        candidates[2] = 0x3D06bD724DcE8c4e0E60AC670893dF0C1D89D90E;
        candidates[3] = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // Binance
        candidates[4] = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503; // Binance
        
        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 balance = IERC20(DeploymentConstants.LRT_SQUARED_PROXY).balanceOf(candidates[i]);
            if (balance > 100 * 1e18) { // At least 100 KING tokens
                return candidates[i];
            }
        }
        
        return address(0);
    }
}