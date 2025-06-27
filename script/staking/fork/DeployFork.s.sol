// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {DeploymentLibrary} from "./DeploymentLibrary.sol";
import {DeploymentConstants} from "./DeploymentConstants.sol";

/**
 * @title DeployFork - Fork deployment script
 * @notice Deploys and upgrades contracts using DeploymentLibrary, exports state for separate testing
 */
contract DeployFork is Script {
    using DeploymentConstants for *;
    
    // Deployment result
    DeploymentLibrary.DeploymentResult public deployment;
    
    function run() external {
        vm.startBroadcast(DeploymentConstants.FORK_DEPLOYER_PK);
        
        console2.log("=== Fork Deployment Script ===");
        console2.log("Using DeploymentLibrary for consistent deployment logic");
        
        // Perform complete deployment using the library
        deployment = DeploymentLibrary.performCompleteDeployment(vm);
        
        // Verify deployment succeeded
        DeploymentLibrary.verifyDeployment(vm, deployment);
        
        // Export deployment state
        printDeploymentState();
        
        vm.stopBroadcast();
        
        console2.log("=== Deployment Complete ===");
        console2.log("Use the exported addresses for testing");
    }
    
    function printDeploymentState() internal view {
        console2.log("\n=== DEPLOYMENT STATE ===");
        console2.log("Copy these addresses for testing:");
        console2.log("CORE_IMPL=%s", deployment.lrtSquaredCoreImpl);
        console2.log("ADMIN_IMPL=%s", deployment.lrtSquaredAdminImpl);
        console2.log("SETHFI_STRATEGY=%s", deployment.newSEthFiStrategy);
        console2.log("EEIGEN_STRATEGY=%s", deployment.newEEigenStrategy);
        console2.log("PROXY=%s", DeploymentConstants.LRT_SQUARED_PROXY);
        
        console2.log("\n=== VERIFICATION ===");
        console2.log("All deployment steps completed successfully");
        console2.log("Token types migrated");
        console2.log("Strategy configurations set");
        console2.log("Ready for integration testing");
    }
}