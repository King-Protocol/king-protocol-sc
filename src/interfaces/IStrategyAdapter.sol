// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IStrategyAdapter {
    /**
     * @notice Get how many staked tokens can actually be withdrawn right now
     * @param vaultBalance The total amount of staked tokens we have in the vault
     * @return The amount of tokens that are unlocked and ready to withdraw
     */
    function getTransferableAmount(uint256 vaultBalance) external view returns (uint256);
}
