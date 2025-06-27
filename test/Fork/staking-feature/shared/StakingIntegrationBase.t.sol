// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILRTSquared} from "../../../../src/interfaces/ILRTSquared.sol";
import {DeploymentLibrary} from "../../../../script/staking/fork/DeploymentLibrary.sol";
import {DeploymentConstants} from "../../../../script/staking/fork/DeploymentConstants.sol";

/**
 * @title StakingIntegrationBase
 * @notice Base contract for all staking integration tests
 * @dev Provides shared setup, utilities, and deployment functionality
 */
abstract contract StakingIntegrationBase is Test {
    using DeploymentConstants for *;
    
    // Test configuration
    address public whale;
    ILRTSquared public lrtSquared;
    DeploymentLibrary.DeploymentResult public deployment;
    
    function setUp() public virtual {
        // Step 1: Test env variable
        string memory rpc = vm.envString("MAINNET_RPC");
        require(bytes(rpc).length > 0, "MAINNET_RPC is empty");
        
        // Step 2: Create and select fork
        uint256 forkId = vm.createFork(rpc, DeploymentConstants.FORK_BLOCK);
        vm.selectFork(forkId);
        vm.chainId(1337);
        
        // Step 3: Initialize contract interface
        lrtSquared = ILRTSquared(DeploymentConstants.LRT_SQUARED_PROXY);
        
        // Step 4: Apply governance storage overrides for testing
        _setupGovernanceOverrides();
        
        // Step 5: Deploy fresh contracts using the library
        _performDeployment();
        
        // Step 6: Find whale for redemption tests
        whale = DeploymentLibrary.findWhale();
    }
    
    function _setupGovernanceOverrides() internal {
        bytes32 governorSlot = DeploymentConstants.GOVERNOR_SLOT;
        bytes32 lowercaseGovernorBytes32 = 0x000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266;
        
        // Apply overrides to all relevant contracts
        vm.store(0x1cB489ef513E1Cc35C4657c91853A2E6fF1957dE, governorSlot, lowercaseGovernorBytes32);
        vm.store(0x8F08B70456eb22f6109F57b8fafE862ED28E6040, governorSlot, lowercaseGovernorBytes32);
        vm.store(0xD2b8c78A5Eb18A5F3b0392c5479BB45c77D02ff5, governorSlot, lowercaseGovernorBytes32);
        vm.store(0xfDD930c22708c7572278cf74D64f3721Eedc18Ad, governorSlot, lowercaseGovernorBytes32);
        vm.store(0x757Fd23a0fDF9F9d2786f62f96f02Db4D096d10A, governorSlot, lowercaseGovernorBytes32);
        
        // Verify the override worked
        bytes32 storedValue = vm.load(DeploymentConstants.LRT_SQUARED_PROXY, governorSlot);
        require(storedValue == lowercaseGovernorBytes32, "Storage override failed");
    }
    
    function _performDeployment() internal {
        address testGovernor = DeploymentConstants.FORK_DEPLOYER;
        
        vm.startPrank(testGovernor);
        
        // Perform deployment steps manually to avoid governance restore
        (deployment.lrtSquaredCoreImpl, deployment.lrtSquaredAdminImpl) = DeploymentLibrary.deployImplementations();
        (deployment.newSEthFiStrategy, deployment.newEEigenStrategy) = DeploymentLibrary.deployStrategies();
        
        DeploymentLibrary.setupGovernanceOverride(vm);
        DeploymentLibrary.upgradeContracts(deployment.lrtSquaredCoreImpl, deployment.lrtSquaredAdminImpl);
        DeploymentLibrary.configureStrategies(deployment.newSEthFiStrategy, deployment.newEEigenStrategy);
        DeploymentLibrary.migrateTokenTypes();
        
        // Set up depositor permissions for testing (while we still have governance control)
        _setupDepositorPermissions(testGovernor);
        
        
        vm.stopPrank();
        
        // Verify deployment succeeded
        DeploymentLibrary.verifyDeployment(vm, deployment);
    }
    
    function _setupDepositorPermissions(address testGovernor) internal {
        // Set up depositor permissions for test addresses
        address[] memory depositors = new address[](2);
        bool[] memory isDepositor = new bool[](2);
        
        // Add test governor as depositor
        depositors[0] = testGovernor;
        isDepositor[0] = true;
        
        // Add whale as depositor (if found)
        depositors[1] = address(this); // Test contract as depositor for internal calls
        isDepositor[1] = true;
        
        lrtSquared.setDepositors(depositors, isDepositor);
    }
    
    // ===============================================
    // UTILITY FUNCTIONS
    // ===============================================
    
    function _stakeToStrategies() internal {
        address testGovernor = DeploymentConstants.FORK_DEPLOYER;
        vm.startPrank(testGovernor);
        
        uint256 ethfiBalance = IERC20(DeploymentConstants.ETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 eigenBalance = IERC20(DeploymentConstants.EIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        
        // Stake 20% of holdings if available
        if (ethfiBalance > 1000e18) {
            uint256 ethfiToStake = ethfiBalance * 20 / 100;
            try lrtSquared.depositToStrategy(DeploymentConstants.ETHFI, ethfiToStake) {
                // Staking succeeded
            } catch {
                // Staking failed, continue
            }
        }
        
        if (eigenBalance > 1000e18) {
            uint256 eigenToStake = eigenBalance * 20 / 100;
            try lrtSquared.depositToStrategy(DeploymentConstants.EIGEN, eigenToStake) {
                // Staking succeeded
            } catch {
                // Staking failed, continue
            }
        }
        
        vm.stopPrank();
    }
    
    function _getVaultTokenBalances() internal view returns (
        uint256 ethfiBalance,
        uint256 eigenBalance,
        uint256 wethBalance,
        uint256 sethfiBalance,
        uint256 eeigenBalance,
        uint256 swellBalance
    ) {
        ethfiBalance = IERC20(DeploymentConstants.ETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        eigenBalance = IERC20(DeploymentConstants.EIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        wethBalance = IERC20(DeploymentConstants.WETH).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        sethfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        eeigenBalance = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        swellBalance = IERC20(DeploymentConstants.SWELL).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
    }
    
    function _getUserTokenBalances(address user) internal view returns (
        uint256 ethfiBalance,
        uint256 eigenBalance,
        uint256 wethBalance,
        uint256 sethfiBalance,
        uint256 eeigenBalance,
        uint256 swellBalance
    ) {
        ethfiBalance = IERC20(DeploymentConstants.ETHFI).balanceOf(user);
        eigenBalance = IERC20(DeploymentConstants.EIGEN).balanceOf(user);
        wethBalance = IERC20(DeploymentConstants.WETH).balanceOf(user);
        sethfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(user);
        eeigenBalance = IERC20(DeploymentConstants.eEIGEN).balanceOf(user);
        swellBalance = IERC20(DeploymentConstants.SWELL).balanceOf(user);
    }
    
    function _hasNativeTokens() internal view returns (bool) {
        (uint256 ethfi, uint256 eigen, uint256 weth,,, uint256 swell) = _getVaultTokenBalances();
        return (ethfi + eigen + weth + swell) > 0;
    }
    
    function _hasStakedTokens() internal view returns (bool) {
        (,,, uint256 sethfi, uint256 eeigen,) = _getVaultTokenBalances();
        return (sethfi + eeigen) > 0;
    }
    
    function _assumeWhaleExists() internal view {
        vm.assume(whale != address(0));
    }
    
    function _assumeWhaleHasBalance(uint256 minBalance) internal view {
        _assumeWhaleExists();
        uint256 whaleBalance = IERC20(DeploymentConstants.LRT_SQUARED_PROXY).balanceOf(whale);
        vm.assume(whaleBalance >= minBalance);
    }
}