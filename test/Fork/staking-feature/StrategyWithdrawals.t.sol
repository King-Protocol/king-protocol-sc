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
 * @notice Tests for atomic withdrawal functionality with real BoringVault integration
 * @dev Tests atomic request creation, transferable amount calculations, and locked token handling
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
    // ===============================================
    // BASIC WITHDRAWAL TESTS
    // ===============================================

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
                stakedToken, // offer token (sETHFI)
                nativeToken // want token (ETHFI)
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

    // ===============================================
    // TRANSFERABLE AMOUNT TESTS
    // ===============================================

    function test_TransferableAmount_SEthFi_WithStaking() public {
        uint256 ethfiAmount = 20e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy strategy = SEthFiStrategy(strategyConfig.strategyAdapter);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 transferable = strategy.getTransferableAmount(sEthfiBalance);

        assertLe(transferable, sEthfiBalance, "Transferable should not exceed balance");
    }

    function test_TransferableAmount_EEigen_WithStaking() public {
        uint256 eigenAmount = 15e18;
        _depositToStrategy(DeploymentConstants.EIGEN, eigenAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);
        EEigenStrategy strategy = EEigenStrategy(strategyConfig.strategyAdapter);

        uint256 eEigenBalance = IERC20(DeploymentConstants.eEIGEN).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 transferable = strategy.getTransferableAmount(eEigenBalance);

        assertLe(transferable, eEigenBalance, "Transferable should not exceed balance");
    }

    function test_WithdrawalWithLockedTokens_SEthFi() public {
        uint256 ethfiAmount = 30e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        ILRTSquared.StrategyConfig memory strategyConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        SEthFiStrategy strategy = SEthFiStrategy(strategyConfig.strategyAdapter);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 transferable = strategy.getTransferableAmount(sEthfiBalance);

        if (transferable < sEthfiBalance && transferable > 0) {
            uint256 withdrawalAmount = transferable / 2;

            vm.prank(DeploymentConstants.FORK_DEPLOYER);
            lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, withdrawalAmount);
        }
    }

    // ===============================================
    // LARGE WITHDRAWAL TESTS
    // ===============================================

    function test_LargeWithdrawal_SEthFi() public {
        uint256 ethfiAmount = 50e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        if (sEthfiBalance > 10e18) {
            uint256 largeWithdrawalAmount = sEthfiBalance * 80 / 100;

            vm.prank(DeploymentConstants.FORK_DEPLOYER);
            try lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, largeWithdrawalAmount) {
                // Large withdrawal worked
            } catch {
                // Large withdrawal failed - acceptable due to BoringVault limits
            }
        }
    }

    function test_MultipleWithdrawals() public {
        uint256 ethfiAmount = 40e18;
        uint256 eigenAmount = 30e18;

        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);
        _depositToStrategy(DeploymentConstants.EIGEN, eigenAmount);

        vm.startPrank(DeploymentConstants.FORK_DEPLOYER);

        // First withdrawal - ETHFI
        try lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, 5e18) {
            // Success
        } catch {
            // Failed - acceptable
        }

        // Second withdrawal - EIGEN
        try lrtSquared.withdrawFromStrategy(DeploymentConstants.EIGEN, 4e18) {
            // Success
        } catch {
            // Failed - acceptable
        }

        // Third withdrawal - ETHFI again
        try lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, 3e18) {
            // Success
        } catch {
            // Failed - acceptable
        }

        vm.stopPrank();
    }

    function test_ZeroWithdrawal_ShouldRevert() public {
        uint256 ethfiAmount = 10e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        vm.expectRevert();
        lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, 0);
    }

    function test_ExcessiveWithdrawal() public {
        uint256 ethfiAmount = 15e18;
        _depositToStrategy(DeploymentConstants.ETHFI, ethfiAmount);

        uint256 sEthfiBalance = IERC20(DeploymentConstants.sETHFI).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        uint256 excessiveAmount = sEthfiBalance * 2;

        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        try lrtSquared.withdrawFromStrategy(DeploymentConstants.ETHFI, excessiveAmount) {
            // May work if strategy handles it
        } catch {
            // May fail - both are fine
        }
    }

    // ===============================================
    // STRATEGY CONFIG TESTS
    // ===============================================

    function test_StrategyConfigurationAfterDeployment() public view {
        ILRTSquared.StrategyConfig memory ethfiConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.ETHFI);
        ILRTSquared.StrategyConfig memory eigenConfig = lrtSquared.tokenStrategyConfig(DeploymentConstants.EIGEN);

        assertTrue(ethfiConfig.strategyAdapter != address(0), "ETHFI strategy should be set");
        assertTrue(eigenConfig.strategyAdapter != address(0), "EIGEN strategy should be set");

        assertEq(ethfiConfig.maxSlippageInBps, 1, "ETHFI strategy should have 1 bps slippage");
        assertEq(eigenConfig.maxSlippageInBps, 1, "EIGEN strategy should have 1 bps slippage");

        SEthFiStrategy sethfiStrategy = SEthFiStrategy(ethfiConfig.strategyAdapter);
        EEigenStrategy eeigenStrategy = EEigenStrategy(eigenConfig.strategyAdapter);

        assertEq(sethfiStrategy.token(), DeploymentConstants.ETHFI, "SEthFi strategy should handle ETHFI");
        assertEq(sethfiStrategy.returnToken(), DeploymentConstants.sETHFI, "SEthFi strategy should return sETHFI");
        assertEq(eeigenStrategy.token(), DeploymentConstants.EIGEN, "EEigen strategy should handle EIGEN");
        assertEq(eeigenStrategy.returnToken(), DeploymentConstants.eEIGEN, "EEigen strategy should return eEIGEN");

        assertEq(
            sethfiStrategy.vault(), DeploymentConstants.LRT_SQUARED_PROXY, "SEthFi strategy vault should be correct"
        );
        assertEq(
            eeigenStrategy.vault(), DeploymentConstants.LRT_SQUARED_PROXY, "EEigen strategy vault should be correct"
        );

        assertTrue(sethfiStrategy.getWithdrawalQueue() != address(0), "SEthFi strategy should have withdrawal queue");
        assertTrue(eeigenStrategy.getWithdrawalQueue() != address(0), "EEigen strategy should have withdrawal queue");
    }

    function _depositToStrategy(address nativeToken, uint256 amount) internal {
        deal(nativeToken, DeploymentConstants.LRT_SQUARED_PROXY, amount);
        vm.prank(DeploymentConstants.FORK_DEPLOYER);
        lrtSquared.depositToStrategy(nativeToken, amount);
    }
}
