// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BoringVaultStrategyBase, ITellerWithMultiAssetSupport} from "./BoringVaultStrategyBase.sol";

contract SEthFiStrategy is BoringVaultStrategyBase {
    using Math for uint256;
    using SafeERC20 for ERC20;

    ITellerWithMultiAssetSupport public constant S_ETHFI_TELLER =
        ITellerWithMultiAssetSupport(0xe2acf9f80a2756E51D1e53F9f41583C84279Fb1f);
    address public constant WITHDRAWAL_QUEUE = 0xD45884B592E316eB816199615A95C182F75dea07;
    ERC20 public constant S_ETHFI = ERC20(0x86B5780b606940Eb59A062aA85a07959518c0161);
    ERC20 public constant ETHFI = ERC20(0xFe0c30065B384F05761f15d0CC899D4F9F9Cc0eB);

    constructor(address _vault, address _priceProvider) BoringVaultStrategyBase(_vault, _priceProvider) {}

    function _deposit(address, uint256 amount, uint256 maxSlippageInBps) internal override {
        uint256 minReturn =
            sEthFiForEthFi(amount).mulDiv(HUNDRED_PERCENT_IN_BPS - maxSlippageInBps, HUNDRED_PERCENT_IN_BPS);
        if (minReturn == 0) revert MinReturnCannotBeZero();

        uint256 balBefore = S_ETHFI.balanceOf(address(this));

        ETHFI.forceApprove(address(S_ETHFI), amount);
        S_ETHFI_TELLER.deposit(ETHFI, amount, minReturn);

        uint256 balAfter = S_ETHFI.balanceOf(address(this));
        if (balAfter - balBefore < minReturn) revert ReturnLessThanMinReturn();

        emit DepositToStrategy(address(ETHFI), amount, address(S_ETHFI), balAfter - balBefore);
    }

    function sEthFiForEthFi(uint256 amount) internal view returns (uint256) {
        uint256 ethFiPrice = priceProvider.getPriceInEth(address(ETHFI));
        uint256 sEthFiPrice = priceProvider.getPriceInEth(address(S_ETHFI));

        return amount.mulDiv(ethFiPrice, sEthFiPrice);
    }

    function returnToken() public pure override returns (address) {
        return address(S_ETHFI);
    }

    function getWithdrawalQueue() public pure override returns (address) {
        return WITHDRAWAL_QUEUE;
    }

    function getBoringVault() public pure override returns (address) {
        return address(S_ETHFI_TELLER);
    }

    function token() public pure override returns (address) {
        return address(ETHFI);
    }

    function getTransferableAmount(uint256 vaultBalance) public view returns (uint256) {
        if (vaultBalance == 0) return 0;

        try S_ETHFI_TELLER.canTransfer(vault, vaultBalance) returns (bool canTransfer) {
            return canTransfer ? vaultBalance : 0;
        } catch {
            return 0;
        }
    }
}
