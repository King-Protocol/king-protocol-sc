// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Utils} from "../../Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LRTSquaredCore} from "../../../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../../../src/LRTSquared/LRTSquaredAdmin.sol";
import {SEthFiStrategy} from "../../../src/strategies/SEthFiStrategy.sol";
import {EEigenStrategy} from "../../../src/strategies/EEigenStrategy.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {MainnetConstants} from "./MainnetConstants.sol";

/**
 * @title ValidateDeployment - Mainnet deployment validation
 * @notice Phase 2: Verify all contracts deployed correctly before governance operations
 * @dev Performs comprehensive validation of deployed contracts
 */
contract ValidateDeployment is Script, Utils {
    using MainnetConstants for *;

    struct DeployedContracts {
        address lrtSquaredCoreImpl;
        address lrtSquaredAdminImpl;
        address sEthFiStrategy;
        address eEigenStrategy;
    }

    function run() external view {
        console2.log("=== Mainnet Deployment Validation ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Block Number:", block.number);

        // Load deployment results
        DeployedContracts memory contracts = _loadDeployedContracts();

        // Perform validations
        _validateImplementations(contracts);
        _validateStrategies(contracts);
        _validateIntegrations(contracts);
        _validateCurrentState();

        console2.log("\n=== VALIDATION COMPLETE ===");
        console2.log("All contracts deployed correctly");
        console2.log("Ready for governance operations");
        console2.log("");
        console2.log("Next step: Generate transactions");
        console2.log("Run: forge script script/staking/mainnet/03_GenerateUpgradeTxns.s.sol");
    }

    function _loadDeployedContracts() internal view returns (DeployedContracts memory contracts) {
        string memory deploymentData = readDeploymentFile();

        contracts.lrtSquaredCoreImpl = vm.parseJsonAddress(deploymentData, ".lrtSquaredCoreImpl");
        contracts.lrtSquaredAdminImpl = vm.parseJsonAddress(deploymentData, ".lrtSquaredAdminImpl");
        contracts.sEthFiStrategy = vm.parseJsonAddress(deploymentData, ".sEthFiStrategy");
        contracts.eEigenStrategy = vm.parseJsonAddress(deploymentData, ".eEigenStrategy");

        console2.log("Loaded contract addresses from deployment file");
        return contracts;
    }

    function _validateImplementations(DeployedContracts memory contracts) internal view {
        console2.log("\n--- Validating Implementations ---");

        // Validate Core implementation
        require(contracts.lrtSquaredCoreImpl != address(0), "Core implementation not deployed");
        require(contracts.lrtSquaredCoreImpl.code.length > 0, "Core implementation has no code");

        // Test Core implementation functions
        LRTSquaredCore coreImpl = LRTSquaredCore(contracts.lrtSquaredCoreImpl);

        // These should not revert (view functions)
        try coreImpl.HUNDRED_PERCENT_IN_BPS() returns (uint64 bps) {
            require(bps == 10000, "Unexpected HUNDRED_PERCENT_IN_BPS value");
        } catch {
            revert("Core implementation HUNDRED_PERCENT_IN_BPS failed");
        }

        console2.log("LRTSquaredCore implementation valid");

        // Validate Admin implementation
        require(contracts.lrtSquaredAdminImpl != address(0), "Admin implementation not deployed");
        require(contracts.lrtSquaredAdminImpl.code.length > 0, "Admin implementation has no code");

        console2.log("LRTSquaredAdmin implementation valid");
    }

    function _validateStrategies(DeployedContracts memory contracts) internal view {
        console2.log("\n--- Validating Strategies ---");

        // Validate SEthFiStrategy
        _validateSEthFiStrategy(contracts.sEthFiStrategy);

        // Validate EEigenStrategy
        _validateEEigenStrategy(contracts.eEigenStrategy);
    }

    function _validateSEthFiStrategy(address strategyAddr) internal view {
        require(strategyAddr != address(0), "SEthFiStrategy not deployed");
        require(strategyAddr.code.length > 0, "SEthFiStrategy has no code");

        SEthFiStrategy strategy = SEthFiStrategy(strategyAddr);

        // Validate configuration
        require(strategy.vault() == MainnetConstants.LRT_SQUARED_PROXY, "SEthFiStrategy vault mismatch");
        require(
            address(strategy.priceProvider()) == MainnetConstants.PRICE_PROVIDER,
            "SEthFiStrategy price provider mismatch"
        );
        require(strategy.returnToken() == MainnetConstants.sETHFI, "SEthFiStrategy return token mismatch");
        require(strategy.token() == MainnetConstants.ETHFI, "SEthFiStrategy token mismatch");
        require(strategy.getBoringVault() != address(0), "SEthFiStrategy boring vault not set");
        require(strategy.getWithdrawalQueue() != address(0), "SEthFiStrategy withdrawal queue not set");

        console2.log("SEthFiStrategy valid");
    }

    function _validateEEigenStrategy(address strategyAddr) internal view {
        require(strategyAddr != address(0), "EEigenStrategy not deployed");
        require(strategyAddr.code.length > 0, "EEigenStrategy has no code");

        EEigenStrategy strategy = EEigenStrategy(strategyAddr);

        // Validate configuration
        require(strategy.vault() == MainnetConstants.LRT_SQUARED_PROXY, "EEigenStrategy vault mismatch");
        require(
            address(strategy.priceProvider()) == MainnetConstants.PRICE_PROVIDER,
            "EEigenStrategy price provider mismatch"
        );
        require(strategy.returnToken() == MainnetConstants.eEIGEN, "EEigenStrategy return token mismatch");
        require(strategy.token() == MainnetConstants.EIGEN, "EEigenStrategy token mismatch");
        require(strategy.getBoringVault() != address(0), "EEigenStrategy boring vault not set");
        require(strategy.getWithdrawalQueue() != address(0), "EEigenStrategy withdrawal queue not set");

        console2.log("EEigenStrategy valid");
    }

    function _validateIntegrations(DeployedContracts memory contracts) internal view {
        console2.log("\n--- Validating External Integrations ---");

        // Validate token contracts exist and have expected properties
        IERC20 ethfi = IERC20(MainnetConstants.ETHFI);
        IERC20 eigen = IERC20(MainnetConstants.EIGEN);
        IERC20 sethfi = IERC20(MainnetConstants.sETHFI);
        IERC20 eeigen = IERC20(MainnetConstants.eEIGEN);

        // These should not revert
        require(ethfi.totalSupply() > 0, "ETHFI token invalid");
        require(eigen.totalSupply() > 0, "EIGEN token invalid");
        require(sethfi.totalSupply() > 0, "sETHFI token invalid");
        require(eeigen.totalSupply() > 0, "eEIGEN token invalid");

        console2.log("Token contracts valid");

        // Validate price provider
        require(MainnetConstants.PRICE_PROVIDER.code.length > 0, "Price provider has no code");
        console2.log("Price provider valid");

        // Validate withdrawal queues
        require(MainnetConstants.sETHFI_QUEUE.code.length > 0, "sETHFI queue has no code");
        require(MainnetConstants.eEIGEN_QUEUE.code.length > 0, "eEIGEN queue has no code");
        console2.log("Withdrawal queues valid");
    }

    function _validateCurrentState() internal view {
        console2.log("\n--- Validating Current LRTSquared State ---");

        ILRTSquared lrtSquared = ILRTSquared(MainnetConstants.LRT_SQUARED_PROXY);

        // Validate proxy is functional
        (uint256 tvl,) = lrtSquared.tvl();
        require(tvl > 0, "LRTSquared TVL should be > 0");
        console2.log("Current TVL: %s wei", tvl);

        // Validate current token configurations
        ILRTSquared.TokenInfo memory eigenInfo = lrtSquared.tokenInfos(MainnetConstants.EIGEN);
        ILRTSquared.TokenInfo memory ethfiInfo = lrtSquared.tokenInfos(MainnetConstants.ETHFI);

        require(eigenInfo.registered, "EIGEN should be registered");
        require(ethfiInfo.registered, "ETHFI should be registered");

        console2.log("Current LRTSquared state valid");

        // Validate governance
        // Note: We can't easily validate the governor without potentially causing state changes
        console2.log("Governor address: %s", MainnetConstants.GOVERNOR);
        console2.log("Governance configuration ready");
    }
}
