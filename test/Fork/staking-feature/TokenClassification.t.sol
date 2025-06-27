// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {DeploymentConstants} from "../../../script/staking/fork/DeploymentConstants.sol";
import {StakingIntegrationBase} from "./shared/StakingIntegrationBase.t.sol";

/**
 * @title TokenClassification
 * @notice Tests for token classification (Native vs Staked) after deployment
 * @dev Verifies the deployment script correctly set token types and strategy relationships
 */
contract TokenClassification is StakingIntegrationBase {
    function test_AllTokenTypesSetCorrectly() public view {
        // Test all native tokens are classified as Native (type 0)
        ILRTSquared.TokenInfo memory ethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.ETHFI);
        ILRTSquared.TokenInfo memory eigenInfo = lrtSquared.tokenInfos(DeploymentConstants.EIGEN);
        ILRTSquared.TokenInfo memory wethInfo = lrtSquared.tokenInfos(DeploymentConstants.WETH);
        ILRTSquared.TokenInfo memory swellInfo = lrtSquared.tokenInfos(DeploymentConstants.SWELL);

        assertEq(uint256(ethfiInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "ETHFI should be Native");
        assertEq(uint256(eigenInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "EIGEN should be Native");
        assertEq(uint256(wethInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "WETH should be Native");
        assertEq(uint256(swellInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "SWELL should be Native");

        // Test all staked tokens are classified as Staked (type 1)
        ILRTSquared.TokenInfo memory sethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.sETHFI);
        ILRTSquared.TokenInfo memory eeigenInfo = lrtSquared.tokenInfos(DeploymentConstants.eEIGEN);

        assertEq(uint256(sethfiInfo.tokenType), uint256(ILRTSquared.TokenType.Staked), "sETHFI should be Staked");
        assertEq(uint256(eeigenInfo.tokenType), uint256(ILRTSquared.TokenType.Staked), "eEIGEN should be Staked");
    }

    function test_AllTokensRegisteredAndWhitelisted() public view {
        address[] memory allTokens = new address[](6);
        allTokens[0] = DeploymentConstants.ETHFI;
        allTokens[1] = DeploymentConstants.EIGEN;
        allTokens[2] = DeploymentConstants.WETH;
        allTokens[3] = DeploymentConstants.SWELL;
        allTokens[4] = DeploymentConstants.sETHFI;
        allTokens[5] = DeploymentConstants.eEIGEN;

        for (uint256 i = 0; i < allTokens.length; i++) {
            ILRTSquared.TokenInfo memory tokenInfo = lrtSquared.tokenInfos(allTokens[i]);

            assertTrue(
                tokenInfo.registered,
                string(abi.encodePacked("Token should be registered: ", vm.toString(allTokens[i])))
            );
            assertTrue(
                tokenInfo.whitelisted,
                string(abi.encodePacked("Token should be whitelisted: ", vm.toString(allTokens[i])))
            );
            assertGt(
                tokenInfo.positionWeightLimit,
                0,
                string(abi.encodePacked("Token should have weight limit: ", vm.toString(allTokens[i])))
            );
        }
    }

    function test_StrategyTokenRelationships() public view {
        // Test ETHFI strategy produces sETHFI tokens
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        assertTrue(ethfiConfig.strategyAdapter != address(0), "ETHFI should have strategy configured");

        // Test EIGEN strategy produces eEIGEN tokens
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        assertTrue(eigenConfig.strategyAdapter != address(0), "EIGEN should have strategy configured");

        // Test tokens without strategies don't have strategy configs
        ILRTSquared.StrategyConfig memory wethConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.WETH);
        ILRTSquared.StrategyConfig memory swellConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.SWELL);

        assertEq(wethConfig.strategyAdapter, address(0), "WETH should not have strategy");
        assertEq(swellConfig.strategyAdapter, address(0), "SWELL should not have strategy");

        // Test staked tokens don't have strategies (they are products of strategies)
        ILRTSquared.StrategyConfig memory sethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.sETHFI);
        ILRTSquared.StrategyConfig memory eeigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.eEIGEN);

        assertEq(sethfiConfig.strategyAdapter, address(0), "sETHFI should not have strategy");
        assertEq(eeigenConfig.strategyAdapter, address(0), "eEIGEN should not have strategy");
    }

    function test_TokenTypeConsistencyWithStrategies() public view {
        // Verify native tokens with strategies are classified correctly
        ILRTSquared.TokenInfo memory ethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.ETHFI);
        ILRTSquared.TokenInfo memory eigenInfo = lrtSquared.tokenInfos(DeploymentConstants.EIGEN);
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);

        // Native tokens with strategies should be Native type
        assertEq(
            uint256(ethfiInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "ETHFI with strategy should be Native"
        );
        assertEq(
            uint256(eigenInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "EIGEN with strategy should be Native"
        );
        assertTrue(ethfiConfig.strategyAdapter != address(0), "ETHFI should have strategy");
        assertTrue(eigenConfig.strategyAdapter != address(0), "EIGEN should have strategy");

        // Native tokens without strategies should be Native type
        ILRTSquared.TokenInfo memory wethInfo = lrtSquared.tokenInfos(DeploymentConstants.WETH);
        ILRTSquared.TokenInfo memory swellInfo = lrtSquared.tokenInfos(DeploymentConstants.SWELL);
        ILRTSquared.StrategyConfig memory wethConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.WETH);
        ILRTSquared.StrategyConfig memory swellConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.SWELL);

        assertEq(
            uint256(wethInfo.tokenType), uint256(ILRTSquared.TokenType.Native), "WETH without strategy should be Native"
        );
        assertEq(
            uint256(swellInfo.tokenType),
            uint256(ILRTSquared.TokenType.Native),
            "SWELL without strategy should be Native"
        );
        assertEq(wethConfig.strategyAdapter, address(0), "WETH should not have strategy");
        assertEq(swellConfig.strategyAdapter, address(0), "SWELL should not have strategy");

        // Staked tokens should be Staked type and have no strategies
        ILRTSquared.TokenInfo memory sethfiInfo = lrtSquared.tokenInfos(DeploymentConstants.sETHFI);
        ILRTSquared.TokenInfo memory eeigenInfo = lrtSquared.tokenInfos(DeploymentConstants.eEIGEN);
        ILRTSquared.StrategyConfig memory sethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.sETHFI);
        ILRTSquared.StrategyConfig memory eeigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.eEIGEN);

        assertEq(uint256(sethfiInfo.tokenType), uint256(ILRTSquared.TokenType.Staked), "sETHFI should be Staked");
        assertEq(uint256(eeigenInfo.tokenType), uint256(ILRTSquared.TokenType.Staked), "eEIGEN should be Staked");
        assertEq(sethfiConfig.strategyAdapter, address(0), "sETHFI should not have strategy");
        assertEq(eeigenConfig.strategyAdapter, address(0), "eEIGEN should not have strategy");
    }

    function test_AllRegisteredTokensQuery() public view {
        // Test that allTokens() returns all 6 tokens
        address[] memory allTokens = lrtSquared.allTokens();

        assertEq(allTokens.length, 6, "Should have 6 registered tokens");

        // Check that all expected tokens are in the list
        bool foundEthfi = false;
        bool foundEigen = false;
        bool foundWeth = false;
        bool foundSwell = false;
        bool foundSethfi = false;
        bool foundEeigen = false;

        for (uint256 i = 0; i < allTokens.length; i++) {
            if (allTokens[i] == DeploymentConstants.ETHFI) foundEthfi = true;
            if (allTokens[i] == DeploymentConstants.EIGEN) foundEigen = true;
            if (allTokens[i] == DeploymentConstants.WETH) foundWeth = true;
            if (allTokens[i] == DeploymentConstants.SWELL) foundSwell = true;
            if (allTokens[i] == DeploymentConstants.sETHFI) foundSethfi = true;
            if (allTokens[i] == DeploymentConstants.eEIGEN) foundEeigen = true;
        }

        assertTrue(foundEthfi, "ETHFI should be in allTokens");
        assertTrue(foundEigen, "EIGEN should be in allTokens");
        assertTrue(foundWeth, "WETH should be in allTokens");
        assertTrue(foundSwell, "SWELL should be in allTokens");
        assertTrue(foundSethfi, "sETHFI should be in allTokens");
        assertTrue(foundEeigen, "eEIGEN should be in allTokens");
    }

    function test_TokenRegistrationChecks() public view {
        // Test isTokenRegistered function
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.ETHFI), "ETHFI should be registered");
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.EIGEN), "EIGEN should be registered");
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.WETH), "WETH should be registered");
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.SWELL), "SWELL should be registered");
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.sETHFI), "sETHFI should be registered");
        assertTrue(lrtSquared.isTokenRegistered(DeploymentConstants.eEIGEN), "eEIGEN should be registered");

        // Test unregistered token returns false
        address fakeToken = address(0x1234567890123456789012345678901234567890);
        assertFalse(lrtSquared.isTokenRegistered(fakeToken), "Fake token should not be registered");
    }

    function test_StrategySlippageConfiguration() public view {
        // Test strategy slippage settings are correct
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);

        assertEq(ethfiConfig.maxSlippageInBps, 1, "ETHFI strategy should have 1 bps slippage");
        assertEq(eigenConfig.maxSlippageInBps, 1, "EIGEN strategy should have 1 bps slippage");
    }
}
