// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BucketLimiter} from "../libraries/BucketLimiter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILRTSquared is IERC20 {
    struct TokenInfo {
        bool registered;
        bool whitelisted;
        uint64 positionWeightLimit;
    }

    struct RateLimit {
        BucketLimiter.Limit limit;
        uint64 timePeriod;
        uint64 renewTimestamp;
        uint128 percentageLimit;
    }

    struct Fee {
        address treasury;
        uint48 depositFeeInBps;
        uint48 redeemFeeInBps;
    }

    /**
     * @notice DEPRECATED: Legacy strategy configuration
     * @dev Maintained for compatibility - DO NOT USE
     */
    struct StrategyConfig_DEPRECATED {
        address strategyAdapter;
        uint96 maxSlippageInBps;
    }

    event TokenRegistered(address token);
    event TokenWhitelisted(address token, bool whitelisted);
    event PriceProviderSet(address oldPriceProvider, address newPriceProvider);
    event DepositorsSet(address[] accounts, bool[] isDepositor);
    event Deposit(
        address indexed sender,
        address indexed recipient,
        uint256 sharesMinted,
        uint256 fee,
        address[] tokens,
        uint256[] amounts
    );
    event Redeem(address indexed account, uint256 sharesRedeemed, uint256 fee, address[] tokens, uint256[] amounts);
    event CommunityPauseDepositSet(uint256 oldAmount, uint256 newAmount);
    event CommunityPause(address indexed pauser);
    event CommunityPauseAmountWithdrawal(address indexed recipient, uint256 amount);
    event RefillRateUpdated(uint128 oldRate, uint128 newRate);
    event PercentageRateLimitUpdated(uint128 oldPercentage, uint128 newPercentage);
    event RateLimitTimePeriodUpdated(uint64 oldTimePeriod, uint64 newTimePeriod);
    event TokenMaxPositionWeightLimitUpdated(uint64 oldLimit, uint64 newLimit);
    event RebalancerSet(address oldRebalancer, address newRebalancer);
    event PauserSet(address pauser, bool isPauser);
    event MaxSlippageForRebalanceSet(uint256 oldMaxSlippage, uint256 newMaxSlippage);
    event WhitelistRebalanceOutputToken(address token, bool whitelisted);
    event SwapperSet(address oldSwapper, address newSwapper);
    event Rebalance(address fromAsset, address toAsset, uint256 fromAssetAmount, uint256 toAssetAmount);
    event FeeSet(Fee oldFee, Fee newFee);
    event TreasurySet(address oldTreasury, address newTreasury);
    /**
     * @notice DEPRECATED: Legacy strategy event
     * @dev No longer emitted - maintained for compatibility only
     */
    event StrategyConfigSet_DEPRECATED(address indexed token, address indexed strategyAdapter, uint96 maxSlippageInBps);

    error TokenAlreadyRegistered();
    error TokenNotWhitelisted();
    error TokenNotRegistered();
    error ArrayLengthMismatch();
    error InvalidValue();
    error InvalidRecipient();
    error VaultTokenValueChanged();
    error InsufficientShares();
    error TotalSupplyZero();
    error OnlyDepositors();
    error PriceProviderNotConfigured();
    error PriceProviderFailed();
    error CommunityPauseDepositNotSet();
    error IncorrectAmountOfEtherSent();
    error EtherTransferFailed();
    error NoCommunityPauseDepositAvailable();
    error RateLimitExceeded();
    error RateLimitRefillRateCannotBeGreaterThanCapacity();
    error WeightLimitCannotBeGreaterThanHundred();
    error TokenWeightLimitBreached();
    error OnlyRebalancer();
    error OnlyPauser();
    error NotAValidRebalanceOutputToken();
    error InsufficientTokensReceivedFromSwapper();
    error ApplicableSlippageGreaterThanMaxLimit();
    error AlreadyInSameState();
    /**
     * @notice DEPRECATED: Legacy strategy errors
     * @dev No longer used - maintained for compatibility only
     */
    error StrategyAdapterCannotBeAddressZero_DEPRECATED();
    error SlippageCannotBeGreaterThanMaxLimit_DEPRECATED();
    error TokenStrategyConfigNotSet_DEPRECATED();
    error StrategyReturnTokenCannotBeAddressZero_DEPRECATED();
    error StrategyReturnTokenNotRegistered_DEPRECATED();
    error PriceProviderNotConfiguredForStrategyReturnToken_DEPRECATED();
    error AmountCannotBeZero();

    function HUNDRED_PERCENT_LIMIT() external pure returns (uint64);
    function HUNDRED_PERCENT_IN_BPS() external pure returns (uint64);
    /**
     * @notice DEPRECATED: Legacy constant
     * @dev Use MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS_DEPRECATED instead
     */
    function MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS() external pure returns (uint256);
    function tokenInfos(address token) external view returns (TokenInfo memory);
    function depositor(address account) external view returns (bool);
    function tokens(uint256 index) external view returns (address);
    function allTokens() external view returns (address[] memory);
    function priceProvider() external view returns (address);
    function rebalancer() external view returns (address);
    function isWhitelistedRebalanceOutputToken(address token) external view returns (bool);
    function maxSlippageForRebalancing() external view returns (uint256);
    function swapper() external view returns (address);
    function pauser(address account) external view returns (bool);
    function depositForCommunityPause() external view returns (uint256);
    function communityPauseDepositedAmt() external view returns (uint256);
    function fee() external view returns (Fee memory);
    /**
     * @notice DEPRECATED: Legacy function
     * @dev Use new vault system instead
     */
    function tokenStrategyConfig(address token) external view returns (StrategyConfig_DEPRECATED memory);
    function getRateLimit() external view returns (RateLimit memory);
    function whitelistRebalacingOutputToken(address _token, bool _shouldWhitelist) external;
    function setFee(Fee memory _fee) external;
    function setTreasuryAddress(address treasury) external;
    function setSwapper(address _swapper) external;
    function rebalance(
        address _fromAsset,
        address _toAsset,
        uint256 _fromAssetAmount,
        uint256 _minToAssetAmount,
        bytes calldata _data
    ) external;
    function registerToken(address _token, uint64 _positionWeightLimit) external;
    function setRebalancer(address account) external;
    function setPauser(address account, bool isPauser) external;
    function setMaxSlippageForRebalancing(uint256 maxSlippage) external;
    function updateWhitelist(address _token, bool _whitelist) external;
    function updateTokenPositionWeightLimit(address _token, uint64 _TokenPositionWeightLimit) external;
    function setDepositors(address[] memory depositors, bool[] memory isDepositor) external;
    function updatePriceProvider(address _priceProvider) external;
    function setRateLimitConfig(uint128 __percentageLimit, uint64 __timePeriod, uint128 __refillRate) external;
    function setRateLimitTimePeriod(uint64 __timePeriod) external;
    function setRefillRatePerSecond(uint64 __refillRate) external;
    function setPercentageRateLimit(uint128 __percentageLimit) external;
    /**
     * @notice DEPRECATED: Legacy strategy function
     * @dev Use new vault system instead
     */
    function setTokenStrategyConfig(address token, StrategyConfig_DEPRECATED memory strategyConfig) external;
    /**
     * @notice DEPRECATED: Legacy strategy function
     * @dev Use new vault system instead
     */
    function depositToStrategy(address token, uint256 amount) external;
    function deposit(address[] memory _tokens, uint256[] memory _amounts, address _receiver) external;
    function redeem(uint256 vaultShares) external;
    function previewDeposit(address[] memory _tokens, uint256[] memory _amounts)
        external
        view
        returns (uint256, uint256);
    function previewRedeem(uint256 vaultShares) external view returns (address[] memory, uint256[] memory, uint256);
    function assetOf(address user, address token) external view returns (uint256);
    function assetsOf(address user) external view returns (address[] memory, uint256[] memory);
    function assetForVaultShares(uint256 vaultShares, address token) external view returns (uint256);
    function assetsForVaultShares(uint256 vaultShare) external view returns (address[] memory, uint256[] memory);
    function totalAssets() external view returns (address[] memory, uint256[] memory);
    function tvl() external view returns (uint256, uint256);
    function isTokenRegistered(address token) external view returns (bool);
    function isTokenWhitelisted(address token) external view returns (bool);
    function getTokenValuesInEth(address[] memory _tokens, uint256[] memory _amounts) external view returns (uint256);
    function getTokenTotalValuesInEth(address token) external view returns (uint256);
    function fairValueOf(uint256 vaultTokenShares) external view returns (uint256, uint256);
    function communityPause() external payable;
    function pause() external;
    function unpause() external;
    function withdrawCommunityDepositedPauseAmount() external;
    function setCommunityPauseDepositAmount(uint256 amount) external;
    function positionWeightLimit() external view returns (address[] memory, uint64[] memory);
    function getPositionWeight(address token) external view returns (uint64);
    function paused() external view returns (bool);
    function governor() external view returns (address);
    function transferGovernance(address _newGovernor) external;

    // ============================================
    // VAULT SYSTEM FUNCTIONS
    // ============================================

    function vaults(uint256 index) external view returns (address);
    function vaultPrincipal(address vault, address token) external view returns (uint256);
    function isVaultRegistered(address vault) external view returns (bool);
    function isVaultEnabled(address vault) external view returns (bool);
    function isAssetAcceptedByVault(address vault, address asset) external view returns (bool);
    function allVaults() external view returns (address[] memory);
    function vaultInfo(address vault) external view returns (bool registered, bool enabled);
    function registerVault(address _vault) external;
    function enableVault(address _vault) external;
    function disableVault(address _vault) external;
    function depositToVault(address _vault, address _asset, uint256 _amount) external returns (uint256 shares);
    function withdrawFromVault(address _vault, address _asset, uint256 _amount) external returns (uint256 actualAmount);
    function pauseVault(address _vault) external;
    function unpauseVault(address _vault) external;
    function pauseAllVaults() external;
    function emergencyWithdrawal(address _vault) external;
    function getVaultBalances() external view returns (address[] memory tokens_, uint256[] memory quantities);
    function getAssetBreakdown()
        external
        view
        returns (
            address[] memory tokens_,
            uint256[] memory mainBalances,
            uint256[] memory vaultBalances,
            uint256[] memory totalBalances
        );

    // Vault events
    event VaultRegistered(address indexed vault, address[] acceptedAssets, bool enabled);
    event VaultEnabled(address indexed vault);
    event VaultDisabled(address indexed vault);
    event DepositedToVault(address indexed vault, address indexed asset, uint256 amount, uint256 shares);
    event WithdrawnFromVault(address indexed vault, address indexed asset, uint256 amount, uint256 actualAmount);
    event VaultPaused(address indexed vault);
    event VaultUnpaused(address indexed vault);
    event AllVaultsPaused(uint256 successCount);
    event EmergencyWithdrawal(address indexed vault, address[] tokens, uint256[] amounts);

    // Vault errors
    error NotKingVault();
    error VaultDoesNotSupportERC165();
    error VaultCannotBeZeroAddress();
    error VaultAlreadyRegistered();
    error VaultNotRegistered();
    error VaultHasPrincipal(address vault, address token, uint256 amount);
    error VaultNotEnabled();
    error AssetNotAcceptedByVault(address vault, address asset);
    error InsufficientTokenBalance();
    error InsufficientPrincipal(address vault, address asset, uint256 principal, uint256 requested);
}
