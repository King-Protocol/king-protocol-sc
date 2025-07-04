// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {IPriceProvider} from "../../../src/interfaces/IPriceProvider.sol";
import {DeploymentConstants} from "../../../script/staking/fork/DeploymentConstants.sol";
import {StakingIntegrationBase} from "./shared/StakingIntegrationBase.t.sol";

/**
 * @title StrategyDeposits
 * @notice Tests for strategy deposit functionality
 * @dev Tests staking operations from native tokens to staked tokens
 */
contract StrategyDeposits is StakingIntegrationBase {
    using Math for uint256;

    function test_StakeEthfiToStrategy() public {
        uint256 ethfiBalance = IERC20(DeploymentConstants.ETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        vm.assume(ethfiBalance > 1000e18); // Ensure sufficient balance for testing

        address testGovernor = DeploymentConstants.FORK_DEPLOYER;
        vm.startPrank(testGovernor);

        uint256 ethfiToStake = ethfiBalance / 10; // Stake 10%
        uint256 sethfiBefore = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        // Perform staking
        lrtSquared.depositToStrategy(DeploymentConstants.ETHFI, ethfiToStake);

        uint256 sethfiAfter = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 ethfiAfter = IERC20(DeploymentConstants.ETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        // Calculate expected sETHFI amount using price provider
        IPriceProvider priceProvider = IPriceProvider(DeploymentConstants.PRICE_PROVIDER);
        uint256 ethfiPrice = priceProvider.getPriceInEth(DeploymentConstants.ETHFI);
        uint256 sethfiPrice = priceProvider.getPriceInEth(DeploymentConstants.sETHFI);
        uint256 expectedSethfi = ethfiToStake.mulDiv(ethfiPrice, sethfiPrice);

        // Verify staking results
        assertEq(ethfiAfter, ethfiBalance - ethfiToStake, "ETHFI balance should decrease by staked amount");

        uint256 sethfiReceived = sethfiAfter - sethfiBefore;

        // Get configured slippage from strategy config
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        uint256 maxSlippageInBps = ethfiConfig.maxSlippageInBps;
        uint256 minExpectedSethfi = expectedSethfi.mulDiv(10000 - maxSlippageInBps, 10000);

        assertGe(sethfiReceived, minExpectedSethfi, "Should receive at least minimum sETHFI after slippage");
        assertLe(sethfiReceived, expectedSethfi, "Should not receive more than calculated sETHFI amount");

        vm.stopPrank();
    }

    function test_StakeEigenToStrategy() public {
        uint256 eigenBalance = IERC20(DeploymentConstants.EIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        vm.assume(eigenBalance > 1000e18); // Ensure sufficient balance for testing

        address testGovernor = DeploymentConstants.FORK_DEPLOYER;
        vm.startPrank(testGovernor);

        uint256 eigenToStake = eigenBalance / 10; // Stake 10%
        uint256 eeigenBefore = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        // Perform staking
        lrtSquared.depositToStrategy(DeploymentConstants.EIGEN, eigenToStake);

        uint256 eeigenAfter = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 eigenAfter = IERC20(DeploymentConstants.EIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        // Calculate expected eEIGEN amount using price provider
        IPriceProvider priceProvider = IPriceProvider(DeploymentConstants.PRICE_PROVIDER);
        uint256 eigenPrice = priceProvider.getPriceInEth(DeploymentConstants.EIGEN);
        uint256 eeigenPrice = priceProvider.getPriceInEth(DeploymentConstants.eEIGEN);
        uint256 expectedEeigen = eigenToStake.mulDiv(eigenPrice, eeigenPrice);

        // Verify staking results
        assertEq(eigenAfter, eigenBalance - eigenToStake, "EIGEN balance should decrease by staked amount");

        uint256 eeigenReceived = eeigenAfter - eeigenBefore;

        // Get configured slippage from strategy config
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        uint256 maxSlippageInBps = eigenConfig.maxSlippageInBps;
        uint256 minExpectedEeigen = expectedEeigen.mulDiv(10000 - maxSlippageInBps, 10000);

        assertGe(eeigenReceived, minExpectedEeigen, "Should receive at least minimum eEIGEN after slippage");
        assertLe(eeigenReceived, expectedEeigen, "Should not receive more than calculated eEIGEN amount");

        vm.stopPrank();
    }
}
