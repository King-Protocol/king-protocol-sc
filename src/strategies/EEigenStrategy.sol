// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BoringVaultStrategyBase, ITellerWithMultiAssetSupport} from "./BoringVaultStrategyBase.sol";

interface ITellerCanTransfer {
    function canTransfer(address from, uint256 amount) external view returns (bool);
}

contract EEigenStrategy is BoringVaultStrategyBase {
    using Math for uint256;
    using SafeERC20 for ERC20;

    ITellerWithMultiAssetSupport public constant E_EIGEN_TELLER =
        ITellerWithMultiAssetSupport(0x63b2B0528376d1B34Ed8c9FF61Bd67ab2C8c2Bb0);
    address public constant WITHDRAWAL_QUEUE = 0xD45884B592E316eB816199615A95C182F75dea07;
    ERC20 public constant E_EIGEN = ERC20(0xE77076518A813616315EaAba6cA8e595E845EeE9);
    ERC20 public constant EIGEN = ERC20(0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83);

    constructor(address _vault, address _priceProvider) BoringVaultStrategyBase(_vault, _priceProvider) {}

    function _deposit(address, uint256 amount, uint256 maxSlippageInBps) internal override {
        uint256 minReturn =
            eEigenForEigen(amount).mulDiv(HUNDRED_PERCENT_IN_BPS - maxSlippageInBps, HUNDRED_PERCENT_IN_BPS);
        if (minReturn == 0) revert MinReturnCannotBeZero();

        uint256 balBefore = E_EIGEN.balanceOf(address(this));

        EIGEN.forceApprove(address(E_EIGEN), amount);
        E_EIGEN_TELLER.deposit(EIGEN, amount, minReturn);

        uint256 balAfter = E_EIGEN.balanceOf(address(this));
        if (balAfter - balBefore < minReturn) revert ReturnLessThanMinReturn();

        emit DepositToStrategy(address(EIGEN), amount, address(E_EIGEN), balAfter - balBefore);
    }

    function eEigenForEigen(uint256 amount) internal view returns (uint256) {
        uint256 eigenPrice = priceProvider.getPriceInEth(address(EIGEN));
        uint256 eEigenPrice = priceProvider.getPriceInEth(address(E_EIGEN));

        return amount.mulDiv(eigenPrice, eEigenPrice);
    }

    function returnToken() external pure override returns (address) {
        return address(E_EIGEN);
    }
    
    function _returnToken() internal pure override returns (address) {
        return address(E_EIGEN);
    }

    function getWithdrawalQueue() public pure override returns (address) {
        return WITHDRAWAL_QUEUE;
    }

    function getBoringVault() public pure override returns (address) {
        return address(E_EIGEN_TELLER);
    }

    function token() public pure override returns (address) {
        return address(EIGEN);
    }

    function getTransferableAmount(uint256 vaultBalance) public view returns (uint256) {
        if (vaultBalance == 0) return 0;

        try ITellerCanTransfer(address(E_EIGEN_TELLER)).canTransfer(vault, vaultBalance) returns (bool canTransfer) {
            return canTransfer ? vaultBalance : 0;
        } catch {
            return 0;
        }
    }
}
