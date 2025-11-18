// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title IKingVault
 * @notice Interface for external vault integrations (Veda BoringVault, Concrete TokenizedVault, etc.)
 * @dev This interface standardizes interactions with third-party yield-generating vaults
 * @dev Extends IERC165 for interface detection to prevent malicious contracts from bypassing validation
 */
interface IKingVault is IERC165 {
    /**
     * @notice Deposit assets into the vault
     * @dev Must handle token approvals before calling
     * @param asset The token address to deposit
     * @param amount The amount to deposit
     * @return shares The amount of vault shares received
     */
    function deposit(address asset, uint256 amount) external returns (uint256 shares);

    /**
     * @notice Withdraw assets from the vault
     * @dev Withdraws to the specified receiver address
     * @param asset The token address to withdraw
     * @param amount The amount to withdraw
     * @param receiver The address to receive withdrawn assets
     * @return actualAmount The actual amount withdrawn (may differ due to fees/slippage)
     */
    function withdraw(address asset, uint256 amount, address receiver) external returns (uint256 actualAmount);

    /**
     * @notice Emergency withdrawal when vault is paused
     * @dev Should work even when normal operations are paused
     * @param asset The token address to withdraw
     * @param amount The amount to withdraw
     * @param receiver The address to receive withdrawn assets
     * @return actualAmount The actual amount withdrawn
     */
    function emergencyWithdraw(address asset, uint256 amount, address receiver) external returns (uint256 actualAmount);

    /**
     * @notice Pause vault operations
     * @dev Only callable by authorized pausers
     */
    function pause() external;

    /**
     * @notice Unpause vault operations
     * @dev Only callable by authorized pausers
     */
    function unpause() external;

    /**
     * @notice Check if vault is paused
     * @return True if paused, false otherwise
     */
    function paused() external view returns (bool);

    /**
     * @notice Get total value locked in the vault
     * @return Total value in ETH terms
     */
    function tvl() external view returns (uint256);

    /**
     * @notice Get list of assets supported by the vault
     * @return Array of token addresses
     */
    function assets() external view returns (address[] memory);

    /**
     * @notice Get balances for all supported assets
     * @dev Used for batch TVL aggregation
     * @return tokens Array of token addresses
     * @return balances Array of balances corresponding to tokens
     */
    function getBalances() external view returns (address[] memory tokens, uint256[] memory balances);

    /**
     * @notice Get balance for a specific asset
     * @dev Used for single-asset queries
     * @param asset The token address to query
     * @return The balance of the specified asset
     */
    function getBalance(address asset) external view returns (uint256);
}
