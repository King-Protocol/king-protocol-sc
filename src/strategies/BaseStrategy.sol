// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPriceProvider} from "../interfaces/IPriceProvider.sol";

abstract contract BaseStrategy {
    uint256 public constant HUNDRED_PERCENT_IN_BPS = 10000;
    address public immutable vault;
    IPriceProvider public immutable priceProvider;

    event DepositToStrategy(address token, uint256 amount, address returnToken, uint256 returnAmount);

    error ReturnLessThanMinReturn();
    error MinReturnCannotBeZero();
    error TokenCannotBeZeroAddress();

    constructor(address _vault, address _priceProvider) {
        require(_vault != address(0), "Vault address cannot be zero");
        require(_priceProvider != address(0), "Price provider address cannot be zero");
        vault = _vault;
        priceProvider = IPriceProvider(_priceProvider);
    }

    function returnToken() public view virtual returns (address);

    function deposit(address token, uint256 amount, uint256 maxSlippageInBps) external sanity(token) {
        _deposit(token, amount, maxSlippageInBps);
    }

    modifier sanity(address token) {
        if (token == address(0)) revert TokenCannotBeZeroAddress();
        _;
    }

    function _deposit(address token, uint256 amount, uint256 maxSlippageInBps) internal virtual;

    function initiateWithdrawal(uint256 shareAmount) external virtual;
}
