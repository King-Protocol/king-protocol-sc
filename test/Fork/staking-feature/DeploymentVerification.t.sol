// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {SEthFiStrategy} from "../../../src/strategies/SEthFiStrategy.sol";
import {EEigenStrategy} from "../../../src/strategies/EEigenStrategy.sol";
import {DeploymentLibrary} from "../../../script/staking/fork/DeploymentLibrary.sol";
import {DeploymentConstants} from "../../../script/staking/fork/DeploymentConstants.sol";
import {StakingIntegrationBase} from "./shared/StakingIntegrationBase.t.sol";

/**
 * @title DeploymentVerification
 * @notice Tests that verify the deployment script executed correctly
 * @dev Uses the actual DeploymentLibrary to test deployment functionality
 */
contract DeploymentVerification is StakingIntegrationBase {
    function test_DeploymentScriptExecution() public view {
        // Verify deployment results are set
        assertTrue(deployment.lrtSquaredCoreImpl != address(0), "Core implementation should be deployed");
        assertTrue(deployment.lrtSquaredAdminImpl != address(0), "Admin implementation should be deployed");
        assertTrue(deployment.newSEthFiStrategy != address(0), "SEthFi strategy should be deployed");
        assertTrue(deployment.newEEigenStrategy != address(0), "EEigen strategy should be deployed");

        // Verify all addresses are unique (no accidental duplicates)
        assertTrue(
            deployment.lrtSquaredCoreImpl != deployment.lrtSquaredAdminImpl, "Core and Admin should be different"
        );
        assertTrue(deployment.newSEthFiStrategy != deployment.newEEigenStrategy, "Strategies should be different");

        // Verify proxy is using the deployed implementations
        address currentCoreImpl = DeploymentLibrary.getProxyImplementation(vm, DeploymentConstants.LRT_SQUARED_PROXY);
        address currentAdminImpl = DeploymentLibrary.getProxyAdminImpl(vm, DeploymentConstants.LRT_SQUARED_PROXY);
        assertEq(currentCoreImpl, deployment.lrtSquaredCoreImpl, "Proxy should use deployed core implementation");
        assertEq(currentAdminImpl, deployment.lrtSquaredAdminImpl, "Proxy should use deployed admin implementation");

        // Verify strategies are configured correctly
        ILRTSquared.StrategyConfig memory ethfiStrategy = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        ILRTSquared.StrategyConfig memory eigenStrategy = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        assertEq(ethfiStrategy.strategyAdapter, deployment.newSEthFiStrategy, "ETHFI should use deployed strategy");
        assertEq(eigenStrategy.strategyAdapter, deployment.newEEigenStrategy, "EIGEN should use deployed strategy");
    }

    function test_ProxyImplementationsSet() public view {
        // Verify proxy implementations using storage slots
        address coreImpl = DeploymentLibrary.getProxyImplementation(vm, DeploymentConstants.LRT_SQUARED_PROXY);
        address adminImpl = DeploymentLibrary.getProxyAdminImpl(vm, DeploymentConstants.LRT_SQUARED_PROXY);

        assertEq(coreImpl, deployment.lrtSquaredCoreImpl, "Core implementation should match deployed");
        assertEq(adminImpl, deployment.lrtSquaredAdminImpl, "Admin implementation should match deployed");
    }

    function test_TokenConfigurationsSet() public view {
        // Test all token configurations were set correctly
        _verifyTokenConfiguration(DeploymentConstants.EIGEN, ILRTSquared.TokenType.Native);
        _verifyTokenConfiguration(DeploymentConstants.ETHFI, ILRTSquared.TokenType.Native);
        _verifyTokenConfiguration(DeploymentConstants.WETH, ILRTSquared.TokenType.Native);
        _verifyTokenConfiguration(DeploymentConstants.sETHFI, ILRTSquared.TokenType.Staked);
        _verifyTokenConfiguration(DeploymentConstants.eEIGEN, ILRTSquared.TokenType.Staked);
        _verifyTokenConfiguration(DeploymentConstants.SWELL, ILRTSquared.TokenType.Native);
    }

    function test_StrategyConfigurationsSet() public view {
        // Verify ETHFI strategy configuration (for staking)
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        assertEq(ethfiConfig.strategyAdapter, deployment.newSEthFiStrategy, "ETHFI strategy should be set");
        assertEq(ethfiConfig.maxSlippageInBps, 1, "ETHFI slippage should be 1 bps");

        // Verify EIGEN strategy configuration (for staking)
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        assertEq(eigenConfig.strategyAdapter, deployment.newEEigenStrategy, "EIGEN strategy should be set");
        assertEq(eigenConfig.maxSlippageInBps, 1, "EIGEN slippage should be 1 bps");

        // Verify strategy contracts are properly configured
        _verifyStrategyContract(deployment.newSEthFiStrategy, DeploymentConstants.ETHFI, DeploymentConstants.sETHFI);
        _verifyStrategyContract(deployment.newEEigenStrategy, DeploymentConstants.EIGEN, DeploymentConstants.eEIGEN);
    }

    function _verifyTokenConfiguration(address token, ILRTSquared.TokenType expectedType) internal view {
        ILRTSquared.TokenInfo memory tokenInfo = lrtSquared.tokenInfos(token);
        assertTrue(tokenInfo.registered, string(abi.encodePacked("Token should be registered: ", vm.toString(token))));
        assertTrue(tokenInfo.whitelisted, string(abi.encodePacked("Token should be whitelisted: ", vm.toString(token))));
        assertEq(
            uint256(tokenInfo.tokenType),
            uint256(expectedType),
            string(abi.encodePacked("Token type mismatch: ", vm.toString(token)))
        );
        assertGt(
            tokenInfo.positionWeightLimit,
            0,
            string(abi.encodePacked("Token should have weight limit: ", vm.toString(token)))
        );
    }

    function _verifyStrategyContract(address strategy, address expectedNative, address expectedStaked) internal view {
        SEthFiStrategy strategyContract;

        if (expectedNative == DeploymentConstants.ETHFI) {
            strategyContract = SEthFiStrategy(strategy);
            assertEq(strategyContract.token(), expectedNative, "Strategy native token should match");
            assertEq(strategyContract.returnToken(), expectedStaked, "Strategy return token should match");
        } else if (expectedNative == DeploymentConstants.EIGEN) {
            EEigenStrategy eigenStrategy = EEigenStrategy(strategy);
            assertEq(eigenStrategy.token(), expectedNative, "Strategy native token should match");
            assertEq(eigenStrategy.returnToken(), expectedStaked, "Strategy return token should match");
        }

        // Common verifications for any strategy
        assertEq(
            SEthFiStrategy(strategy).vault(), DeploymentConstants.LRT_SQUARED_PROXY, "Strategy vault should be proxy"
        );
        assertTrue(SEthFiStrategy(strategy).getWithdrawalQueue() != address(0), "Strategy should have withdrawal queue");
    }
}
