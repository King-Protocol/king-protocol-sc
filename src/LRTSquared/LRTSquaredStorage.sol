// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {UUPSUpgradeable, Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IPriceProvider} from "src/interfaces/IPriceProvider.sol";
import {IKingVault} from "../interfaces/IKingVault.sol";
import {Governable} from "../governance/Governable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BucketLimiter} from "../libraries/BucketLimiter.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/*
    AVSs pay out rewards to stakers in their ERC20 tokens.
    The LrtSquare contract consolidates AVS rewards into a single ERC20 token 
    It is designed to address the inefficiencies of collecting small, scattered rewards, 
    which can be costly and cumbersome for users. 
    
    LrtSquare enables LRT protocols to deposit AVS rewards, issue share tokens to stakers, 
    and allows users to redeem the underlying assets proportionate to their shares.
    This setup reduces transaction costs and simplifies the reward collection process, 
    benefiting users with smaller stakes who might prefer managing/trading their share tokens directly, 
    while larger holders have the option to redeem and potentially arbitrage.
*/
contract LRTSquaredStorage is
    Initializable,
    Governable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using BucketLimiter for BucketLimiter.Limit;
    using SafeERC20 for IERC20;
    using Math for uint256;

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
     * @dev Maintained for storage layout compatibility - DO NOT USE
     * @dev This struct is deprecated as of vault integration upgrade
     */
    struct StrategyConfig_DEPRECATED {
        address strategyAdapter;
        uint96 maxSlippageInBps;
    }

    uint64 public constant HUNDRED_PERCENT_LIMIT = 1_000_000_000;
    uint64 public constant HUNDRED_PERCENT_IN_BPS = 10000;

    mapping(address => TokenInfo) internal _tokenInfos;
    // only whitelisted depositors can deposit tokens into the vault
    mapping(address => bool) public depositor;
    // address of accepted tokens
    address[] public tokens;
    // address of the price provider
    address public priceProvider;
    // rate limit on deposit amount
    RateLimit internal rateLimit;
    // address of the rebalancer
    address public rebalancer;
    // tokens that are whitelisted as swap output tokens can only be the output of rebalancing
    mapping(address swapOutputTokens => bool isWhitelisted) public isWhitelistedRebalanceOutputToken;
    // max slippage acceptable when we rebalance (in 18 decimals)
    uint256 public maxSlippageForRebalancing;
    // Swapper is a helper contract that helps us swap funds in the vault and rebalance
    address public swapper;
    // Swapper is a helper contract that helps us swap funds in the vault and rebalance
    mapping(address => bool) public pauser;
    // deposit amount for community pause in Eth
    uint256 public depositForCommunityPause;
    // deposited amount after community pause
    uint256 public communityPauseDepositedAmt;
    // fee struct
    Fee public fee;
    /**
     * @notice DEPRECATED: Legacy strategy config mapping
     * @dev Maintained for UUPS storage compatibility - DO NOT USE
     */
    mapping(address token => StrategyConfig_DEPRECATED strategyConfig) public tokenStrategyConfig_DEPRECATED;
    /**
     * @notice DEPRECATED: Legacy max slippage constant
     * @dev Maintained for compatibility - DO NOT USE
     */
    uint256 public constant MAX_SLIPPAGE_FOR_STRATEGY_IN_BPS_DEPRECATED = 100;
    // keccak256("LRTSquared.admin.impl");
    bytes32 constant adminImplPosition = 0x67f3bdb99ec85305417f06f626cf52c7dee7e44607664b5f1cce0af5d822472f;

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
    error SharesCannotBeZero();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice set the implementation for the admin, this needs to be in a base class else we cannot set it
     * @param newImpl address of the implementation
     */
    function setAdminImpl(address newImpl) external onlyGovernor {
        bytes32 position = adminImplPosition;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(position, newImpl)
        }
    }

    function isTokenRegistered(address token) public view returns (bool) {
        return _tokenInfos[token].registered;
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return _tokenInfos[token].whitelisted;
    }

    function allTokens() external view returns (address[] memory) {
        return tokens;
    }

    function tokenInfos(address token) external view returns (TokenInfo memory) {
        return _tokenInfos[token];
    }

    function _getVaultTokenValuesInEth(uint256 vaultTokenShares) internal view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return 0;

        (address[] memory assets, uint256[] memory assetAmounts) = totalAssets();

        uint256 totalValue = getTokenValuesInEth(assets, assetAmounts);
        return (totalValue * vaultTokenShares) / totalSupply;
    }

    /**
     * @notice Get aggregated balances from all enabled vaults
     * @dev Queries each enabled vault, falls back to principal on failure
     * @dev Only includes whitelisted tokens in aggregation
     * @return tokens_ Array of unique token addresses
     * @return quantities Array of total quantities across all vaults
     */
    function getVaultBalances() public view returns (address[] memory tokens_, uint256[] memory quantities) {
        uint256 tokenCount = tokens.length;
        uint256[] memory aggregated = new uint256[](tokenCount);

        // Iterate through all registered vaults
        uint256 vaultCount = vaults.length;
        for (uint256 i = 0; i < vaultCount;) {
            address vault = vaults[i];

            // Only query enabled vaults
            if (isVaultEnabled(vault)) {
                // Try to query vault balances
                try IKingVault(vault).getBalances() returns (
                    address[] memory vaultTokens, uint256[] memory vaultBalances
                ) {
                    // Aggregate balances by token
                    for (uint256 j = 0; j < vaultTokens.length;) {
                        address token = vaultTokens[j];

                        // Find token index in our registry
                        for (uint256 k = 0; k < tokenCount;) {
                            if (tokens[k] == token && isTokenWhitelisted(token)) {
                                aggregated[k] += vaultBalances[j];
                                break;
                            }
                            unchecked {
                                ++k;
                            }
                        }
                        unchecked {
                            ++j;
                        }
                    }
                } catch {
                    // Fallback to principal tracking on query failure
                    for (uint256 j = 0; j < tokenCount;) {
                        address token = tokens[j];
                        if (isTokenWhitelisted(token)) {
                            aggregated[j] += vaultPrincipal[vault][token];
                        }
                        unchecked {
                            ++j;
                        }
                    }
                }
            }
            unchecked {
                ++i;
            }
        }

        return (tokens, aggregated);
    }

    /**
     * @notice Get total assets across main contract and all enabled vaults
     * @dev Optimized to use vault.getBalances() for batch queries (reduces external calls)
     * @dev Reverts if any vault.getBalances() call fails (fail-fast behavior)
     * @return assets Array of registered token addresses
     * @return assetAmounts Array of total amounts for each token (main + all vaults)
     */
    function totalAssets() public view returns (address[] memory assets, uint256[] memory assetAmounts) {
        assets = tokens;
        uint256 tokenCount = assets.length;
        assetAmounts = new uint256[](tokenCount);

        // Get main contract balances for all registered tokens
        for (uint256 i = 0; i < tokenCount;) {
            assetAmounts[i] = IERC20(assets[i]).balanceOf(address(this));
            unchecked {
                ++i;
            }
        }

        // Aggregate balances from all enabled vaults
        uint256 vaultCount = vaults.length;
        for (uint256 j = 0; j < vaultCount;) {
            address vault = vaults[j];

            // Only query enabled vaults
            if (isVaultEnabled(vault)) {
                // Get all balances from vault in single call
                // Will revert if vault call fails (fail-fast behavior)
                (address[] memory vaultTokens, uint256[] memory vaultBalances) = IKingVault(vault).getBalances();

                // Validate array lengths match
                uint256 vaultTokenCount = vaultTokens.length;
                if (vaultTokenCount != vaultBalances.length) {
                    revert ArrayLengthMismatch();
                }

                // Match vault tokens to registered tokens and aggregate
                for (uint256 k = 0; k < vaultTokenCount;) {
                    address vaultToken = vaultTokens[k];

                    // Find matching registered token
                    for (uint256 i = 0; i < tokenCount;) {
                        if (assets[i] == vaultToken) {
                            assetAmounts[i] += vaultBalances[k];
                            break;
                        }
                        unchecked {
                            ++i;
                        }
                    }

                    unchecked {
                        ++k;
                    }
                }
            }

            unchecked {
                ++j;
            }
        }

        return (assets, assetAmounts);
    }

    /**
     * @notice Get detailed breakdown of asset locations (main contract vs vaults)
     * @dev Optimized to use vault.getBalances() for batch queries (reduces external calls)
     * @dev Reverts if any vault.getBalances() call fails (fail-fast behavior)
     * @return tokens_ Array of token addresses
     * @return mainBalances Balances held in main contract
     * @return vaultBalances Balances held in all vaults
     * @return totalBalances Total balances (main + vaults)
     */
    function getAssetBreakdown()
        external
        view
        returns (
            address[] memory tokens_,
            uint256[] memory mainBalances,
            uint256[] memory vaultBalances,
            uint256[] memory totalBalances
        )
    {
        tokens_ = tokens;
        uint256 tokenCount = tokens_.length;

        mainBalances = new uint256[](tokenCount);
        vaultBalances = new uint256[](tokenCount);
        totalBalances = new uint256[](tokenCount);

        // Get main contract balances for all registered tokens
        for (uint256 i = 0; i < tokenCount;) {
            mainBalances[i] = IERC20(tokens_[i]).balanceOf(address(this));
            unchecked {
                ++i;
            }
        }

        // Aggregate balances from all enabled vaults
        uint256 vaultCount = vaults.length;
        for (uint256 j = 0; j < vaultCount;) {
            address vault = vaults[j];

            // Only query enabled vaults
            if (isVaultEnabled(vault)) {
                // Get all balances from vault in single call
                // Will revert if vault call fails (fail-fast behavior)
                (address[] memory vaultTokens, uint256[] memory vaultTokenBalances) = IKingVault(vault).getBalances();

                // Validate array lengths match
                uint256 vaultTokenCount = vaultTokens.length;
                if (vaultTokenCount != vaultTokenBalances.length) {
                    revert ArrayLengthMismatch();
                }

                // Match vault tokens to registered tokens and aggregate
                for (uint256 k = 0; k < vaultTokenCount;) {
                    address vaultToken = vaultTokens[k];

                    // Find matching registered token
                    for (uint256 i = 0; i < tokenCount;) {
                        if (tokens_[i] == vaultToken) {
                            vaultBalances[i] += vaultTokenBalances[k];
                            break;
                        }
                        unchecked {
                            ++i;
                        }
                    }

                    unchecked {
                        ++k;
                    }
                }
            }

            unchecked {
                ++j;
            }
        }

        // Calculate totals
        for (uint256 i = 0; i < tokenCount;) {
            totalBalances[i] = mainBalances[i] + vaultBalances[i];
            unchecked {
                ++i;
            }
        }

        return (tokens_, mainBalances, vaultBalances, totalBalances);
    }

    function getTokenValuesInEth(address[] memory _tokens, uint256[] memory _amounts) public view returns (uint256) {
        uint256 total_eth = 0;
        uint256 len = _tokens.length;

        if (len != _amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < _tokens.length;) {
            if (!isTokenRegistered(_tokens[i])) revert TokenNotRegistered();

            uint256 price = IPriceProvider(priceProvider).getPriceInEth(_tokens[i]);
            if (price == 0) revert PriceProviderFailed();
            total_eth += (_amounts[i] * price) / 10 ** _getDecimals(_tokens[i]);

            unchecked {
                ++i;
            }
        }
        return total_eth;
    }

    function getTokenTotalValuesInEth(address token) public view returns (uint256) {
        uint256 price = IPriceProvider(priceProvider).getPriceInEth(token);
        if (price == 0) revert PriceProviderFailed();

        return (IERC20(token).balanceOf(address(this)) * IPriceProvider(priceProvider).getPriceInEth(token))
            / 10 ** _getDecimals(token);
    }

    function _getDecimals(address erc20) internal view returns (uint8) {
        return IERC20Metadata(erc20).decimals();
    }

    function _verifyPositionLimits() internal view {
        uint256 len = tokens.length;
        uint256 vaultTotalValue = _getVaultTokenValuesInEth(totalSupply());

        if (vaultTotalValue == 0) return;

        for (uint256 i = 0; i < len;) {
            if (_getPositionWeight(tokens[i], vaultTotalValue) > _tokenInfos[tokens[i]].positionWeightLimit) {
                revert TokenWeightLimitBreached();
            }

            unchecked {
                ++i;
            }
        }
    }

    function _getPositionWeight(address token, uint256 vaultTotalValue) internal view returns (uint64) {
        uint256 valueOfTokenInVault = getTokenTotalValuesInEth(token);
        return SafeCast.toUint64((valueOfTokenInVault * HUNDRED_PERCENT_LIMIT) / vaultTotalValue);
    }

    function _withdrawEth(address recipient, uint256 amount) internal {
        (bool success,) = payable(recipient).call{value: amount}("");
        if (!success) revert EtherTransferFailed();
    }

    function _setFee(Fee memory _fee) internal {
        if (
            _fee.treasury == address(0) || _fee.depositFeeInBps > HUNDRED_PERCENT_IN_BPS
                || _fee.redeemFeeInBps > HUNDRED_PERCENT_IN_BPS
        ) revert InvalidValue();

        emit FeeSet(fee, _fee);
        fee = _fee;
    }

    // ============================================
    // VAULT SYSTEM STORAGE
    // ============================================

    /**
     * @notice Information about a registered vault
     * @dev Vaults are never removed from registry (audit trail)
     * @dev Accepted assets are determined by calling vault.assets()
     * @param registered True if vault has been registered
     * @param enabled True if vault is currently enabled for operations
     */
    struct VaultInfo {
        bool registered;
        bool enabled;
    }

    /**
     * @notice Registry of all vaults
     * @dev Array never shrinks (immutable audit trail)
     */
    address[] public vaults;

    /**
     * @notice Detailed information for each vault
     * @dev mapping(vaultAddress => VaultInfo)
     */
    mapping(address => VaultInfo) internal _vaultInfos;

    /**
     * @notice Track principal (deposited assets) in each vault per token
     * @dev mapping(vaultAddress => mapping(tokenAddress => amount))
     * @dev Critical for preventing vault disable when holding assets
     */
    mapping(address => mapping(address => uint256)) public vaultPrincipal;

    // ============================================
    // VAULT EVENTS
    // ============================================

    /**
     * @notice Emitted when a new vault is registered
     * @param vault Address of the registered vault
     * @param acceptedAssets Array of assets this vault accepts
     * @param enabled Initial enabled status
     */
    event VaultRegistered(address indexed vault, address[] acceptedAssets, bool enabled);

    /**
     * @notice Emitted when a vault is enabled
     * @param vault Address of the enabled vault
     */
    event VaultEnabled(address indexed vault);

    /**
     * @notice Emitted when a vault is disabled
     * @param vault Address of the disabled vault
     */
    event VaultDisabled(address indexed vault);

    /**
     * @notice Emitted when assets are deposited to a vault
     * @param vault Address of the vault
     * @param asset Address of the asset deposited
     * @param amount Amount deposited
     * @param shares Vault shares received
     */
    event DepositedToVault(address indexed vault, address indexed asset, uint256 amount, uint256 shares);

    /**
     * @notice Emitted when assets are withdrawn from a vault
     * @param vault Address of the vault
     * @param asset Address of the asset withdrawn
     * @param amount Amount requested
     * @param actualAmount Actual amount received
     */
    event WithdrawnFromVault(address indexed vault, address indexed asset, uint256 amount, uint256 actualAmount);

    /**
     * @notice Emitted when a vault is paused
     * @param vault Address of the paused vault
     */
    event VaultPaused(address indexed vault);

    /**
     * @notice Emitted when a vault is unpaused
     * @param vault Address of the unpaused vault
     */
    event VaultUnpaused(address indexed vault);

    /**
     * @notice Emitted when all vaults are paused
     * @param count Number of vaults paused
     */
    event AllVaultsPaused(uint256 count);

    /**
     * @notice Emitted when emergency withdrawal is performed
     * @param vault Address of the vault
     * @param tokens Array of tokens withdrawn
     * @param amounts Array of amounts withdrawn
     */
    event EmergencyWithdrawal(address indexed vault, address[] tokens, uint256[] amounts);

    // ============================================
    // VAULT ERRORS
    // ============================================

    /**
     * @notice Thrown when vault address is zero
     */
    error VaultCannotBeZeroAddress();

    /**
     * @notice Thrown when vault is already registered
     */
    error VaultAlreadyRegistered();

    /**
     * @notice Thrown when vault is not registered
     */
    error VaultNotRegistered();

    /**
     * @notice Thrown when attempting to disable vault with active principal
     * @param vault Address of the vault
     * @param token Address of the token with principal
     * @param amount Amount of principal that must be withdrawn first
     */
    error VaultHasPrincipal(address vault, address token, uint256 amount);

    /**
     * @notice Thrown when vault is not enabled
     */
    error VaultNotEnabled();

    /**
     * @notice Thrown when asset is not accepted by vault
     * @param vault Address of the vault
     * @param asset Address of the asset
     */
    error AssetNotAcceptedByVault(address vault, address asset);

    /**
     * @notice Thrown when contract has insufficient token balance for operation
     */
    error InsufficientTokenBalance();

    /**
     * @notice Thrown when attempting to withdraw more than tracked principal
     * @param vault Address of the vault
     * @param asset Address of the asset
     * @param principal Current principal balance
     * @param requested Requested withdrawal amount
     */
    error InsufficientPrincipal(address vault, address asset, uint256 principal, uint256 requested);

    /**
     * @notice Thrown when vault does not implement ERC165
     */
    error VaultDoesNotSupportERC165();

    /**
     * @notice Thrown when vault does not support IKingVault interface
     */
    error NotKingVault();

    // ============================================
    // VAULT VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if a vault is registered
     * @param vault Address of the vault to check
     * @return True if vault is registered
     */
    function isVaultRegistered(address vault) public view returns (bool) {
        return _vaultInfos[vault].registered;
    }

    /**
     * @notice Check if a vault is enabled
     * @param vault Address of the vault to check
     * @return True if vault is registered and enabled
     */
    function isVaultEnabled(address vault) public view returns (bool) {
        return _vaultInfos[vault].registered && _vaultInfos[vault].enabled;
    }

    /**
     * @notice Check if a vault accepts a specific asset
     * @dev Queries vault's assets() function dynamically
     * @param vault Address of the vault
     * @param asset Address of the asset
     * @return True if vault's assets() array includes the asset
     */
    function isAssetAcceptedByVault(address vault, address asset) public view returns (bool) {
        // Return false for unregistered vaults
        if (!_vaultInfos[vault].registered) return false;

        // Query vault's assets
        try IKingVault(vault).assets() returns (address[] memory vaultAssets) {
            // Check if asset is in vault's assets array
            for (uint256 i = 0; i < vaultAssets.length;) {
                if (vaultAssets[i] == asset) {
                    return true;
                }
                unchecked {
                    ++i;
                }
            }
            return false;
        } catch {
            // If vault call fails, treat as not accepting the asset
            return false;
        }
    }

    /**
     * @notice Get all registered vaults
     * @return Array of vault addresses
     */
    function allVaults() external view returns (address[] memory) {
        return vaults;
    }

    /**
     * @notice Get vault information
     * @param vault Address of the vault
     * @return registered True if vault is registered
     * @return enabled True if vault is enabled
     */
    function vaultInfo(address vault) external view returns (bool registered, bool enabled) {
        VaultInfo storage info = _vaultInfos[vault];
        return (info.registered, info.enabled);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}
}
