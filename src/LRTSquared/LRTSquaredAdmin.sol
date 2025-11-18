// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    LRTSquaredStorage,
    BucketLimiter,
    Math,
    SafeERC20,
    IERC20,
    IPriceProvider,
    ISwapper
} from "./LRTSquaredStorage.sol";
import {BaseStrategy} from "../strategies/BaseStrategy.sol";
import {IKingVault} from "../interfaces/IKingVault.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract LRTSquaredAdmin is LRTSquaredStorage {
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

    function whitelistRebalacingOutputToken(address _token, bool _shouldWhitelist) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (_shouldWhitelist) {
            if (!isTokenRegistered(_token)) revert TokenNotRegistered();
            if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0) {
                revert PriceProviderNotConfigured();
            }
        }

        isWhitelistedRebalanceOutputToken[_token] = _shouldWhitelist;
        emit WhitelistRebalanceOutputToken(_token, _shouldWhitelist);
    }

    function setFee(Fee memory _fee) external onlyGovernor {
        _setFee(_fee);
    }

    function setTreasuryAddress(address treasury) external onlyGovernor {
        if (treasury == address(0)) revert InvalidValue();
        emit TreasurySet(fee.treasury, treasury);
        fee.treasury = treasury;
    }

    function setSwapper(address _swapper) external onlyGovernor {
        if (_swapper == address(0)) revert InvalidValue();
        emit SwapperSet(swapper, _swapper);
        swapper = _swapper;
    }

    function rebalance(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        bytes calldata _data
    ) external onlyRebalancer {
        if (!isTokenRegistered(_fromAsset) || !isTokenRegistered(_toAsset)) revert TokenNotRegistered();
        // Input token may have been removed from whitelist to pause deposits for that token
        if (!isTokenWhitelisted(_toAsset)) revert TokenNotWhitelisted();
        if (!isWhitelistedRebalanceOutputToken[_toAsset]) revert NotAValidRebalanceOutputToken();

        uint256 vaultTotalValueBefore = _getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountBefore = IERC20(_toAsset).balanceOf(address(this));
        IERC20(_fromAsset).safeTransfer(swapper, _fromAssetAmount);
        uint256 outAmount = ISwapper(swapper).swap(_fromAsset, _toAsset, _fromAssetAmount, _minToAssetAmount, _data);

        uint256 vaultTotalValueAfter = _getVaultTokenValuesInEth(totalSupply());
        uint256 toAssetAmountAfter = IERC20(_toAsset).balanceOf(address(this));

        if (toAssetAmountAfter - toAssetAmountBefore < _minToAssetAmount) {
            revert InsufficientTokensReceivedFromSwapper();
        }
        if (vaultTotalValueAfter < vaultTotalValueBefore) {
            uint256 minVaultTotalValueAfter = (vaultTotalValueBefore * maxSlippageForRebalancing) / 1 ether;
            if (vaultTotalValueAfter < minVaultTotalValueAfter) revert ApplicableSlippageGreaterThanMaxLimit();
        }

        _verifyPositionLimits();

        emit Rebalance(_fromAsset, _toAsset, _fromAssetAmount, outAmount);
    }

    function registerToken(address _token, uint64 _positionWeightLimit) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (isTokenRegistered(_token)) revert TokenAlreadyRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(_token) == 0) {
            revert PriceProviderNotConfigured();
        }
        if (_positionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();

        _tokenInfos[_token] =
            TokenInfo({registered: true, whitelisted: true, positionWeightLimit: _positionWeightLimit});
        tokens.push(_token);

        emit TokenRegistered(_token);
        emit TokenWhitelisted(_token, true);
    }

    function setRebalancer(address account) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        emit RebalancerSet(rebalancer, account);
        rebalancer = account;
    }

    function setPauser(address account, bool isPauser) external onlyGovernor {
        if (account == address(0)) revert InvalidValue();
        if (pauser[account] == isPauser) revert AlreadyInSameState();

        pauser[account] = isPauser;
        emit PauserSet(account, isPauser);
    }

    function setMaxSlippageForRebalancing(uint256 maxSlippage) external onlyRebalancer {
        if (maxSlippage == 0) revert InvalidValue();
        emit MaxSlippageForRebalanceSet(maxSlippageForRebalancing, maxSlippage);
        maxSlippageForRebalancing = maxSlippage;
    }

    function updateWhitelist(address _token, bool _whitelist) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        _tokenInfos[_token].whitelisted = _whitelist;
        emit TokenWhitelisted(_token, _whitelist);
    }

    function updateTokenPositionWeightLimit(address _token, uint64 _TokenPositionWeightLimit) external onlyGovernor {
        if (_token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(_token)) revert TokenNotRegistered();
        if (_TokenPositionWeightLimit > HUNDRED_PERCENT_LIMIT) revert WeightLimitCannotBeGreaterThanHundred();
        emit TokenMaxPositionWeightLimitUpdated(_tokenInfos[_token].positionWeightLimit, _TokenPositionWeightLimit);
        _tokenInfos[_token].positionWeightLimit = _TokenPositionWeightLimit;
    }

    function setDepositors(address[] memory depositors, bool[] memory isDepositor) external onlyGovernor {
        uint256 len = depositors.length;
        if (len != isDepositor.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < len;) {
            if (depositors[i] == address(0)) revert InvalidValue();
            depositor[depositors[i]] = isDepositor[i];

            unchecked {
                ++i;
            }
        }

        emit DepositorsSet(depositors, isDepositor);
    }

    function updatePriceProvider(address _priceProvider) external onlyGovernor {
        if (_priceProvider == address(0)) revert InvalidValue();
        emit PriceProviderSet(priceProvider, _priceProvider);
        priceProvider = _priceProvider;
    }

    function setRateLimitConfig(uint128 __percentageLimit, uint64 __timePeriod, uint128 __refillRate)
        external
        onlyGovernor
    {
        uint256 _totalSupply = totalSupply();
        uint128 capactity = uint128(_totalSupply.mulDiv(__percentageLimit, HUNDRED_PERCENT_LIMIT));
        rateLimit = RateLimit({
            limit: BucketLimiter.create(capactity, __refillRate),
            timePeriod: __timePeriod,
            renewTimestamp: uint64(block.timestamp + __timePeriod),
            percentageLimit: __percentageLimit
        });
    }

    function setRateLimitTimePeriod(uint64 __timePeriod) external onlyGovernor {
        if (__timePeriod == 0) revert InvalidValue();
        emit RateLimitTimePeriodUpdated(rateLimit.timePeriod, __timePeriod);
        rateLimit.timePeriod = __timePeriod;
    }

    function setRefillRatePerSecond(uint64 __refillRate) external onlyGovernor {
        emit RefillRateUpdated(rateLimit.limit.refillRate, __refillRate);
        rateLimit.limit.setRefillRate(__refillRate);
    }

    function setPercentageRateLimit(uint128 __percentageLimit) external onlyGovernor {
        emit PercentageRateLimitUpdated(rateLimit.percentageLimit, __percentageLimit);
        rateLimit.percentageLimit = __percentageLimit;
    }

    function pause() external onlyPauser whenNotPaused {
        _pause();
    }

    function unpause() external onlyPauser whenPaused {
        uint256 amount = communityPauseDepositedAmt;
        if (amount != 0) {
            communityPauseDepositedAmt = 0;
            _withdrawEth(governor(), amount);
            emit CommunityPauseAmountWithdrawal(governor(), amount);
        }

        _unpause();
    }

    function setCommunityPauseDepositAmount(uint256 amount) external onlyGovernor {
        emit CommunityPauseDepositSet(depositForCommunityPause, amount);
        depositForCommunityPause = amount;
    }

    // ============================================
    // VAULT REGISTRATION AND MANAGEMENT
    // ============================================

    /**
     * @notice Register a new vault
     * @dev Can only be called by governor
     * @dev Vaults are NEVER removed from mapping for audit trail
     * @dev Validates vault implements IKingVault via ERC165 and all vault assets are registered in main contract
     * @param _vault Address of the vault to register (must implement IKingVault interface)
     */
    function registerVault(address _vault) external onlyGovernor {
        // Validation
        if (_vault == address(0)) revert VaultCannotBeZeroAddress();

        // Validate vault implements ERC165 and IKingVault interface
        // This prevents malicious contracts from bypassing validation by only implementing assets()
        try IERC165(_vault).supportsInterface(type(IKingVault).interfaceId) returns (bool supported) {
            if (!supported) revert NotKingVault();
        } catch {
            revert VaultDoesNotSupportERC165();
        }

        // Validate vault implements IKingVault interface by calling assets()
        // This will revert if vault doesn't implement the interface correctly
        address[] memory vaultAssets = IKingVault(_vault).assets();
        if (vaultAssets.length == 0) revert InvalidValue();

        // Validate ALL vault assets are registered in main contract
        for (uint256 i = 0; i < vaultAssets.length;) {
            if (!isTokenRegistered(vaultAssets[i])) revert TokenNotRegistered();
            unchecked {
                ++i;
            }
        }

        // If not already registered, add to vaults array
        if (!_vaultInfos[_vault].registered) {
            _vaultInfos[_vault].registered = true;
            vaults.push(_vault);
        }

        // Enable vault by default on registration
        _vaultInfos[_vault].enabled = true;

        emit VaultRegistered(_vault, vaultAssets, true);
    }

    /**
     * @notice Enable a registered vault
     * @dev Can only be called by governor
     * @dev Vault must be registered first
     * @param _vault Address of the vault to enable
     */
    function enableVault(address _vault) external onlyGovernor {
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();

        _vaultInfos[_vault].enabled = true;

        emit VaultEnabled(_vault);
    }

    /**
     * @notice Disable a registered vault
     * @dev Can only be called by governor
     * @dev CRITICAL: Cannot disable vault that holds principal (deposited assets)
     * @dev Must withdraw all assets before disabling
     * @param _vault Address of the vault to disable
     */
    function disableVault(address _vault) external onlyGovernor {
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();

        // CRITICAL SAFETY CHECK: Verify vault has no principal
        // Check all registered tokens
        for (uint256 i = 0; i < tokens.length;) {
            address token = tokens[i];
            uint256 principal = vaultPrincipal[_vault][token];

            if (principal > 0) {
                revert VaultHasPrincipal(_vault, token, principal);
            }

            unchecked {
                ++i;
            }
        }

        _vaultInfos[_vault].enabled = false;

        emit VaultDisabled(_vault);
    }

    /**
     * @notice Deposit assets from main contract into a registered vault
     * @dev Only governor can execute vault operations
     * @param _vault The vault address to deposit into
     * @param _asset The token address to deposit
     * @param _amount The amount to deposit
     * @return shares The vault shares received
     *
     * Requirements:
     * - Vault must be registered and enabled
     * - Asset must be accepted by the vault
     * - Contract must have sufficient token balance
     * - Deposit must not breach position weight limits
     *
     * Effects:
     * - Transfers tokens from contract to vault
     * - Updates vaultPrincipal tracking
     * - Emits DepositedToVault event
     */
    function depositToVault(address _vault, address _asset, uint256 _amount)
        external
        onlyGovernor
        returns (uint256 shares)
    {
        // Validation checks
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();
        if (!isVaultEnabled(_vault)) revert VaultNotEnabled();
        if (!isAssetAcceptedByVault(_vault, _asset)) revert AssetNotAcceptedByVault(_vault, _asset);
        if (_amount == 0) revert AmountCannotBeZero();

        // Check contract has sufficient balance
        uint256 contractBalance = IERC20(_asset).balanceOf(address(this));
        if (contractBalance < _amount) revert InsufficientTokenBalance();

        // Verify position weight limits after deposit
        // This ensures the vault doesn't cause the asset to exceed its weight limit
        _verifyPositionLimits();

        // Approve vault to spend tokens
        IERC20(_asset).safeIncreaseAllowance(_vault, _amount);

        // Execute deposit to external vault
        shares = IKingVault(_vault).deposit(_asset, _amount);

        // Update principal tracking (critical for fund safety)
        vaultPrincipal[_vault][_asset] += _amount;

        emit DepositedToVault(_vault, _asset, _amount, shares);
    }

    /**
     * @notice Withdraw assets from a registered vault back to main contract
     * @dev Only governor can execute vault operations
     * @param _vault The vault address to withdraw from
     * @param _asset The token address to withdraw
     * @param _amount The amount to withdraw
     * @return actualAmount The actual amount received (may differ due to fees/slippage)
     *
     * Requirements:
     * - Vault must be registered
     * - Must have sufficient principal tracked for this vault/asset pair
     * - Receiver is always this contract (funds return to main contract)
     *
     * Effects:
     * - Withdraws tokens from vault to this contract
     * - Updates vaultPrincipal tracking (decreases by amount)
     * - Emits WithdrawnFromVault event
     *
     * Security:
     * - Validates sufficient principal before withdrawal
     * - Updates principal based on requested amount, not actual
     * - Prevents withdrawing more than deposited principal
     */
    function withdrawFromVault(address _vault, address _asset, uint256 _amount)
        external
        onlyGovernor
        returns (uint256 actualAmount)
    {
        // Validation checks
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();
        if (_amount == 0) revert AmountCannotBeZero();

        // Check sufficient principal tracking
        uint256 principal = vaultPrincipal[_vault][_asset];
        if (principal < _amount) revert InsufficientPrincipal(_vault, _asset, principal, _amount);

        // Update principal BEFORE external call (checks-effects-interactions pattern)
        vaultPrincipal[_vault][_asset] = principal - _amount;

        // Execute withdrawal from external vault (receiver is this contract)
        actualAmount = IKingVault(_vault).withdraw(_asset, _amount, address(this));

        emit WithdrawnFromVault(_vault, _asset, _amount, actualAmount);
    }

    // ============================================
    // EMERGENCY CONTROLS
    // ============================================

    /**
     * @notice Pause a specific vault
     * @dev Only governor can pause vaults
     * @dev Calls the vault's pause() function
     * @param _vault Address of the vault to pause
     *
     * Requirements:
     * - Vault must be registered
     * - Vault must implement pause() function
     *
     * Effects:
     * - Calls external vault's pause() function
     * - Emits VaultPaused event
     */
    function pauseVault(address _vault) external onlyGovernor {
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();

        // Call external vault's pause function
        IKingVault(_vault).pause();

        emit VaultPaused(_vault);
    }

    /**
     * @notice Unpause a specific vault
     * @dev Only governor can unpause vaults
     * @dev Calls the vault's unpause() function
     * @param _vault Address of the vault to unpause
     *
     * Requirements:
     * - Vault must be registered
     * - Vault must implement unpause() function
     *
     * Effects:
     * - Calls external vault's unpause() function
     * - Emits VaultUnpaused event
     */
    function unpauseVault(address _vault) external onlyGovernor {
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();

        // Call external vault's unpause function
        IKingVault(_vault).unpause();

        emit VaultUnpaused(_vault);
    }

    /**
     * @notice Pause all registered vaults
     * @dev Emergency function to halt all vault operations
     * @dev Continues on individual vault failures to ensure maximum vaults are paused
     * @dev Only governor can execute
     *
     * Effects:
     * - Attempts to pause each registered vault
     * - Continues even if individual vaults revert
     * - Emits AllVaultsPaused event with count of successfully paused vaults
     *
     * Security:
     * - Does not revert if individual vault pause fails
     * - Ensures maximum protection by pausing as many vaults as possible
     * - Governor-only access
     */
    function pauseAllVaults() external onlyGovernor {
        uint256 vaultCount = vaults.length;
        uint256 successCount = 0;

        for (uint256 i = 0; i < vaultCount;) {
            address vault = vaults[i];

            // Try to pause vault, continue on failure
            try IKingVault(vault).pause() {
                emit VaultPaused(vault);
                successCount++;
            } catch {
                // Continue to next vault on failure
                // Individual vault pause failures don't stop the emergency procedure
            }

            unchecked {
                ++i;
            }
        }

        emit AllVaultsPaused(successCount);
    }

    /**
     * @notice Perform emergency withdrawal from a vault
     * @dev Works even when vault is paused
     * @dev Withdraws ALL assets and resets principal to zero
     * @dev Only governor can execute
     *
     * @param _vault Address of the vault to withdraw from
     *
     * Requirements:
     * - Vault must be registered
     * - Vault must implement emergencyWithdraw() function
     *
     * Effects:
     * - Queries principal for all registered tokens
     * - Calls emergencyWithdraw for each asset with non-zero principal
     * - Resets vaultPrincipal to zero for all assets
     * - Emits EmergencyWithdrawal event
     *
     * Security:
     * - Works even when vault is paused
     * - Resets principal tracking to prevent future issues
     * - Governor-only access
     * - Uses checks-effects-interactions pattern
     */
    function emergencyWithdrawal(address _vault) external onlyGovernor {
        if (!isVaultRegistered(_vault)) revert VaultNotRegistered();

        // Track withdrawn assets for event emission
        address[] memory withdrawnTokens = new address[](tokens.length);
        uint256[] memory withdrawnAmounts = new uint256[](tokens.length);
        uint256 withdrawnCount = 0;

        // Iterate through all registered tokens
        for (uint256 i = 0; i < tokens.length;) {
            address token = tokens[i];
            uint256 principal = vaultPrincipal[_vault][token];

            // Only withdraw if vault has principal for this token
            if (principal > 0) {
                // Reset principal BEFORE external call (checks-effects-interactions)
                vaultPrincipal[_vault][token] = 0;

                // Emergency withdraw from vault
                // Note: Using emergencyWithdraw instead of regular withdraw
                // as it works even when vault is paused
                try IKingVault(_vault).emergencyWithdraw(token, principal, address(this)) returns (
                    uint256 actualAmount
                ) {
                    // Track for event
                    withdrawnTokens[withdrawnCount] = token;
                    withdrawnAmounts[withdrawnCount] = actualAmount;
                    withdrawnCount++;
                } catch {
                    // If emergency withdraw fails, principal is already reset
                    // This is acceptable in emergency scenarios
                    // Track as zero withdrawn
                    withdrawnTokens[withdrawnCount] = token;
                    withdrawnAmounts[withdrawnCount] = 0;
                    withdrawnCount++;
                }
            }

            unchecked {
                ++i;
            }
        }

        // Trim arrays to actual withdrawn count
        address[] memory finalTokens = new address[](withdrawnCount);
        uint256[] memory finalAmounts = new uint256[](withdrawnCount);
        for (uint256 i = 0; i < withdrawnCount;) {
            finalTokens[i] = withdrawnTokens[i];
            finalAmounts[i] = withdrawnAmounts[i];
            unchecked {
                ++i;
            }
        }

        emit EmergencyWithdrawal(_vault, finalTokens, finalAmounts);
    }

    /**
     * @notice DEPRECATED: Legacy strategy config function
     * @dev Maintained for compatibility - DO NOT USE
     */
    function setTokenStrategyConfig(address token, StrategyConfig_DEPRECATED memory strategyConfig) external onlyGovernor {
        if (token == address(0)) revert InvalidValue();
        if (!isTokenRegistered(token)) revert TokenNotRegistered();
        if (IPriceProvider(priceProvider).getPriceInEth(token) == 0) revert PriceProviderNotConfigured();

        if (strategyConfig.strategyAdapter == address(0)) revert StrategyAdapterCannotBeAddressZero_DEPRECATED();
        if (strategyConfig.maxSlippageInBps > MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS_DEPRECATED) {
            revert SlippageCannotBeGreaterThanMaxLimit_DEPRECATED();
        }

        address returnToken = BaseStrategy(strategyConfig.strategyAdapter).returnToken();
        if (returnToken == address(0)) revert StrategyReturnTokenCannotBeAddressZero_DEPRECATED();
        if (!isTokenRegistered(returnToken)) revert StrategyReturnTokenNotRegistered_DEPRECATED();
        if (IPriceProvider(priceProvider).getPriceInEth(returnToken) == 0) {
            revert PriceProviderNotConfiguredForStrategyReturnToken_DEPRECATED();
        }

        tokenStrategyConfig_DEPRECATED[token] = strategyConfig;
        emit StrategyConfigSet_DEPRECATED(token, strategyConfig.strategyAdapter, strategyConfig.maxSlippageInBps);
    }

    /**
     * @notice DEPRECATED: Legacy strategy deposit function
     * @dev Maintained for compatibility - DO NOT USE
     */
    function depositToStrategy(address token, uint256 amount) external onlyGovernor {
        if (amount == type(uint256).max) amount = IERC20(token).balanceOf(address(this));
        if (amount == 0) revert AmountCannotBeZero();

        if (tokenStrategyConfig_DEPRECATED[token].strategyAdapter == address(0)) revert TokenStrategyConfigNotSet_DEPRECATED();
        delegateCall(
            tokenStrategyConfig_DEPRECATED[token].strategyAdapter,
            abi.encodeWithSelector(
                BaseStrategy.deposit.selector, token, amount, tokenStrategyConfig_DEPRECATED[token].maxSlippageInBps
            )
        );

        _verifyPositionLimits();
    }

    function delegateCall(address target, bytes memory data) internal returns (bytes memory result) {
        require(target != address(this), "delegatecall to self");

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            // Perform delegatecall to the target contract
            let success := delegatecall(gas(), target, add(data, 0x20), mload(data), 0, 0)

            // Get the size of the returned data
            let size := returndatasize()

            // Allocate memory for the return data
            result := mload(0x40)

            // Set the length of the return data
            mstore(result, size)

            // Copy the return data to the allocated memory
            returndatacopy(add(result, 0x20), 0, size)

            // Update the free memory pointer
            mstore(0x40, add(result, add(0x20, size)))

            if iszero(success) { revert(result, returndatasize()) }
        }
    }

    modifier onlyRebalancer() {
        _onlyRebalancer();
        _;
    }

    function _onlyRebalancer() internal view {
        if (rebalancer != msg.sender) revert OnlyRebalancer();
    }

    modifier onlyPauser() {
        _onlyPauser();
        _;
    }

    function _onlyPauser() internal view {
        if (!pauser[msg.sender]) revert OnlyPauser();
    }
}
