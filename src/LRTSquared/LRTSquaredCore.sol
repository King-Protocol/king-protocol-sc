// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredStorage, SafeERC20, IERC20, Math, BucketLimiter, IPriceProvider} from "./LRTSquaredStorage.sol";
import {IStrategyAdapter} from "../interfaces/IStrategyAdapter.sol";
import {BaseStrategy} from "../strategies/BaseStrategy.sol";

contract LRTSquaredCore is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

    function getRateLimit() external view returns (RateLimit memory) {
        RateLimit memory _rateLimit = rateLimit;
        _rateLimit.limit.getCurrent();
        return _rateLimit;
    }

    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param _amounts amounts of tokens to deposit
    /// @param _receiver recipient of the minted share token
    function deposit(address[] memory _tokens, uint256[] memory _amounts, address _receiver)
        external
        whenNotPaused
        onlyDepositors
        updateRateLimit
    {
        if (_tokens.length != _amounts.length) revert ArrayLengthMismatch();
        if (_receiver == address(0)) revert InvalidRecipient();

        bool initialDeposit = (totalSupply() == 0);
        uint256 vaultTokenValueBefore = _getVaultTokenValuesInEth(1 * 10 ** decimals());

        (uint256 shareToMint, uint256 depositFee) = previewDeposit(_tokens, _amounts);
        // if initial deposit, set renew timestamp to new timestamp
        if (initialDeposit) rateLimit.renewTimestamp = uint64(block.timestamp + rateLimit.timePeriod);
        // check rate limit
        if (!rateLimit.limit.consume(uint128(shareToMint + depositFee))) revert RateLimitExceeded();
        if (shareToMint == 0) revert SharesCannotBeZero();

        _deposit(_tokens, _amounts, shareToMint, depositFee, _receiver);

        _verifyPositionLimits();

        uint256 vaultTokenValueAfter = _getVaultTokenValuesInEth(1 * 10 ** decimals());

        if (!initialDeposit && vaultTokenValueBefore > vaultTokenValueAfter) revert VaultTokenValueChanged();

        emit Deposit(msg.sender, _receiver, shareToMint, depositFee, _tokens, _amounts);
    }

    /// @notice Redeem the underlying assets proportionate to the share of the caller.
    /// @param vaultShares amount of vault share token to redeem the underlying assets
    function redeem(uint256 vaultShares) external {
        if (vaultShares == 0) revert SharesCannotBeZero();
        if (balanceOf(msg.sender) < vaultShares) revert InsufficientShares();

        (address[] memory assets, uint256[] memory assetAmounts, uint256 feeForRedemption) = previewRedeem(vaultShares);
        if (feeForRedemption != 0) _transfer(msg.sender, fee.treasury, feeForRedemption);
        _burn(msg.sender, vaultShares - feeForRedemption);

        for (uint256 i = 0; i < assets.length; i++) {
            if (assetAmounts[i] > 0) IERC20(assets[i]).safeTransfer(msg.sender, assetAmounts[i]);
        }

        emit Redeem(msg.sender, vaultShares, feeForRedemption, assets, assetAmounts);
    }

    function previewDeposit(address[] memory _tokens, uint256[] memory _amounts)
        public
        view
        returns (uint256, uint256)
    {
        uint256 rewardsValueInEth = getTokenValuesInEth(_tokens, _amounts);
        uint256 shareToMint = _convertToShares(rewardsValueInEth, Math.Rounding.Floor);
        uint256 feeForDeposit = shareToMint.mulDiv(fee.depositFeeInBps, HUNDRED_PERCENT_IN_BPS);

        return (shareToMint - feeForDeposit, feeForDeposit);
    }

    function previewRedeem(uint256 vaultShares) public view returns (address[] memory, uint256[] memory, uint256) {
        // If user wants to redeem 0 shares, return empty arrays
        if (vaultShares == 0) {
            return (new address[](0), new uint256[](0), 0);
        }

        uint256 feeForRedemption = vaultShares.mulDiv(fee.redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        uint256 netVaultShares = vaultShares - feeForRedemption;

        // Calculate how much ETH value the user's shares represent
        uint256 redemptionValueInEth = _getVaultTokenValuesInEth(netVaultShares);

        // Figure out which tokens and amounts to give back to the user
        return _calculateRedemptionDistribution(redemptionValueInEth, feeForRedemption);
    }

    function assetOf(address user, address token) external view returns (uint256) {
        return assetForVaultShares(balanceOf(user), token);
    }

    function assetsOf(address user) external view returns (address[] memory, uint256[] memory) {
        return assetsForVaultShares(balanceOf(user));
    }

    function assetForVaultShares(uint256 vaultShares, address token) public view returns (uint256) {
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        if (totalSupply() == 0) revert TotalSupplyZero();

        return _convertToAssetAmount(token, vaultShares, Math.Rounding.Floor);
    }

    function assetsForVaultShares(uint256 vaultShare) public view returns (address[] memory, uint256[] memory) {
        if (totalSupply() == 0) revert TotalSupplyZero();
        address[] memory assets = tokens;
        uint256 len = assets.length;
        uint256[] memory assetAmounts = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            assetAmounts[i] = assetForVaultShares(vaultShare, assets[i]);

            unchecked {
                ++i;
            }
        }

        return (assets, assetAmounts);
    }

    function tvl() external view returns (uint256, uint256) {
        (address[] memory assets, uint256[] memory assetAmounts) = totalAssets();

        uint256 totalValue = 0;
        for (uint256 i = 0; i < assets.length; i++) {
            totalValue += (assetAmounts[i] * IPriceProvider(priceProvider).getPriceInEth(assets[i]))
                / 10 ** _getDecimals(assets[i]);
        }

        (uint256 ethUsdPrice, uint8 ethUsdDecimals) = IPriceProvider(priceProvider).getEthUsdPrice();
        uint256 totalValueInUsd = totalValue * ethUsdPrice / 10 ** ethUsdDecimals;

        return (totalValue, totalValueInUsd);
    }

    function fairValueOf(uint256 vaultTokenShares) external view returns (uint256, uint256) {
        uint256 valueInEth = _getVaultTokenValuesInEth(vaultTokenShares);
        (uint256 ethUsdPrice, uint8 ethUsdPriceDecimals) = IPriceProvider(priceProvider).getEthUsdPrice();
        if (ethUsdPrice == 0) revert PriceProviderFailed();
        uint256 valueInUsd = valueInEth * ethUsdPrice / 10 ** ethUsdPriceDecimals;

        return (valueInEth, valueInUsd);
    }

    function communityPause() external payable whenNotPaused {
        if (depositForCommunityPause == 0) revert CommunityPauseDepositNotSet();
        if (msg.value != depositForCommunityPause) {
            revert IncorrectAmountOfEtherSent();
        }

        _pause();
        communityPauseDepositedAmt = msg.value;
        emit CommunityPause(msg.sender);
    }

    function withdrawCommunityDepositedPauseAmount() external {
        uint256 amount = communityPauseDepositedAmt;

        if (amount == 0) revert NoCommunityPauseDepositAvailable();
        communityPauseDepositedAmt = 0;
        _withdrawEth(governor(), amount);

        emit CommunityPauseAmountWithdrawal(governor(), amount);
    }

    function positionWeightLimit() public view returns (address[] memory, uint64[] memory) {
        uint256 len = tokens.length;
        uint64[] memory positionWeightLimits = new uint64[](len);
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());

        for (uint256 i = 0; i < len;) {
            positionWeightLimits[i] = _getPositionWeight(tokens[i], vaultTotalValue);
            unchecked {
                ++i;
            }
        }

        return (tokens, positionWeightLimits);
    }

    function getPositionWeight(address token) public view returns (uint64) {
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());
        return _getPositionWeight(token, vaultTotalValue);
    }

    /// @notice Deposit rewards to the contract and mint share tokens to the recipient.
    /// @param _tokens addresses of ERC20 tokens to deposit
    /// @param amounts amounts of tokens to deposit
    /// @param shareToMint amount of share token (= LRT^2 token) to mint
    /// @param depositFee fee to mint to the treasury
    /// @param recipientForMintedShare recipient of the minted share token
    function _deposit(
        address[] memory _tokens,
        uint256[] memory amounts,
        uint256 shareToMint,
        uint256 depositFee,
        address recipientForMintedShare
    ) internal {
        for (uint256 i = 0; i < _tokens.length;) {
            if (!isTokenWhitelisted(_tokens[i])) revert TokenNotWhitelisted();
            IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);

            unchecked {
                ++i;
            }
        }

        if (depositFee != 0) _mint(fee.treasury, depositFee);
        _mint(recipientForMintedShare, shareToMint);
    }

    function _convertToShares(uint256 valueInEth, Math.Rounding rounding) public view virtual returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return valueInEth;

        return valueInEth.mulDiv(_totalSupply, _getVaultTokenValuesInEth(_totalSupply), rounding);
    }

    function _convertToAssetAmount(address assetToken, uint256 vaultShares, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        uint256 bal = IERC20(assetToken).balanceOf(address(this));
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) _totalSupply = 1;
        if (bal == 0) bal = 1;

        return vaultShares.mulDiv(bal, _totalSupply, rounding);
    }

    modifier onlyDepositors() {
        _onlyDepositors();
        _;
    }

    function _onlyDepositors() internal view {
        if (!depositor[msg.sender]) revert OnlyDepositors();
    }

    modifier updateRateLimit() {
        _updateRateLimit();
        _;
    }

    function _updateRateLimit() internal {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return;

        // If total supply = 0, can't mint anything since new rate limit which is a percentage of total supply would be 0
        if (block.timestamp > rateLimit.renewTimestamp) {
            uint128 capactity = uint128(_totalSupply.mulDiv(rateLimit.percentageLimit, HUNDRED_PERCENT_LIMIT));
            rateLimit.limit = BucketLimiter.create(capactity, rateLimit.limit.refillRate);
            rateLimit.renewTimestamp = uint64(block.timestamp + rateLimit.timePeriod);
        }
    }

    // ========================= REDEMPTION LOGIC =========================

    /**
     * @dev Tracks all info about a native token and its paired staked token
     *
     * For example, if we have ETHFI (native) and sETHFI (staked):
     * - token: ETHFI address
     * - totalBalance: 100 ETHFI in vault
     * - availableBalance: 100 ETHFI (all available since native)
     * - value: 50 ETH (if ETHFI price is 0.5 ETH)
     * - availableValue: 50 ETH
     * - stakedToken: sETHFI address
     * - stakedValue: 100 ETH (if we have 100 sETHFI worth 1 ETH each)
     * - stakedAvailableValue: 20 ETH (if only 20 sETHFI are unlocked)
     * - totalValue: 150 ETH (native + staked)
     * - totalAvailableValue: 70 ETH (native + unlocked staked)
     */
    struct AssetInventory {
        address token;
        uint256 totalBalance;
        uint256 availableBalance;
        uint256 value;
        uint256 availableValue;
        // Staked token grouping information for fair distribution
        address stakedToken;
        uint256 stakedValue;
        uint256 stakedAvailableValue;
        uint256 totalValue;
        uint256 totalAvailableValue;
    }

    struct InventoryTotals {
        uint256 totalValue;
        uint256 totalAvailableValue;
    }

    /**
     * @dev Tracks which tokens and amounts will be sent to the user
     *
     * - tokens: Array of token addresses to send
     * - amounts: Array of token amounts to send (matching tokens array)
     * - totalValue: Total ETH value requested by user
     * - totalUnfulfilled: ETH value we still need to distribute
     */
    struct RedemptionDistribution {
        address[] tokens;
        uint256[] amounts;
        uint256 totalValue;
        uint256 totalUnfulfilled;
    }

    function _calculateRedemptionDistribution(uint256 redemptionValueInEth, uint256 feeForRedemption)
        internal
        view
        returns (address[] memory, uint256[] memory, uint256)
    {
        // Step 1: Build a list of all tokens in the vault and their values
        (AssetInventory[] memory assets, InventoryTotals memory totals) = _buildAssetInventory();

        // Step 2: Make sure we have enough unlocked tokens to fulfill the redemption
        if (totals.totalAvailableValue < redemptionValueInEth) {
            revert InsufficientLiquidity();
        }

        // Step 3: Figure out which tokens to give and how much of each
        RedemptionDistribution memory distribution = _calculateRedemptionAmounts(assets, redemptionValueInEth);

        return (distribution.tokens, distribution.amounts, feeForRedemption);
    }

    function _buildAssetInventory() internal view returns (AssetInventory[] memory, InventoryTotals memory) {
        (address[] memory allTokens, uint256[] memory allBalances) = totalAssets();

        // Count how many native tokens we have (staked tokens get grouped with their native pair)
        uint256 nativeCount = 0;
        for (uint256 i = 0; i < allTokens.length;) {
            if (_tokenInfos[allTokens[i]].tokenType == TokenType.Native) {
                nativeCount++;
            }
            unchecked {
                ++i;
            }
        }

        AssetInventory[] memory assets = new AssetInventory[](nativeCount);
        InventoryTotals memory totals = InventoryTotals(0, 0);
        uint256 assetIndex = 0;

        // Build inventory for each native token and find its staked pair if it exists
        for (uint256 i = 0; i < allTokens.length;) {
            address token = allTokens[i];

            if (_tokenInfos[token].tokenType == TokenType.Native) {
                uint256 nativeBalance = allBalances[i];
                uint256 nativeValue = getTokenValueInEth(token, nativeBalance);
                uint256 nativeAvailableValue = nativeValue; // Native tokens are always fully available

                // Look for a staked version of this native token
                address stakedToken = address(0);
                uint256 stakedValue = 0;
                uint256 stakedAvailableValue = 0;

                StrategyConfig memory config = tokenStrategyConfig[token];
                if (config.strategyAdapter != address(0)) {
                    try BaseStrategy(config.strategyAdapter).returnToken() returns (address returnToken) {
                        stakedToken = returnToken;

                        // Find how much of this staked token we have
                        for (uint256 j = 0; j < allTokens.length;) {
                            if (allTokens[j] == stakedToken) {
                                uint256 stakedBalance = allBalances[j];
                                stakedValue = getTokenValueInEth(stakedToken, stakedBalance);
                                // Check how much is actually unlocked and withdrawable
                                uint256 stakedAvailable = _getAvailableStakedTokenAmount(stakedToken, stakedBalance);
                                stakedAvailableValue = getTokenValueInEth(stakedToken, stakedAvailable);
                                break;
                            }
                            unchecked {
                                ++j;
                            }
                        }
                    } catch {
                        // Strategy doesn't have a staked token, continue
                    }
                }

                uint256 totalValue = nativeValue + stakedValue;
                uint256 totalAvailableValue = nativeAvailableValue + stakedAvailableValue;

                assets[assetIndex] = AssetInventory({
                    token: token,
                    totalBalance: nativeBalance,
                    availableBalance: nativeBalance, // Native tokens don't have locks
                    value: nativeValue,
                    availableValue: nativeAvailableValue,
                    stakedToken: stakedToken,
                    stakedValue: stakedValue,
                    stakedAvailableValue: stakedAvailableValue,
                    totalValue: totalValue,
                    totalAvailableValue: totalAvailableValue
                });

                // Add to running totals
                totals.totalValue += totalValue;
                totals.totalAvailableValue += totalAvailableValue;

                assetIndex++;
            }

            unchecked {
                ++i;
            }
        }

        return (assets, totals);
    }

    function _getAvailableStakedTokenAmount(address token, uint256 balance) internal view returns (uint256) {
        if (balance == 0) return 0;

        // Find the strategy that produces this staked token
        address strategy = _findStrategyForStakedToken(token);
        if (strategy == address(0)) return balance;

        return IStrategyAdapter(strategy).getTransferableAmount(balance);
    }

    function _calculateRedemptionAmounts(AssetInventory[] memory assets, uint256 redemptionValueInEth)
        internal
        view
        returns (RedemptionDistribution memory)
    {
        // Initialize distribution with pending values
        RedemptionDistribution memory distribution = _initializeDistribution(redemptionValueInEth);

        // Distribute native tokens first
        distribution = _distributeNativeTokens(assets, distribution);

        // Distribute staked tokens for remaining pending values
        distribution = _distributeStakedTokens(assets, distribution);

        return distribution;
    }

    function _initializeDistribution(uint256 redemptionValueInEth)
        internal
        pure
        returns (RedemptionDistribution memory)
    {
        return RedemptionDistribution({
            tokens: new address[](0),
            amounts: new uint256[](0),
            totalValue: redemptionValueInEth,
            totalUnfulfilled: redemptionValueInEth
        });
    }

    function _distributeNativeTokens(AssetInventory[] memory assets, RedemptionDistribution memory distribution)
        internal
        pure
        returns (RedemptionDistribution memory)
    {
        uint256[] memory nativeUsed = new uint256[](assets.length);
        uint256[] memory targetValues = new uint256[](assets.length);

        // First, calculate each token pair's fair share based on its vault proportion
        uint256 totalValue = 0;
        for (uint256 i = 0; i < assets.length;) {
            totalValue += assets[i].totalValue;
            unchecked {
                ++i;
            }
        }

        // Each token pair gets a proportional target value
        // Example: If ETHFI+sETHFI is 30% of vault, it gets 30% of redemption value
        for (uint256 i = 0; i < assets.length;) {
            if (totalValue > 0) {
                targetValues[i] = distribution.totalValue.mulDiv(assets[i].totalValue, totalValue);
            }
            unchecked {
                ++i;
            }
        }

        // Step 1: Try to fulfill each token pair's target using only native tokens
        uint256 totalShortfall = 0;
        for (uint256 i = 0; i < assets.length;) {
            if (targetValues[i] > 0 && assets[i].availableBalance > 0) {
                uint256 nativeCapacity = assets[i].availableValue;
                if (nativeCapacity >= targetValues[i]) {
                    // We have enough native tokens to meet this target
                    nativeUsed[i] = targetValues[i].mulDiv(assets[i].availableBalance, assets[i].availableValue);
                    distribution.totalUnfulfilled -= targetValues[i];
                } else {
                    // Not enough native tokens - use all we have
                    nativeUsed[i] = assets[i].availableBalance;
                    totalShortfall += targetValues[i] - nativeCapacity;
                    distribution.totalUnfulfilled -= nativeCapacity;
                }
            } else if (targetValues[i] > 0) {
                totalShortfall += targetValues[i];
            }
            unchecked {
                ++i;
            }
        }

        // Step 2: If some token pairs couldn't meet their targets, redistribute using excess native tokens
        if (totalShortfall > 0) {
            // Calculate how much native liquidity is still available
            uint256 totalRemainingNative = 0;
            for (uint256 i = 0; i < assets.length;) {
                if (nativeUsed[i] < assets[i].availableBalance) {
                    uint256 usedValue = nativeUsed[i].mulDiv(assets[i].availableValue, assets[i].availableBalance);
                    totalRemainingNative += assets[i].availableValue - usedValue;
                }
                unchecked {
                    ++i;
                }
            }

            if (totalRemainingNative >= totalShortfall) {
                // Scenario: We have enough native tokens to cover the shortfall
                // Take exactly what we need from tokens with excess
                uint256 crossRebalanceRatio = totalShortfall.mulDiv(1e18, totalRemainingNative);

                for (uint256 i = 0; i < assets.length;) {
                    uint256 remainingNative = assets[i].availableBalance - nativeUsed[i];
                    if (remainingNative > 0) {
                        uint256 remainingValue =
                            remainingNative.mulDiv(assets[i].availableValue, assets[i].availableBalance);
                        uint256 additionalValue = remainingValue.mulDiv(crossRebalanceRatio, 1e18);
                        uint256 additionalNative =
                            additionalValue.mulDiv(assets[i].availableBalance, assets[i].availableValue);
                        nativeUsed[i] += additionalNative;
                    }
                    unchecked {
                        ++i;
                    }
                }

                // All shortfall is now covered by native tokens
                distribution.totalUnfulfilled -= totalShortfall;
            } else if (totalRemainingNative > 0) {
                // Scenario: Not enough native tokens - use all remaining natives
                for (uint256 i = 0; i < assets.length;) {
                    uint256 remainingNative = assets[i].availableBalance - nativeUsed[i];
                    if (remainingNative > 0) {
                        nativeUsed[i] = assets[i].availableBalance;
                        uint256 remainingValue =
                            remainingNative.mulDiv(assets[i].availableValue, assets[i].availableBalance);
                        distribution.totalUnfulfilled -= remainingValue;
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        }

        // Build arrays with the native tokens we're using
        _buildDistributionArrays(assets, distribution, nativeUsed, new uint256[](assets.length));

        return distribution;
    }

    function _distributeStakedTokens(AssetInventory[] memory assets, RedemptionDistribution memory distribution)
        internal
        view
        returns (RedemptionDistribution memory)
    {
        if (distribution.totalUnfulfilled == 0) {
            return distribution; // All value already distributed via native tokens
        }

        uint256[] memory stakedUsed = new uint256[](assets.length);

        // Calculate total available staked token value
        uint256 totalAvailableStaked = 0;
        for (uint256 i = 0; i < assets.length;) {
            totalAvailableStaked += assets[i].stakedAvailableValue;
            unchecked {
                ++i;
            }
        }

        if (totalAvailableStaked > 0) {
            // Distribute the remaining value proportionally based on available staked liquidity
            for (uint256 i = 0; i < assets.length;) {
                if (assets[i].stakedAvailableValue > 0) {
                    // This staked token's share of the remaining distribution
                    uint256 stakedShare =
                        distribution.totalUnfulfilled.mulDiv(assets[i].stakedAvailableValue, totalAvailableStaked);

                    // Convert ETH value to token amount
                    if (assets[i].stakedToken != address(0)) {
                        // Get token decimals and price for conversion
                        uint256 decimals = 10 ** _getDecimals(assets[i].stakedToken);
                        uint256 pricePerToken = IPriceProvider(priceProvider).getPriceInEth(assets[i].stakedToken);
                        // Calculate: tokens = (ETH value * 10^decimals) / price per token
                        stakedUsed[i] = stakedShare.mulDiv(decimals, pricePerToken);
                    }
                }
                unchecked {
                    ++i;
                }
            }
        }

        // Rebuild arrays including staked tokens
        uint256[] memory nativeUsed = new uint256[](assets.length);
        // Extract native amounts from existing distribution
        uint256 nativeIndex = 0;
        for (uint256 i = 0; i < assets.length;) {
            if (nativeIndex < distribution.tokens.length && distribution.tokens[nativeIndex] == assets[i].token) {
                nativeUsed[i] = distribution.amounts[nativeIndex];
                nativeIndex++;
            }
            unchecked {
                ++i;
            }
        }

        _buildDistributionArrays(assets, distribution, nativeUsed, stakedUsed);

        return distribution;
    }

    function _buildDistributionArrays(
        AssetInventory[] memory assets,
        RedemptionDistribution memory distribution,
        uint256[] memory nativeUsed,
        uint256[] memory stakedUsed
    ) internal pure {
        uint256 distributionCount = 0;
        for (uint256 i = 0; i < assets.length;) {
            if (nativeUsed[i] > 0) distributionCount++;
            if (stakedUsed[i] > 0 && assets[i].stakedToken != address(0)) distributionCount++;
            unchecked {
                ++i;
            }
        }

        distribution.tokens = new address[](distributionCount);
        distribution.amounts = new uint256[](distributionCount);
        uint256 index = 0;

        for (uint256 i = 0; i < assets.length;) {
            if (nativeUsed[i] > 0) {
                distribution.tokens[index] = assets[i].token;
                distribution.amounts[index] = nativeUsed[i];
                index++;
            }
            if (stakedUsed[i] > 0 && assets[i].stakedToken != address(0)) {
                distribution.tokens[index] = assets[i].stakedToken;
                distribution.amounts[index] = stakedUsed[i];
                index++;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Falldown to the admin implementation
     * @notice This is a catch all for all functions not declared in core
     */
    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        bytes32 slot = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), sload(slot), 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
