// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Utils} from "../../Utils.sol";
import {LRTSquaredCore} from "../../../src/LRTSquared/LRTSquaredCore.sol";
import {LRTSquaredAdmin} from "../../../src/LRTSquared/LRTSquaredAdmin.sol";
import {SEthFiStrategy} from "../../../src/strategies/SEthFiStrategy.sol";
import {EEigenStrategy} from "../../../src/strategies/EEigenStrategy.sol";
import {MainnetConstants} from "./MainnetConstants.sol";

/**
 * @title DeployContracts - Mainnet contract deployment
 * @notice Phase 1: Deploy new implementations and strategies (no governance operations)
 * @dev This script only deploys contracts and saves addresses - no proxy upgrades
 */
contract DeployContracts is Script, Utils {
    using MainnetConstants for *;

    struct DeploymentResult {
        address lrtSquaredCoreImpl;
        address lrtSquaredAdminImpl;
        address sEthFiStrategy;
        address eEigenStrategy;
        uint256 deploymentTimestamp;
        address deployer;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Mainnet Contract Deployment ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("Block Number:", block.number);

        // Verify we're on mainnet
        require(block.chainid == 1, "Must deploy on mainnet (chain ID 1)");

        vm.startBroadcast(deployerPrivateKey);

        DeploymentResult memory result = _deployAllContracts(deployer);

        vm.stopBroadcast();

        // Save deployment results
        _saveDeploymentResults(result);

        // Print deployment summary
        _printDeploymentSummary(result);

        console2.log("=== Deployment Complete ===");
        console2.log("Proceed to validation phase: 02_ValidateDeployment.s.sol");
    }

    function _deployAllContracts(address deployer) internal returns (DeploymentResult memory result) {
        console2.log("\n--- Deploying Implementations ---");

        // Deploy Core implementation
        result.lrtSquaredCoreImpl = address(new LRTSquaredCore());
        console2.log("LRTSquaredCore deployed:", result.lrtSquaredCoreImpl);

        // Deploy Admin implementation
        result.lrtSquaredAdminImpl = address(new LRTSquaredAdmin());
        console2.log("LRTSquaredAdmin deployed:", result.lrtSquaredAdminImpl);

        console2.log("\n--- Deploying Strategies ---");

        // Deploy SEthFiStrategy
        result.sEthFiStrategy =
            address(new SEthFiStrategy(MainnetConstants.LRT_SQUARED_PROXY, MainnetConstants.PRICE_PROVIDER));
        console2.log("SEthFiStrategy deployed:", result.sEthFiStrategy);

        // Deploy EEigenStrategy
        result.eEigenStrategy =
            address(new EEigenStrategy(MainnetConstants.LRT_SQUARED_PROXY, MainnetConstants.PRICE_PROVIDER));
        console2.log("EEigenStrategy deployed:", result.eEigenStrategy);

        // Set metadata
        result.deploymentTimestamp = block.timestamp;
        result.deployer = deployer;

        return result;
    }

    function _saveDeploymentResults(DeploymentResult memory result) internal {
        string memory json = "deployment";

        // Contract addresses
        vm.serializeAddress(json, "lrtSquaredCoreImpl", result.lrtSquaredCoreImpl);
        vm.serializeAddress(json, "lrtSquaredAdminImpl", result.lrtSquaredAdminImpl);
        vm.serializeAddress(json, "sEthFiStrategy", result.sEthFiStrategy);
        vm.serializeAddress(json, "eEigenStrategy", result.eEigenStrategy);

        // Metadata
        vm.serializeUint(json, "deploymentTimestamp", result.deploymentTimestamp);
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeUint(json, "blockNumber", block.number);
        vm.serializeAddress(json, "deployer", result.deployer);

        // Existing addresses for reference
        vm.serializeAddress(json, "lrtSquaredProxy", MainnetConstants.LRT_SQUARED_PROXY);
        vm.serializeAddress(json, "governor", MainnetConstants.GOVERNOR);
        vm.serializeAddress(json, "priceProvider", MainnetConstants.PRICE_PROVIDER);

        string memory finalJson = vm.serializeString(json, "phase", "contracts_deployed");

        // Write to deployment file
        writeDeploymentFile(finalJson);

        console2.log("Deployment results saved to deployments/1/deployments.json");
    }

    function _printDeploymentSummary(DeploymentResult memory result) internal pure {
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("Deployer: %s", result.deployer);
        console2.log("Timestamp: %s", result.deploymentTimestamp);
        console2.log("");
        console2.log("Core Implementation: %s", result.lrtSquaredCoreImpl);
        console2.log("Admin Implementation: %s", result.lrtSquaredAdminImpl);
        console2.log("SEthFi Strategy: %s", result.sEthFiStrategy);
        console2.log("EEigen Strategy: %s", result.eEigenStrategy);
        console2.log("");
        console2.log("Target Proxy: %s", MainnetConstants.LRT_SQUARED_PROXY);
        console2.log("Governor: %s", MainnetConstants.GOVERNOR);
        console2.log("");
        console2.log("Next Steps:");
        console2.log("1. Run validation: forge script script/staking/mainnet/02_ValidateDeployment.s.sol");
        console2.log("2. Generate transactions: forge script script/staking/mainnet/03_GenerateUpgradeTxns.s.sol");
        console2.log("3. Import transactions into Safe Transaction Builder");
    }
}
