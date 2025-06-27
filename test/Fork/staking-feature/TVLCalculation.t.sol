// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILRTSquared} from "../../../src/interfaces/ILRTSquared.sol";
import {IPriceProvider} from "../../../src/interfaces/IPriceProvider.sol";
import {DeploymentConstants} from "../../../script/staking/fork/DeploymentConstants.sol";
import {StakingIntegrationBase} from "./shared/StakingIntegrationBase.t.sol";

/**
 * @title TVLCalculation
 * @notice Tests for Total Value Locked (TVL) calculation functionality
 * @dev Tests TVL calculation with mixed native/staked tokens and proper exclusion of reward tokens
 */
contract TVLCalculation is StakingIntegrationBase {
    using Math for uint256;

    function test_BasicTVLCalculation() public view {
        (uint256 tvlEth, uint256 tvlUsd) = lrtSquared.tvl();

        // Calculate expected TVL using exact token balances and prices
        uint256 expectedTvlEth = _calculateExpectedTVLInEth();

        // Verify actual TVL matches our calculation (allow small rounding tolerance)
        assertApproxEqRel(tvlEth, expectedTvlEth, 1e15, "TVL ETH should match calculated value"); // 0.1% tolerance

        // Verify TVL components are positive
        assertGt(tvlEth, 0, "TVL ETH should be positive");
        assertGt(tvlUsd, 0, "TVL USD should be positive");
    }

    function test_TVLWithMixedTokenPositions() public {
        // Perform staking to create mixed positions
        _stakeToStrategies();

        (uint256 tvlEth, uint256 tvlUsd) = lrtSquared.tvl();

        // Calculate exact expected TVL and component breakdown
        uint256 expectedTvlEth = _calculateExpectedTVLInEth();
        uint256 nativeTokenValueEth = _getTotalNativeTokenValueInEth();
        uint256 stakedTokenValueEth = _getTotalStakedTokenValueInEth();

        // Verify actual TVL matches our exact calculation
        assertApproxEqRel(tvlEth, expectedTvlEth, 1e15, "TVL ETH should match calculated value"); // 0.1% tolerance

        // Verify component breakdown matches total
        assertApproxEqRel(tvlEth, nativeTokenValueEth + stakedTokenValueEth, 1e15, "TVL should equal sum of components");

        // Verify we have mixed token positions
        assertGt(nativeTokenValueEth, 0, "Should have native token value");
        assertGt(stakedTokenValueEth, 0, "Should have staked token value after staking");

        // Verify TVL is positive
        assertGt(tvlEth, 0, "TVL ETH should be positive with mixed positions");
        assertGt(tvlUsd, 0, "TVL USD should be positive with mixed positions");
    }

    function test_TVLExcludesUnregisteredTokens() public {
        // PEPE token address on mainnet
        address PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

        // Record TVL before adding unregistered tokens
        (uint256 tvlEthBefore, uint256 tvlUsdBefore) = lrtSquared.tvl();
        uint256 calculatedTvlEthBefore = _calculateExpectedTVLInEth();

        // Verify our calculation matches before the attack
        assertApproxEqRel(
            tvlEthBefore, calculatedTvlEthBefore, 1e15, "TVL calculation should be accurate before attack"
        );

        // Find a PEPE whale to transfer from
        address pepeWhale = 0x8d54f697caa0A21C9A2C2e4BF7C0F73A63610470; // Known PEPE whale
        uint256 pepeWhaleBalance = IERC20(PEPE).balanceOf(pepeWhale);

        // If whale doesn't have enough, try another known whale
        if (pepeWhaleBalance < 100000000e18) {
            pepeWhale = 0x28C6c06298d514Db089934071355E5743bf21d60; // Binance 14
            pepeWhaleBalance = IERC20(PEPE).balanceOf(pepeWhale);
        }

        // Assume we can find PEPE tokens
        vm.assume(pepeWhaleBalance > 100000000e18); // Need at least 100M PEPE

        // Calculate ~$1M worth of PEPE tokens
        // PEPE has 18 decimals, let's transfer 1 trillion PEPE (~$1M at current prices)
        uint256 pepeAmountToTransfer = 1000000000000e18; // 1 trillion PEPE

        // Ensure we don't transfer more than whale has
        if (pepeAmountToTransfer > pepeWhaleBalance) {
            pepeAmountToTransfer = pepeWhaleBalance / 2; // Use half of whale's balance
        }

        // Verify PEPE is not registered in the vault
        assertFalse(lrtSquared.isTokenRegistered(PEPE), "PEPE should not be registered");

        // Record PEPE balance in vault before attack
        uint256 pepeInVaultBefore = IERC20(PEPE).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);

        // Simulate malicious transfer of PEPE tokens to vault
        vm.prank(pepeWhale);
        IERC20(PEPE).transfer(DeploymentConstants.LRT_SQUARED_PROXY, pepeAmountToTransfer);

        // Verify PEPE tokens were transferred to vault
        uint256 pepeInVaultAfter = IERC20(PEPE).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        assertEq(pepeInVaultAfter, pepeInVaultBefore + pepeAmountToTransfer, "PEPE should be transferred to vault");

        // Record TVL after the malicious transfer
        (uint256 tvlEthAfter, uint256 tvlUsdAfter) = lrtSquared.tvl();
        uint256 calculatedTvlEthAfter = _calculateExpectedTVLInEth();

        // Critical test: TVL should NOT increase despite having unregistered tokens in vault
        assertApproxEqRel(tvlEthAfter, tvlEthBefore, 1e16, "TVL should not increase due to unregistered tokens"); // 1% tolerance
        assertApproxEqRel(tvlUsdAfter, tvlUsdBefore, 1e16, "TVL USD should not increase due to unregistered tokens");

        // Verify our calculation still matches (proving unregistered tokens are excluded)
        assertApproxEqRel(
            tvlEthAfter, calculatedTvlEthAfter, 1e15, "TVL calculation should still be accurate after attack"
        );

        // Verify totalAssets() still only returns registered tokens (not PEPE)
        (address[] memory registeredAssets,) = lrtSquared.totalAssets();
        address[] memory allRegisteredTokens = _getAllRegisteredTokens();
        assertEq(
            registeredAssets.length,
            allRegisteredTokens.length,
            "totalAssets should still return only registered tokens"
        );

        // Verify PEPE is not included in totalAssets despite being in vault
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            assertNotEq(registeredAssets[i], PEPE, "PEPE should not be included in totalAssets");
            assertTrue(lrtSquared.isTokenRegistered(registeredAssets[i]), "Each asset should still be registered");
        }

        // Final verification: The vault has PEPE but TVL ignores it
        assertGt(pepeInVaultAfter, 0, "Vault should contain PEPE tokens");
        assertTrue(pepeInVaultAfter >= pepeAmountToTransfer, "Vault should have the transferred PEPE amount");
    }

    function test_TVLBeforeAndAfterStaking() public {
        // Record initial TVL and calculate expected values
        (uint256 tvlEthBefore, uint256 tvlUsdBefore) = lrtSquared.tvl();
        uint256 expectedTvlEthBefore = _calculateExpectedTVLInEth();

        // Verify our calculation matches before staking
        assertApproxEqRel(tvlEthBefore, expectedTvlEthBefore, 1e15, "TVL calculation should be accurate before staking");

        // Perform staking operations
        _stakeToStrategies();

        // Record TVL after staking and calculate expected values
        (uint256 tvlEthAfter, uint256 tvlUsdAfter) = lrtSquared.tvl();
        uint256 expectedTvlEthAfter = _calculateExpectedTVLInEth();

        // Verify our calculation matches after staking
        assertApproxEqRel(tvlEthAfter, expectedTvlEthAfter, 1e15, "TVL calculation should be accurate after staking");

        // TVL should remain approximately the same after staking (swapping native for staked tokens)
        // Allow small tolerance for price differences between native and staked token prices
        assertApproxEqRel(tvlEthAfter, tvlEthBefore, 2e16, "TVL should remain similar after staking"); // 2% tolerance
        assertApproxEqRel(tvlUsdAfter, tvlUsdBefore, 2e16, "TVL USD should remain similar after staking");

        // Verify token composition changed (should have both native and staked now)
        uint256 nativeValueAfter = _getTotalNativeTokenValueInEth();
        uint256 stakedValueAfter = _getTotalStakedTokenValueInEth();

        // Based on _stakeToStrategies() implementation (stakes 20% of holdings), verify exact amounts
        uint256 expectedNativeAfterStaking = expectedTvlEthBefore * 80 / 100; // Approximately 80% should remain native
        uint256 expectedStakedAfterStaking = expectedTvlEthBefore * 20 / 100; // Approximately 20% should be staked

        assertApproxEqRel(nativeValueAfter, expectedNativeAfterStaking, 1e16, "Should have expected native token value"); // 1% tolerance
        assertApproxEqRel(stakedValueAfter, expectedStakedAfterStaking, 1e16, "Should have expected staked token value"); // 1% tolerance
    }

    function test_TVLAfterRedemption() public {
        _assumeWhaleHasBalance(20e18);

        uint256 redemptionAmount = 20e18;

        // Record initial TVL and calculate expected values
        (uint256 tvlEthBefore, uint256 tvlUsdBefore) = lrtSquared.tvl();
        uint256 expectedTvlEthBefore = _calculateExpectedTVLInEth();
        uint256 totalSupplyBefore = IERC20(DeploymentConstants.LRT_SQUARED_PROXY).totalSupply();

        // Verify our calculation matches before redemption
        assertApproxEqRel(
            tvlEthBefore, expectedTvlEthBefore, 1e15, "TVL calculation should be accurate before redemption"
        );

        // Calculate expected changes accounting for redemption fees
        uint256 redeemFeeInBps = lrtSquared.fee().redeemFeeInBps;
        uint256 feeAmount = (redemptionAmount * redeemFeeInBps) / 10000;
        uint256 netSharesRedeemed = redemptionAmount - feeAmount;
        uint256 sharePercentageRedeemed = netSharesRedeemed.mulDiv(1e18, totalSupplyBefore);

        uint256 expectedTvlEthAfter = tvlEthBefore - tvlEthBefore.mulDiv(sharePercentageRedeemed, 1e18);
        uint256 expectedTvlUsdAfter = tvlUsdBefore - tvlUsdBefore.mulDiv(sharePercentageRedeemed, 1e18);

        vm.startPrank(whale);

        // Perform redemption
        lrtSquared.redeem(redemptionAmount);

        vm.stopPrank();

        // Record TVL after redemption and verify our calculation
        (uint256 tvlEthAfter, uint256 tvlUsdAfter) = lrtSquared.tvl();
        uint256 calculatedTvlEthAfter = _calculateExpectedTVLInEth();

        // Verify our calculation still matches actual TVL
        assertApproxEqRel(
            tvlEthAfter, calculatedTvlEthAfter, 1e15, "TVL calculation should be accurate after redemption"
        );

        // TVL should decrease as expected
        assertLt(tvlEthAfter, tvlEthBefore, "TVL ETH should decrease after redemption");
        assertLt(tvlUsdAfter, tvlUsdBefore, "TVL USD should decrease after redemption");

        // Verify the change matches our expected calculation (with small tolerance for rounding)
        assertApproxEqRel(tvlEthAfter, expectedTvlEthAfter, 1e16, "TVL ETH should decrease by expected amount"); // 1% tolerance
        assertApproxEqRel(tvlUsdAfter, expectedTvlUsdAfter, 1e16, "TVL USD should decrease by expected amount");
    }

    // ===============================================
    // HELPER FUNCTIONS
    // ===============================================

    function _getAllRegisteredTokens() internal view returns (address[] memory) {
        return lrtSquared.allTokens();
    }

    function _getVaultTokenBalancesDynamic()
        internal
        view
        returns (address[] memory tokens, uint256[] memory balances)
    {
        tokens = _getAllRegisteredTokens();
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(DeploymentConstants.LRT_SQUARED_PROXY);
        }
    }

    function _calculateExpectedTVLInEth() internal view returns (uint256 expectedTvlEth) {
        (address[] memory tokens, uint256[] memory balances) = _getVaultTokenBalancesDynamic();
        IPriceProvider priceProvider = IPriceProvider(DeploymentConstants.PRICE_PROVIDER);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (balances[i] > 0) {
                uint256 tokenPriceInEth = priceProvider.getPriceInEth(tokens[i]);
                expectedTvlEth += balances[i].mulDiv(tokenPriceInEth, 1e18);
            }
        }
    }

    function _getTotalNativeTokenValueInEth() internal view returns (uint256 totalValue) {
        (address[] memory tokens, uint256[] memory balances) = _getVaultTokenBalancesDynamic();
        IPriceProvider priceProvider = IPriceProvider(DeploymentConstants.PRICE_PROVIDER);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (balances[i] > 0) {
                ILRTSquared.TokenInfo memory tokenInfo = lrtSquared.tokenInfos(tokens[i]);
                if (tokenInfo.tokenType == ILRTSquared.TokenType.Native) {
                    uint256 tokenPriceInEth = priceProvider.getPriceInEth(tokens[i]);
                    totalValue += balances[i].mulDiv(tokenPriceInEth, 1e18);
                }
            }
        }
    }

    function _getTotalStakedTokenValueInEth() internal view returns (uint256 totalValue) {
        (address[] memory tokens, uint256[] memory balances) = _getVaultTokenBalancesDynamic();
        IPriceProvider priceProvider = IPriceProvider(DeploymentConstants.PRICE_PROVIDER);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (balances[i] > 0) {
                ILRTSquared.TokenInfo memory tokenInfo = lrtSquared.tokenInfos(tokens[i]);
                if (tokenInfo.tokenType == ILRTSquared.TokenType.Staked) {
                    uint256 tokenPriceInEth = priceProvider.getPriceInEth(tokens[i]);
                    totalValue += balances[i].mulDiv(tokenPriceInEth, 1e18);
                }
            }
        }
    }

    function test_TVLByTokenTypeSegregation() public {
        // Test TVL calculation separating native and staked token contributions
        _stakeToStrategies();

        (uint256 totalTvlEth,) = lrtSquared.tvl();
        uint256 nativeValueEth = _getTotalNativeTokenValueInEth();
        uint256 stakedValueEth = _getTotalStakedTokenValueInEth();

        // Total TVL should equal sum of native and staked values
        assertApproxEqRel(totalTvlEth, nativeValueEth + stakedValueEth, 1e15, "TVL should equal native + staked values");

        // Both types should contribute to TVL after staking
        assertGt(nativeValueEth, 0, "Should have native token value in TVL");
        assertGt(stakedValueEth, 0, "Should have staked token value in TVL after staking");
    }

    function test_TVLTokenTypeDistributionAfterStaking() public {
        // Test token type distribution before and after staking
        uint256 nativeValueBefore = _getTotalNativeTokenValueInEth();
        uint256 stakedValueBefore = _getTotalStakedTokenValueInEth();

        // Should start with mostly native tokens
        assertGt(nativeValueBefore, 0, "Should have native tokens before staking");

        // Perform staking
        _stakeToStrategies();

        uint256 nativeValueAfter = _getTotalNativeTokenValueInEth();
        uint256 stakedValueAfter = _getTotalStakedTokenValueInEth();

        // Should now have both native and staked tokens
        assertGt(nativeValueAfter, 0, "Should still have native tokens after staking");
        assertGt(stakedValueAfter, 0, "Should have staked tokens after staking");

        // Native value should decrease, staked value should increase
        assertLt(nativeValueAfter, nativeValueBefore, "Native value should decrease after staking");
        assertGt(stakedValueAfter, stakedValueBefore, "Staked value should increase after staking");
    }
}
