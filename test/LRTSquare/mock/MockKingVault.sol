// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IKingVault} from "../../../src/interfaces/IKingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title MockKingVault
 * @notice Mock implementation of IKingVault for testing purposes
 * @dev Allows manual control of balances and behavior for comprehensive testing
 * @dev Implements ERC165 for interface detection
 */
contract MockKingVault is IKingVault, Pausable, ERC165 {
    address[] private _tokens;
    uint256[] private _balances;
    bool private _shouldRevert;

    /**
     * @notice Set the balances that getBalances() should return
     * @param tokens Array of token addresses
     * @param balances Array of balances corresponding to tokens
     */
    function setBalances(address[] memory tokens, uint256[] memory balances) external {
        require(tokens.length == balances.length, "Length mismatch");
        _tokens = tokens;
        _balances = balances;
    }

    /**
     * @notice Configure whether getBalances() should revert
     * @param shouldRevert True to make getBalances() revert, false for normal operation
     */
    function setShouldRevert(bool shouldRevert) external {
        _shouldRevert = shouldRevert;
    }

    /**
     * @notice Implements IKingVault.getBalances()
     * @return tokens Array of token addresses held by this vault
     * @return balances Array of balances for each token
     */
    function getBalances() external view override returns (address[] memory tokens, uint256[] memory balances) {
        require(!_shouldRevert, "MockKingVault: Configured to revert");
        return (_tokens, _balances);
    }

    /**
     * @notice Implements IKingVault.deposit()
     * @dev Simple mock implementation that accepts deposits
     */
    function deposit(address asset, uint256 amount) external override whenNotPaused returns (uint256 shares) {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Invalid amount");

        // Transfer tokens from sender
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Return 1:1 shares for simplicity
        shares = amount;
        return shares;
    }

    /**
     * @notice Implements IKingVault.withdraw()
     * @dev Simple mock implementation that processes withdrawals
     */
    function withdraw(address asset, uint256 amount, address receiver)
        external
        override
        whenNotPaused
        returns (uint256 actualAmount)
    {
        require(asset != address(0), "Invalid asset");
        require(amount > 0, "Invalid amount");
        require(receiver != address(0), "Invalid receiver");

        // Transfer tokens to receiver
        uint256 balance = IERC20(asset).balanceOf(address(this));
        actualAmount = amount > balance ? balance : amount;

        if (actualAmount > 0) {
            IERC20(asset).transfer(receiver, actualAmount);
        }

        return actualAmount;
    }

    /**
     * @notice Implements IKingVault.emergencyWithdraw()
     * @dev Emergency withdrawal function
     */
    function emergencyWithdraw(address asset, uint256 amount, address receiver)
        external
        override
        returns (uint256 actualAmount)
    {
        require(asset != address(0), "Invalid asset");
        require(receiver != address(0), "Invalid receiver");

        uint256 balance = IERC20(asset).balanceOf(address(this));
        actualAmount = amount > balance ? balance : amount;

        if (actualAmount > 0) {
            IERC20(asset).transfer(receiver, actualAmount);
        }

        return actualAmount;
    }

    /**
     * @notice Implements IKingVault.assets()
     * @dev Returns array of configured assets
     */
    function assets() external view override returns (address[] memory) {
        return _tokens;
    }

    /**
     * @notice Implements IKingVault.getBalance()
     * @dev Returns balance for a specific asset
     */
    function getBalance(address asset) external view override returns (uint256) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == asset) {
                return _balances[i];
            }
        }
        return 0;
    }

    /**
     * @notice Implements IKingVault.tvl()
     * @dev Returns simple TVL (sum of balances, not accounting for prices)
     */
    function tvl() external view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < _balances.length; i++) {
            total += _balances[i];
        }
        return total;
    }

    /**
     * @notice Pause the vault
     */
    function pause() external override {
        _pause();
    }

    /**
     * @notice Unpause the vault
     */
    function unpause() external override {
        _unpause();
    }

    /**
     * @notice Check if vault is paused
     */
    function paused() public view override(IKingVault, Pausable) returns (bool) {
        return super.paused();
    }

    /**
     * @notice Check if contract supports a given interface
     * @param interfaceId The interface identifier to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IKingVault).interfaceId || super.supportsInterface(interfaceId);
    }
}
