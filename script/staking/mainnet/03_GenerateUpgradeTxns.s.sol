// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Utils} from "../../Utils.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {LRTSquaredStorage} from "../../../src/LRTSquared/LRTSquaredStorage.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {MainnetConstants} from "./MainnetConstants.sol";

/**
 * @title GenerateUpgradeTxns - Safe transaction generator
 * @notice Phase 3: Generate Safe Transaction Builder JSON files for multi-sig execution
 * @dev Creates JSON files that can be imported into Safe Transaction Builder
 */
contract GenerateUpgradeTxns is Script, Utils {
    using MainnetConstants for *;

    struct DeployedContracts {
        address lrtSquaredCoreImpl;
        address lrtSquaredAdminImpl;
        address sEthFiStrategy;
        address eEigenStrategy;
    }

    function run() external {
        console2.log("=== Generating Safe Transactions ===");
        console2.log("Chain ID:", block.chainid);

        // Load deployment results
        DeployedContracts memory contracts = _loadDeployedContracts();

        // Generate transaction files
        _generateUpgradeTransactions(contracts);
        _generateConfigureTransactions(contracts);
        _generateMigrateTransactions();

        console2.log("\n=== TRANSACTION GENERATION COMPLETE ===");
        console2.log("Generated files in script/staking/mainnet/transactions/:");
        console2.log("- upgrade.json: Proxy upgrades");
        console2.log("- configure.json: Strategy configurations");
        console2.log("- migrate.json: Token type migration");
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Import each JSON file into Safe Transaction Builder");
        console2.log("2. Review all transactions carefully");
        console2.log("3. Execute in order: upgrade -> configure -> migrate");
    }

    function _loadDeployedContracts() internal view returns (DeployedContracts memory contracts) {
        string memory deploymentData = readDeploymentFile();

        contracts.lrtSquaredCoreImpl = vm.parseJsonAddress(deploymentData, ".lrtSquaredCoreImpl");
        contracts.lrtSquaredAdminImpl = vm.parseJsonAddress(deploymentData, ".lrtSquaredAdminImpl");
        contracts.sEthFiStrategy = vm.parseJsonAddress(deploymentData, ".sEthFiStrategy");
        contracts.eEigenStrategy = vm.parseJsonAddress(deploymentData, ".eEigenStrategy");

        console2.log("Loaded deployed contract addresses");
        return contracts;
    }

    function _generateUpgradeTransactions(DeployedContracts memory contracts) internal {
        console2.log("\n--- Generating Upgrade Transactions ---");

        string memory json = "transactions";
        vm.serializeString(json, "version", "1.0");
        vm.serializeString(json, "chainId", "1");

        // Transaction 1: Upgrade Core implementation
        string memory tx1 = "tx1";
        vm.serializeString(tx1, "to", vm.toString(MainnetConstants.LRT_SQUARED_PROXY));
        vm.serializeString(tx1, "value", "0");

        bytes memory upgradeCalldata =
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", contracts.lrtSquaredCoreImpl, "");
        vm.serializeString(tx1, "data", vm.toString(upgradeCalldata));
        string memory tx1Final =
            vm.serializeString(tx1, "description", "Upgrade LRTSquared to new Core implementation with staking support");

        // Transaction 2: Set Admin implementation
        string memory tx2 = "tx2";
        vm.serializeString(tx2, "to", vm.toString(MainnetConstants.LRT_SQUARED_PROXY));
        vm.serializeString(tx2, "value", "0");

        bytes memory setAdminCalldata = abi.encodeWithSignature("setAdminImpl(address)", contracts.lrtSquaredAdminImpl);
        vm.serializeString(tx2, "data", vm.toString(setAdminCalldata));
        string memory tx2Final =
            vm.serializeString(tx2, "description", "Set new Admin implementation with strategy management functions");

        // Assemble transactions array
        string memory txArray = "txArray";
        vm.serializeString(txArray, "0", tx1Final);
        string memory txArrayFinal = vm.serializeString(txArray, "1", tx2Final);

        string memory finalJson = vm.serializeString(json, "transactions", txArrayFinal);

        // Write upgrade transactions file
        vm.writeJson(finalJson, "script/staking/mainnet/transactions/upgrade.json");
        console2.log("Generated upgrade.json");
    }

    function _generateConfigureTransactions(DeployedContracts memory contracts) internal {
        console2.log("\n--- Generating Configuration Transactions ---");

        string memory json = "transactions";
        vm.serializeString(json, "version", "1.0");
        vm.serializeString(json, "chainId", "1");

        // Transaction 1: Configure ETHFI strategy
        string memory tx1 = "tx1";
        vm.serializeString(tx1, "to", vm.toString(MainnetConstants.LRT_SQUARED_PROXY));
        vm.serializeString(tx1, "value", "0");

        bytes memory ethfiConfigCalldata = abi.encodeWithSignature(
            "setTokenStrategyConfig(address,(address,uint256))",
            MainnetConstants.ETHFI,
            ILRTSquared.StrategyConfig({strategyAdapter: contracts.sEthFiStrategy, maxSlippageInBps: 1})
        );
        vm.serializeString(tx1, "data", vm.toString(ethfiConfigCalldata));
        string memory tx1Final =
            vm.serializeString(tx1, "description", "Configure ETHFI token strategy for staking to sETHFI");

        // Transaction 2: Configure EIGEN strategy
        string memory tx2 = "tx2";
        vm.serializeString(tx2, "to", vm.toString(MainnetConstants.LRT_SQUARED_PROXY));
        vm.serializeString(tx2, "value", "0");

        bytes memory eigenConfigCalldata = abi.encodeWithSignature(
            "setTokenStrategyConfig(address,(address,uint256))",
            MainnetConstants.EIGEN,
            ILRTSquared.StrategyConfig({strategyAdapter: contracts.eEigenStrategy, maxSlippageInBps: 1})
        );
        vm.serializeString(tx2, "data", vm.toString(eigenConfigCalldata));
        string memory tx2Final =
            vm.serializeString(tx2, "description", "Configure EIGEN token strategy for staking to eEIGEN");

        // Assemble transactions array
        string memory txArray = "txArray";
        vm.serializeString(txArray, "0", tx1Final);
        string memory txArrayFinal = vm.serializeString(txArray, "1", tx2Final);

        string memory finalJson = vm.serializeString(json, "transactions", txArrayFinal);

        // Write configuration transactions file
        vm.writeJson(finalJson, "script/staking/mainnet/transactions/configure.json");
        console2.log("Generated configure.json");
    }

    function _generateMigrateTransactions() internal {
        console2.log("\n--- Generating Migration Transactions ---");

        string memory json = "transactions";
        vm.serializeString(json, "version", "1.0");
        vm.serializeString(json, "chainId", "1");

        // Transaction 1: Migrate token types
        string memory tx1 = "tx1";
        vm.serializeString(tx1, "to", vm.toString(MainnetConstants.LRT_SQUARED_PROXY));
        vm.serializeString(tx1, "value", "0");

        // Prepare tokens and types arrays
        address[] memory tokens = new address[](6);
        tokens[0] = MainnetConstants.EIGEN;
        tokens[1] = MainnetConstants.ETHFI;
        tokens[2] = MainnetConstants.WETH;
        tokens[3] = MainnetConstants.sETHFI;
        tokens[4] = MainnetConstants.eEIGEN;
        tokens[5] = MainnetConstants.SWELL;

        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](6);
        types[0] = ILRTSquared.TokenType.Native; // EIGEN
        types[1] = ILRTSquared.TokenType.Native; // ETHFI
        types[2] = ILRTSquared.TokenType.Native; // WETH
        types[3] = ILRTSquared.TokenType.Staked; // sETHFI
        types[4] = ILRTSquared.TokenType.Staked; // eEIGEN
        types[5] = ILRTSquared.TokenType.Native; // SWELL

        bytes memory migrateCalldata = abi.encodeWithSignature("migrateTokenTypes(address[],uint8[])", tokens, types);
        vm.serializeString(tx1, "data", vm.toString(migrateCalldata));
        string memory tx1Final = vm.serializeString(
            tx1, "description", "Migrate token types: Native (EIGEN,ETHFI,WETH,SWELL) and Staked (sETHFI,eEIGEN)"
        );

        // Assemble transactions array
        string memory txArray = "txArray";
        string memory txArrayFinal = vm.serializeString(txArray, "0", tx1Final);

        string memory finalJson = vm.serializeString(json, "transactions", txArrayFinal);

        // Write migration transactions file
        vm.writeJson(finalJson, "script/staking/mainnet/transactions/migrate.json");
        console2.log("Generated migrate.json");
    }
}
