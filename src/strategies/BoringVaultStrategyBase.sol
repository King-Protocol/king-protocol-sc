// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseStrategy} from "./BaseStrategy.sol";
import {ILRTSquared} from "../interfaces/ILRTSquared.sol";

interface ITellerWithMultiAssetSupport {
    function deposit(ERC20 depositAsset, uint256 depositAmount, uint256 minimumMint)
        external
        payable
        returns (uint256 shares);
}

interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }
    
    function updateAtomicRequest(address offer, address want, AtomicRequest calldata atomicRequest) external;
    function getUserAtomicRequest(address user, address offer, address want) external view returns (AtomicRequest memory);
}

/**
 * @title BoringVaultStrategyBase
 * @notice Minimal base contract for Ether.fi atomic withdrawal strategies
 */
abstract contract BoringVaultStrategyBase is BaseStrategy {
    using Math for uint256;
    using SafeERC20 for ERC20;

    uint256 public constant WITHDRAWAL_COOLDOWN = 10 days;

    error ExistingWithdrawalRequestActive();

    event WithdrawalInitiated(uint256 shareAmount, uint256 deadline);
    event WithdrawalCancelled();

    constructor(address _vault, address _priceProvider) BaseStrategy(_vault, _priceProvider) {}

    // Required abstract functions that strategies must implement
    function getBoringVault() public view virtual returns (address);
    function getWithdrawalQueue() public view virtual returns (address);

    function token() public view virtual returns (address);
    function returnToken() external view virtual override returns (address);
    
    // Internal function that can be overridden for delegateCall context
    function _returnToken() internal view virtual returns (address) {
        return this.returnToken();
    }

    /**
     * @notice Initiate atomic withdrawal request
     * @param shareAmount Amount of staked tokens to withdraw
     */
    function initiateWithdrawal(uint256 shareAmount) external virtual override {
        address queue = getWithdrawalQueue();
        require(shareAmount > 0 && shareAmount <= type(uint96).max, "Invalid amount");

        // Get return token address (handles delegateCall context)
        address returnTokenAddr = _returnToken();
        
        // Check for existing withdrawal request
        // In delegateCall context, this will be the vault. In direct calls, it will be the strategy.
        IAtomicQueue.AtomicRequest memory existingRequest = IAtomicQueue(queue).getUserAtomicRequest(
            address(this), 
            returnTokenAddr, 
            token()
        );
        
        // Reject if there's an active withdrawal request
        if (existingRequest.offerAmount > 0) {
            revert ExistingWithdrawalRequestActive();
        }

        // Calculate atomic price with slippage
        uint256 atomicPrice = _calculateAtomicPrice();
        require(atomicPrice <= type(uint88).max, "Price too high");
        
        // Approve queue to take our staked tokens
        ERC20(returnTokenAddr).forceApprove(queue, shareAmount);

        // Create atomic request with proper deadline
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + WITHDRAWAL_COOLDOWN),
            atomicPrice: uint88(atomicPrice),
            offerAmount: uint96(shareAmount),
            inSolve: false
        });

        IAtomicQueue(queue).updateAtomicRequest(returnTokenAddr, token(), request);

        emit WithdrawalInitiated(shareAmount, request.deadline);
    }

    /**
     * @notice Cancel existing withdrawal request
     */
    function cancelWithdrawal() external virtual {
        address queue = getWithdrawalQueue();
        address returnTokenAddr = _returnToken();
        
        // Create a cancellation request with zero offer amount
        IAtomicQueue.AtomicRequest memory cancelRequest = IAtomicQueue.AtomicRequest({
            deadline: 0,
            atomicPrice: 0,
            offerAmount: 0,
            inSolve: false
        });

        IAtomicQueue(queue).updateAtomicRequest(returnTokenAddr, token(), cancelRequest);

        emit WithdrawalCancelled();
    }

    /**
     * @notice Deposit native tokens to receive staked tokens
     */
    function _deposit(address, uint256 amount, uint256 maxSlippageInBps) internal virtual override {
        address boringVault = getBoringVault();
        address nativeToken = token();
        address stakedToken = _returnToken();
        
        // Calculate minimum shares with slippage protection
        uint256 nativeTokenPrice = priceProvider.getPriceInEth(nativeToken);
        uint256 stakedTokenPrice = priceProvider.getPriceInEth(stakedToken);
        uint256 expectedShares = amount.mulDiv(nativeTokenPrice, stakedTokenPrice);
        uint256 minShares = expectedShares.mulDiv(HUNDRED_PERCENT_IN_BPS - maxSlippageInBps, HUNDRED_PERCENT_IN_BPS);

        // Deposit to boring vault
        ERC20(nativeToken).forceApprove(boringVault, amount);
        uint256 sharesReceived = ITellerWithMultiAssetSupport(boringVault).deposit(
            ERC20(nativeToken),
            amount,
            minShares
        );

        // Transfer shares to vault
        ERC20(stakedToken).safeTransfer(vault, sharesReceived);
        emit DepositToStrategy(nativeToken, amount, stakedToken, sharesReceived);
    }

    /**
     * @notice Calculate atomic price for withdrawals
     */
    function _calculateAtomicPrice() internal view virtual returns (uint256) {
        uint256 stakedTokenPrice = priceProvider.getPriceInEth(_returnToken());
        uint256 nativeTokenPrice = priceProvider.getPriceInEth(token());
        
        // Price = native per staked, scaled to 1e18
        uint256 basePrice = nativeTokenPrice.mulDiv(1e18, stakedTokenPrice);
        
        // Apply slippage tolerance
        ILRTSquared.StrategyConfig memory config = ILRTSquared(vault).tokenStrategyConfig(token());
        return basePrice.mulDiv(HUNDRED_PERCENT_IN_BPS - config.maxSlippageInBps, HUNDRED_PERCENT_IN_BPS);
    }
}