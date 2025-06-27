// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "../strategies/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStrategyWithEvents is BaseStrategy {
    using SafeERC20 for IERC20;

    event MockWithdrawalInitiated(address indexed caller, uint256 amount);

    address private immutable _returnToken;
    uint256 public lastWithdrawalAmount;
    address public lastWithdrawalCaller;

    constructor(address _vault, address _priceProvider, address _returnTokenAddress)
        BaseStrategy(_vault, _priceProvider)
    {
        _returnToken = _returnTokenAddress;
    }

    function returnToken() public view override returns (address) {
        return _returnToken;
    }

    function initiateWithdrawal(uint256 shareAmount) external override {
        // Track the call for testing
        lastWithdrawalAmount = shareAmount;
        lastWithdrawalCaller = msg.sender;

        // Emit event for testing
        emit MockWithdrawalInitiated(msg.sender, shareAmount);
    }

    function _deposit(address, uint256 amount, uint256) internal override {
        // Mock implementation - just transfer tokens
        IERC20(_returnToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(_returnToken).safeTransfer(vault, amount);
        emit DepositToStrategy(_returnToken, amount, _returnToken, amount);
    }
}
