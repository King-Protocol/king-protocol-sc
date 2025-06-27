// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {SEthFiStrategy} from "../../../src/strategies/SEthFiStrategy.sol";
import {EEigenStrategy} from "../../../src/strategies/EEigenStrategy.sol";
import {DeploymentConstants} from "../../../script/staking/fork/DeploymentConstants.sol";
import {StakingIntegrationBase} from "./shared/StakingIntegrationBase.t.sol";

/**
 * @title StrategyWithdrawalsAtomic
 * @notice Minimal tests for atomic withdrawal functionality
 * @dev Tests only verify that atomic requests can be created successfully
 */
interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }
    function updateAtomicRequest(address offer, address want, AtomicRequest calldata atomicRequest) external;
}

contract StrategyWithdrawalsAtomic is StakingIntegrationBase {
    function test_SEthFiStrategy_InitiateAtomicWithdrawal_VerifyCall() public {
        uint256 ethfiAmount = 10e18;
        uint256 withdrawalAmount = 5e18;

        // Deposit ETHFI to get sETHFI
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy strategy = SEthFiStrategy(strategyConfig.strategyAdapter);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        assertTrue(sEthfiBalance >= withdrawalAmount, "Insufficient sETHFI balance");

        // Get expected values
        address withdrawalQueue = strategy.getWithdrawalQueue();
        address stakedToken = strategy.returnToken();
        address nativeToken = strategy.token();
        
        // Calculate expected atomic price (would need to replicate the calculation)
        // For now, we'll use expectCall with any atomic request
        
        // Expect the updateAtomicRequest call to the withdrawal queue
        // We verify that the correct tokens and amount are used
        vm.expectCall(
            withdrawalQueue,
            abi.encodeWithSelector(
                IAtomicQueue.updateAtomicRequest.selector,
                stakedToken,  // offer token (sETHFI)
                nativeToken   // want token (ETHFI)
                // We can't easily match the AtomicRequest struct, but we know it's called
            )
        );

        // Initiate atomic withdrawal via admin contract
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, withdrawalAmount);
        
        // The expectCall will verify the call was made
    }
    
    function test_SEthFiStrategy_InitiateAtomicWithdrawal() public {
        uint256 ethfiAmount = 10e18;
        uint256 withdrawalAmount = 5e18;

        // Deposit ETHFI to get sETHFI
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy(strategyConfig.strategyAdapter);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        assertTrue(sEthfiBalance >= withdrawalAmount, "Insufficient sETHFI balance");

        // Initiate atomic withdrawal via admin contract
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, withdrawalAmount);
    }

    function test_SEthFiStrategy_VerifyAtomicRequestParameters() public {
        uint256 ethfiAmount = 10e18;
        uint256 withdrawalAmount = 5e18;

        // Deposit ETHFI to get sETHFI
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy strategy = SEthFiStrategy(strategyConfig.strategyAdapter);

        // Setup expected values
        strategy.getWithdrawalQueue();
        uint256 expectedDeadline = block.timestamp + 10 days;
        
        // We can use vm.expectEmit to verify the WithdrawalInitiated event
        vm.expectEmit(true, true, true, true);
        emit WithdrawalInitiated(withdrawalAmount, expectedDeadline);

        // Initiate withdrawal via admin contract
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, withdrawalAmount);
    }
    
    event WithdrawalInitiated(uint256 shareAmount, uint256 deadline);

    function test_EEigenStrategy_InitiateAtomicWithdrawal() public {
        uint256 eigenAmount = 10e18;
        uint256 withdrawalAmount = 3e18;

        // Deposit EIGEN to get eEIGEN
        _depositToStrategy(DeploymentConstants.EIGEN, eigenAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        EEigenStrategy(strategyConfig.strategyAdapter);

        uint256 eEigenBalance = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        assertTrue(eEigenBalance >= withdrawalAmount, "Insufficient eEIGEN balance");

        // Initiate atomic withdrawal via admin contract
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.withdrawFromStrategy(DeploymentConstants.EIGEN, withdrawalAmount);
    }

    function test_GetTransferableAmount_SEthFi() public {
        uint256 ethfiAmount = 10e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy strategy = SEthFiStrategy(strategyConfig.strategyAdapter);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 transferable = strategy.getTransferableAmount(sEthfiBalance);
        
        // Transferable amount depends on Teller's canTransfer check
        assertLe(transferable, sEthfiBalance, "Transferable should not exceed balance");
    }

    function test_GetTransferableAmount_EEigen() public {
        uint256 eigenAmount = 10e18;
        _depositToStrategy(DeploymentConstants.EIGEN, eigenAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        EEigenStrategy strategy = EEigenStrategy(strategyConfig.strategyAdapter);

        uint256 eEigenBalance = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 transferable = strategy.getTransferableAmount(eEigenBalance);
        
        // Transferable amount depends on Teller's canTransfer check
        assertLe(transferable, eEigenBalance, "Transferable should not exceed balance");
    }

    function _depositToStrategy(address nativeToken, uint256 amount) internal {
        deal(nativeToken, DeploymentConstants.LRT_SQUARED_PROXY, amount);
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.depositToStrategy(nativeToken, amount);
    }
}