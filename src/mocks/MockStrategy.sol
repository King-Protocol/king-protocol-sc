// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "../strategies/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockStrategy
 * @notice A simple mock strategy for testing staked token behavior
 * @dev This contract simulates a real staking strategy but with controllable behavior for tests
 */
contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address private immutable _returnToken;
    address private immutable _nativeToken;
    uint256 private _mockedPrice;
    uint256 private _transferableAmount;

    constructor(address _vault, address _priceProvider, address _returnTokenAddress, address _nativeTokenAddress)
        BaseStrategy(_vault, _priceProvider)
    {
        _returnToken = _returnTokenAddress;
        _nativeToken = _nativeTokenAddress;
        _mockedPrice = 1e18; // Default 1:1 price ratio
        _transferableAmount = type(uint256).max; // Default: all tokens are unlocked
    }

    function _deposit(address nativeToken, uint256 amount, uint256) internal override {
        // Simulate depositing native tokens into the strategy
        IERC20(nativeToken).safeTransferFrom(msg.sender, address(this), amount);

        // Simulate receiving staked tokens back (1:1 ratio for simplicity)
        IERC20(_returnToken).safeTransfer(msg.sender, amount);

        emit DepositToStrategy(nativeToken, amount, _returnToken, amount);
    }

    function returnToken() public view override returns (address) {
        return _returnToken;
    }

    function token() external view returns (address) {
        return _nativeToken;
    }

    function setMockedPrice(uint256 price) external {
        _mockedPrice = price;
    }

    function initiateWithdrawal(uint256) external pure override {
        // Mock withdrawal - nothing happens in test environment
    }

    /**
     * @notice Returns how many staked tokens can be withdrawn right now
     * @param vaultBalance Total staked tokens the vault has
     * @return Amount of tokens that are unlocked and ready to withdraw
     */
    function getTransferableAmount(uint256 vaultBalance) external view returns (uint256) {
        if (_transferableAmount == type(uint256).max) {
            // All tokens are unlocked - return the full balance
            return vaultBalance;
        } else {
            // Some tokens are locked - return the smaller of available vs balance
            return _transferableAmount > vaultBalance ? vaultBalance : _transferableAmount;
        }
    }

    /**
     * @notice Set how many tokens are unlocked (for testing locked token scenarios)
     * @param amount Number of tokens that should be available for withdrawal
     */
    function setTransferableAmount(uint256 amount) external {
        _transferableAmount = amount;
    }
}
