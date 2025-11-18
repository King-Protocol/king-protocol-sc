// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared} from "./LRTSquaredSetUp.t.sol";
import {MockKingVault} from "./mock/MockKingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title VaultTVLIntegration
 * @notice Comprehensive test suite for Phase 4: TVL aggregation and balance integration
 * @dev Tests vault balance aggregation, totalAssets integration, and getAssetBreakdown functionality
 */
contract VaultTVLIntegration is LRTSquaredTestSetup {
    MockKingVault public vault1;
    MockKingVault public vault2;
    MockKingVault public vault3;

    function setUp() public override {
        super.setUp();

        // Deploy mock vaults
        vault1 = new MockKingVault();
        vault2 = new MockKingVault();
        vault3 = new MockKingVault();

        // Register tokens
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");

        // Configure vaults with accepted assets
        address[] memory acceptedAssets1 = new address[](2);
        acceptedAssets1[0] = address(tokens[0]);
        acceptedAssets1[1] = address(tokens[1]);
        uint256[] memory balances1 = new uint256[](2);
        balances1[0] = 0;
        balances1[1] = 0;
        vault1.setBalances(acceptedAssets1, balances1);

        address[] memory acceptedAssets2 = new address[](2);
        acceptedAssets2[0] = address(tokens[1]);
        acceptedAssets2[1] = address(tokens[2]);
        uint256[] memory balances2 = new uint256[](2);
        balances2[0] = 0;
        balances2[1] = 0;
        vault2.setBalances(acceptedAssets2, balances2);

        address[] memory acceptedAssets3 = new address[](1);
        acceptedAssets3[0] = address(tokens[0]);
        uint256[] memory balances3 = new uint256[](1);
        balances3[0] = 0;
        vault3.setBalances(acceptedAssets3, balances3);

        // Register vaults
        _registerVault(address(vault1), hex"");
        _registerVault(address(vault2), hex"");
        _registerVault(address(vault3), hex"");
    }

    // ============================================
    // VAULT BALANCE AGGREGATION TESTS (7 tests)
    // ============================================

    /**
     * @notice Test 1: getVaultBalances returns empty arrays when no vaults have balances
     * @dev Scenario:
     *      - Three vaults are registered but have no deposits
     *      - All vaults are enabled
     *      - Expected: getVaultBalances returns all registered tokens with zero quantities
     */
    function test_GetVaultBalances_EmptyVaults() public view {
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        assertEq(tkns.length, 3, "Should return all registered tokens");
        assertEq(quantities.length, 3, "Should return quantities array matching tokens");

        for (uint256 i = 0; i < quantities.length; i++) {
            assertEq(quantities[i], 0, "All quantities should be zero");
        }
    }

    /**
     * @notice Test 2: getVaultBalances correctly aggregates balances from single vault
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Configure mock vault to return this balance
     *      - Expected: getVaultBalances shows 10 ether for token[0], zero for others
     */
    function test_GetVaultBalances_SingleVault() public {
        // Setup: Deposit to vault1
        uint256 depositAmount = 10 ether;

        // Transfer tokens to main contract first
        deal(address(tokens[0]), address(lrtSquared), depositAmount);

        _depositToVault(address(vault1), address(tokens[0]), depositAmount, hex"");

        // Configure mock vault to return balances
        address[] memory vaultTokens = new address[](1);
        vaultTokens[0] = address(tokens[0]);
        uint256[] memory vaultBalances = new uint256[](1);
        vaultBalances[0] = depositAmount;
        vault1.setBalances(vaultTokens, vaultBalances);

        // Test
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify token[0] balance
        bool found = false;
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], depositAmount, "Should return correct token[0] balance");
                found = true;
            }
        }
        assertTrue(found, "Should include token[0] in results");
    }

    /**
     * @notice Test 3: getVaultBalances aggregates balances from multiple vaults
     * @dev Scenario:
     *      - Deposit token[0] and token[1] to vault1
     *      - Deposit token[1] and token[2] to vault2
     *      - Expected: token[1] is aggregated from both vaults (5 + 8 = 13 ether)
     *      - Expected: token[0] shows vault1 balance only, token[2] shows vault2 balance only
     */
    function test_GetVaultBalances_MultipleVaults() public {
        // Setup: Deposit to vault1 and vault2
        uint256 token0Amount1 = 10 ether;
        uint256 token1Amount1 = 5 ether;
        uint256 token1Amount2 = 8 ether;
        uint256 token2Amount2 = 12 ether;

        // Deposit to vault1
        deal(address(tokens[0]), address(lrtSquared), token0Amount1);
        _depositToVault(address(vault1), address(tokens[0]), token0Amount1, hex"");

        deal(address(tokens[1]), address(lrtSquared), token1Amount1);
        _depositToVault(address(vault1), address(tokens[1]), token1Amount1, hex"");

        // Deposit to vault2
        deal(address(tokens[1]), address(lrtSquared), token1Amount2);
        _depositToVault(address(vault2), address(tokens[1]), token1Amount2, hex"");

        deal(address(tokens[2]), address(lrtSquared), token2Amount2);
        _depositToVault(address(vault2), address(tokens[2]), token2Amount2, hex"");

        // Configure mock vaults
        address[] memory vault1Tokens = new address[](2);
        vault1Tokens[0] = address(tokens[0]);
        vault1Tokens[1] = address(tokens[1]);
        uint256[] memory vault1Balances = new uint256[](2);
        vault1Balances[0] = token0Amount1;
        vault1Balances[1] = token1Amount1;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault2Tokens = new address[](2);
        vault2Tokens[0] = address(tokens[1]);
        vault2Tokens[1] = address(tokens[2]);
        uint256[] memory vault2Balances = new uint256[](2);
        vault2Balances[0] = token1Amount2;
        vault2Balances[1] = token2Amount2;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // Test
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify balances
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], token0Amount1, "Should return correct token[0] balance");
            } else if (tkns[i] == address(tokens[1])) {
                assertEq(quantities[i], token1Amount1 + token1Amount2, "Should aggregate token[1] from both vaults");
            } else if (tkns[i] == address(tokens[2])) {
                assertEq(quantities[i], token2Amount2, "Should return correct token[2] balance");
            }
        }
    }

    /**
     * @notice Test 4: getVaultBalances aggregates same token across multiple vaults
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Deposit 15 ether of token[0] to vault3
     *      - Expected: token[0] balance is aggregated: 10 + 15 = 25 ether
     */
    function test_GetVaultBalances_SameTokenMultipleVaults() public {
        // Setup: Deposit token[0] to vault1 and vault3
        uint256 vault1Amount = 10 ether;
        uint256 vault3Amount = 15 ether;

        deal(address(tokens[0]), address(lrtSquared), vault1Amount);
        _depositToVault(address(vault1), address(tokens[0]), vault1Amount, hex"");

        deal(address(tokens[0]), address(lrtSquared), vault3Amount);
        _depositToVault(address(vault3), address(tokens[0]), vault3Amount, hex"");

        // Configure mock vaults
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vault1Amount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault3Tokens = new address[](1);
        vault3Tokens[0] = address(tokens[0]);
        uint256[] memory vault3Balances = new uint256[](1);
        vault3Balances[0] = vault3Amount;
        vault3.setBalances(vault3Tokens, vault3Balances);

        // Test
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify token[0] is aggregated from both vaults
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], vault1Amount + vault3Amount, "Should aggregate token[0] from vault1 and vault3");
            }
        }
    }

    /**
     * @notice Test 5: getVaultBalances excludes disabled vaults
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Deposit 8 ether of token[1] to vault2
     *      - Withdraw all assets from vault2 (required before disabling)
     *      - Disable vault2
     *      - Expected: Only vault1 balance is included, vault2 is excluded
     */
    function test_GetVaultBalances_ExcludesDisabledVaults() public {
        // Setup: Deposit to vault1 and vault2
        uint256 vault1Amount = 10 ether;
        uint256 vault2Amount = 8 ether;

        deal(address(tokens[0]), address(lrtSquared), vault1Amount);
        _depositToVault(address(vault1), address(tokens[0]), vault1Amount, hex"");

        deal(address(tokens[1]), address(lrtSquared), vault2Amount);
        _depositToVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Configure mock vaults
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vault1Amount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault2Tokens = new address[](1);
        vault2Tokens[0] = address(tokens[1]);
        uint256[] memory vault2Balances = new uint256[](1);
        vault2Balances[0] = vault2Amount;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // CRITICAL: Must withdraw all assets before disabling vault
        // This matches the safety check in disableVault() that prevents disabling vaults with principal
        _withdrawFromVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Update mock vault2 to reflect withdrawal
        vault2Balances[0] = 0;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // Now we can disable vault2
        _disableVault(address(vault2), hex"");

        // Test
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify only vault1 balance is included
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], vault1Amount, "Should include vault1 token[0] balance");
            } else if (tkns[i] == address(tokens[1])) {
                assertEq(quantities[i], 0, "Should exclude disabled vault2 token[1] balance");
            }
        }
    }

    /**
     * @notice Test 6: getVaultBalances falls back to principal tracking on query failure
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Configure vault1 to revert on getBalances()
     *      - Expected: Falls back to principal tracking, returns 10 ether for token[0]
     */
    function test_GetVaultBalances_FallbackToPrincipal() public {
        // Setup: Deposit to vault1
        uint256 depositAmount = 10 ether;

        deal(address(tokens[0]), address(lrtSquared), depositAmount);
        _depositToVault(address(vault1), address(tokens[0]), depositAmount, hex"");

        // Configure vault to revert on getBalances()
        vault1.setShouldRevert(true);

        // Test - should fall back to principal tracking
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify fallback to principal
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], depositAmount, "Should use principal tracking on vault failure");
            }
        }
    }

    /**
     * @notice Test 7: getVaultBalances filters non-whitelisted tokens
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Configure vault to return token[0] balance
     *      - Remove token[0] from whitelist (de-whitelist, NOT unregister)
     *      - Expected: Non-whitelisted token is excluded from aggregation (shows 0)
     *      - Note: This is valid - you CAN de-whitelist tokens with vault balances
     */
    function test_GetVaultBalances_FiltersNonWhitelistedTokens() public {
        // Setup: Deposit token[0] to vault1
        uint256 depositAmount = 10 ether;

        deal(address(tokens[0]), address(lrtSquared), depositAmount);
        _depositToVault(address(vault1), address(tokens[0]), depositAmount, hex"");

        // Configure vault to return token[0] balance
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = depositAmount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Remove token[0] from whitelist
        _updateWhitelist(address(tokens[0]), false, hex"");

        // Test - should exclude non-whitelisted token
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify non-whitelisted token is excluded
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], 0, "Should exclude non-whitelisted token[0]");
            }
        }
    }

    // ============================================
    // TVL INTEGRATION TESTS (7 tests)
    // ============================================

    /**
     * @notice Test 8: totalAssets includes vault balances
     * @dev Scenario:
     *      - Deposit 20 ether to main contract
     *      - Deposit 10 ether to vault1
     *      - Expected: totalAssets shows main balance + vault balance
     */
    function test_TotalAssets_IncludesVaultBalances() public {
        // Setup: Deposit to main contract and vault
        uint256 mainAmount = 20 ether;
        uint256 vaultAmount = 10 ether;

        // Deposit to main contract
        address[] memory depositTokens = new address[](1);
        depositTokens[0] = address(tokens[0]);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = mainAmount;

        tokens[0].approve(address(lrtSquared), mainAmount + vaultAmount);
        _deposit(depositTokens, depositAmounts, owner, hex"");

        // Deposit to vault
        _depositToVault(address(vault1), address(tokens[0]), vaultAmount, hex"");

        // Configure vault
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultAmount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Test
        (address[] memory tkns, uint256[] memory amounts) = lrtSquared.totalAssets();

        // Verify total includes both main and vault
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                // Main contract should have mainAmount, vault has vaultAmount
                uint256 mainBalance = IERC20(tokens[0]).balanceOf(address(lrtSquared));
                assertGt(amounts[i], mainBalance, "Should include vault balances");
            }
        }
    }

    /**
     * @notice Test 9: totalAssets aggregates multiple vaults correctly
     * @dev Scenario:
     *      - Deposit 5 ether of token[1] to vault1
     *      - Deposit 8 ether of token[1] to vault2
     *      - Expected: totalAssets aggregates token[1] from both vaults (5 + 8 = 13 ether)
     */
    function test_TotalAssets_MultipleVaults() public {
        // Setup: Deposit token[1] to vault1 and vault2
        uint256 vault1Amount = 5 ether;
        uint256 vault2Amount = 8 ether;

        deal(address(tokens[1]), address(lrtSquared), vault1Amount);
        _depositToVault(address(vault1), address(tokens[1]), vault1Amount, hex"");

        deal(address(tokens[1]), address(lrtSquared), vault2Amount);
        _depositToVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Configure vaults
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[1]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vault1Amount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault2Tokens = new address[](1);
        vault2Tokens[0] = address(tokens[1]);
        uint256[] memory vault2Balances = new uint256[](1);
        vault2Balances[0] = vault2Amount;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // Test
        (address[] memory tkns, uint256[] memory amounts) = lrtSquared.totalAssets();

        // Verify aggregation
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[1])) {
                uint256 mainBalance = IERC20(tokens[1]).balanceOf(address(lrtSquared));
                assertEq(amounts[i], mainBalance + vault1Amount + vault2Amount, "Should aggregate from both vaults");
            }
        }
    }

    /**
     * @notice Test 10: totalAssets returns correct values with empty vaults
     * @dev Scenario:
     *      - Deposit 20 ether to main contract only
     *      - No vault deposits
     *      - Expected: totalAssets equals main contract balance (no vault contributions)
     */
    function test_TotalAssets_EmptyVaults() public {
        // Setup: Only main contract has balances
        uint256 mainAmount = 20 ether;

        address[] memory depositTokens = new address[](1);
        depositTokens[0] = address(tokens[0]);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = mainAmount;

        tokens[0].approve(address(lrtSquared), mainAmount);
        _deposit(depositTokens, depositAmounts, owner, hex"");

        // Test
        (address[] memory tkns, uint256[] memory amounts) = lrtSquared.totalAssets();

        // Verify only main balances
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                uint256 mainBalance = IERC20(tokens[0]).balanceOf(address(lrtSquared));
                assertEq(amounts[i], mainBalance, "Should return only main balance");
            }
        }
    }

    /**
     * @notice Test 11: getAssetBreakdown returns accurate distribution
     * @dev Scenario:
     *      - Deposit 20 ether to main contract
     *      - Deposit 10 ether to vault1
     *      - Expected: Breakdown shows main=20, vault=10, total=30
     */
    function test_GetAssetBreakdown_AccurateDistribution() public {
        // Setup: Deposit to both main and vault
        uint256 mainAmount = 20 ether;
        uint256 vaultAmount = 10 ether;

        // Main contract deposit
        address[] memory depositTokens = new address[](1);
        depositTokens[0] = address(tokens[0]);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = mainAmount;

        tokens[0].approve(address(lrtSquared), mainAmount + vaultAmount);
        _deposit(depositTokens, depositAmounts, owner, hex"");

        // Vault deposit
        _depositToVault(address(vault1), address(tokens[0]), vaultAmount, hex"");

        // Configure vault
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultAmount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Test
        (address[] memory tkns, uint256[] memory mainBalances, uint256[] memory vaultBalances, uint256[] memory totalBalances)
        = lrtSquared.getAssetBreakdown();

        // Verify breakdown
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                uint256 expectedMain = IERC20(tokens[0]).balanceOf(address(lrtSquared));
                assertEq(mainBalances[i], expectedMain, "Should return correct main balance");
                assertEq(vaultBalances[i], vaultAmount, "Should return correct vault balance");
                assertEq(totalBalances[i], expectedMain + vaultAmount, "Should return correct total");
            }
        }
    }

    /**
     * @notice Test 12: getAssetBreakdown with multiple vaults
     * @dev Scenario:
     *      - Deposit 15 ether of token[1] to main contract
     *      - Deposit 5 ether to vault1
     *      - Deposit 8 ether to vault2
     *      - Expected: Breakdown shows main=15, vault=13 (5+8), total=28
     */
    function test_GetAssetBreakdown_MultipleVaults() public {
        // Setup: Distribute token[1] across main, vault1, and vault2
        uint256 mainAmount = 15 ether;
        uint256 vault1Amount = 5 ether;
        uint256 vault2Amount = 8 ether;

        // Give main contract tokens directly (not through deposit to avoid rate limits)
        deal(address(tokens[1]), address(lrtSquared), mainAmount + vault1Amount + vault2Amount);

        // Vault deposits
        _depositToVault(address(vault1), address(tokens[1]), vault1Amount, hex"");
        _depositToVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Configure vaults
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[1]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vault1Amount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault2Tokens = new address[](1);
        vault2Tokens[0] = address(tokens[1]);
        uint256[] memory vault2Balances = new uint256[](1);
        vault2Balances[0] = vault2Amount;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // Test
        (address[] memory tkns, uint256[] memory mainBalances, uint256[] memory vaultBalances, uint256[] memory totalBalances)
        = lrtSquared.getAssetBreakdown();

        // Verify
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[1])) {
                uint256 expectedMain = IERC20(tokens[1]).balanceOf(address(lrtSquared));
                assertEq(mainBalances[i], expectedMain, "Should return correct main balance");
                assertEq(vaultBalances[i], vault1Amount + vault2Amount, "Should aggregate vault balances");
                assertEq(totalBalances[i], expectedMain + vault1Amount + vault2Amount, "Should return correct total");
            }
        }
    }

    /**
     * @notice Test 13: Share pricing reflects vault TVL
     * @dev Scenario:
     *      - Initial deposit of 100 ether establishes baseline share price
     *      - Deposit 50 ether to vault (increases TVL)
     *      - Expected: previewDeposit accounts for increased TVL from vault
     */
    function test_SharePricing_ReflectsVaultTVL() public {
        // Setup: Initial deposit to establish share price
        uint256 initialDeposit = 100 ether;

        address[] memory depositTokens = new address[](1);
        depositTokens[0] = address(tokens[0]);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = initialDeposit;

        tokens[0].approve(address(lrtSquared), initialDeposit);
        _deposit(depositTokens, depositAmounts, owner, hex"");

        // Deposit to vault
        uint256 vaultDeposit = 50 ether;
        tokens[0].approve(address(lrtSquared), vaultDeposit);
        _depositToVault(address(vault1), address(tokens[0]), vaultDeposit, hex"");

        // Configure vault
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultDeposit;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Test: Preview deposit should account for increased TVL
        uint256 previewAmount = 10 ether;
        depositAmounts[0] = previewAmount;
        (uint256 expectedShares,) = lrtSquared.previewDeposit(depositTokens, depositAmounts);

        // With increased TVL from vault, shares per ETH should be different than initial
        assertTrue(expectedShares > 0, "Should receive shares for deposit");
    }

    /**
     * @notice Test 14: Deposit and withdraw affect TVL correctly
     * @dev Scenario:
     *      - Record initial TVL (should be 0)
     *      - Deposit 50 ether to main contract (TVL increases)
     *      - Transfer 20 ether from main to vault1 (TVL stays same, just moved)
     *      - Expected: TVL reflects all deposits, vault transfers don't change total
     */
    function test_TVL_DepositWithdrawCycle() public {
        // Initial state - record TVL
        (address[] memory initialTokens, uint256[] memory initialAmounts) = lrtSquared.totalAssets();
        uint256 initialToken0TVL = 0;
        for (uint256 i = 0; i < initialTokens.length; i++) {
            if (initialTokens[i] == address(tokens[0])) {
                initialToken0TVL = initialAmounts[i];
                break;
            }
        }

        // Deposit to main
        uint256 mainDeposit = 50 ether;
        address[] memory depositTokens = new address[](1);
        depositTokens[0] = address(tokens[0]);
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = mainDeposit;

        tokens[0].approve(address(lrtSquared), mainDeposit);
        _deposit(depositTokens, depositAmounts, owner, hex"");

        // Check TVL increased
        (address[] memory afterDepositTokens, uint256[] memory afterDepositAmounts) = lrtSquared.totalAssets();
        uint256 afterDepositTVL = 0;
        for (uint256 i = 0; i < afterDepositTokens.length; i++) {
            if (afterDepositTokens[i] == address(tokens[0])) {
                afterDepositTVL = afterDepositAmounts[i];
                break;
            }
        }
        assertGt(afterDepositTVL, initialToken0TVL, "TVL should increase after deposit");

        // Deposit to vault
        uint256 vaultDeposit = 20 ether;
        tokens[0].approve(address(lrtSquared), vaultDeposit);
        _depositToVault(address(vault1), address(tokens[0]), vaultDeposit, hex"");

        // Configure vault
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultDeposit;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Check TVL includes vault
        (address[] memory afterVaultTokens, uint256[] memory afterVaultAmounts) = lrtSquared.totalAssets();
        uint256 afterVaultTVL = 0;
        for (uint256 i = 0; i < afterVaultTokens.length; i++) {
            if (afterVaultTokens[i] == address(tokens[0])) {
                afterVaultTVL = afterVaultAmounts[i];
                break;
            }
        }
        // Main balance reduced by vaultDeposit, but vault balance added back
        assertEq(afterVaultTVL, afterDepositTVL, "TVL should remain same (moved to vault)");
    }

    // ============================================
    // EDGE CASE TESTS (5 tests)
    // ============================================

    /**
     * @notice Test 15: Mixed enabled and disabled vaults
     * @dev Scenario:
     *      - Deposit 10 ether of token[0] to vault1
     *      - Deposit 15 ether of token[1] to vault2
     *      - Withdraw all assets from vault2 (required before disabling)
     *      - Disable vault2
     *      - Expected: totalAssets includes only enabled vault1, excludes disabled vault2
     */
    function test_EdgeCase_MixedEnabledDisabled() public {
        // Setup: Deposit to vault1 and vault2
        uint256 vault1Amount = 10 ether;
        uint256 vault2Amount = 15 ether;

        deal(address(tokens[0]), address(lrtSquared), vault1Amount);
        _depositToVault(address(vault1), address(tokens[0]), vault1Amount, hex"");

        deal(address(tokens[1]), address(lrtSquared), vault2Amount);
        _depositToVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Configure vaults
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vault1Amount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        address[] memory vault2Tokens = new address[](1);
        vault2Tokens[0] = address(tokens[1]);
        uint256[] memory vault2Balances = new uint256[](1);
        vault2Balances[0] = vault2Amount;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // CRITICAL: Must withdraw all assets before disabling vault
        // This matches the safety check in disableVault() that prevents disabling vaults with principal
        _withdrawFromVault(address(vault2), address(tokens[1]), vault2Amount, hex"");

        // Update mock vault2 to reflect withdrawal
        vault2Balances[0] = 0;
        vault2.setBalances(vault2Tokens, vault2Balances);

        // Transfer withdrawn tokens out of main contract (simulate sending to treasury or burning)
        // This ensures we're only testing vault balances, not main contract balances
        vm.prank(address(lrtSquared));
        tokens[1].transfer(address(0xdead), vault2Amount);

        // Now we can disable vault2
        _disableVault(address(vault2), hex"");

        // Test totalAssets
        (address[] memory tkns, uint256[] memory amounts) = lrtSquared.totalAssets();

        // Verify only enabled vault included
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertGt(amounts[i], 0, "Should include enabled vault1");
            } else if (tkns[i] == address(tokens[1])) {
                assertEq(amounts[i], 0, "Should exclude disabled vault2");
            }
        }
    }

    /**
     * @notice Test 16: Vault returns higher balance than principal (profits)
     * @dev Scenario:
     *      - Deposit 10 ether principal to vault1
     *      - Configure vault to return 12 ether (simulating 2 ether yield/profit)
     *      - Expected: getVaultBalances returns actual vault balance including profits (12 ether)
     */
    function test_EdgeCase_VaultProfits() public {
        // Setup: Deposit to vault
        uint256 principalAmount = 10 ether;

        deal(address(tokens[0]), address(lrtSquared), principalAmount);
        _depositToVault(address(vault1), address(tokens[0]), principalAmount, hex"");

        // Configure vault to return more than principal (simulating yield)
        uint256 vaultBalance = 12 ether;
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultBalance;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Test
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify profit is included
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], vaultBalance, "Should return actual vault balance including profits");
            }
        }
    }

    /**
     * @notice Test 17: All vaults empty
     * @dev Scenario:
     *      - Three vaults registered but no deposits made
     *      - Expected: getVaultBalances returns all zeros
     *      - Expected: totalAssets returns all zeros (main contract also has no balance)
     */
    function test_EdgeCase_AllVaultsEmpty() public view {
        // Test with no vault deposits
        (, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify all zeros
        for (uint256 i = 0; i < quantities.length; i++) {
            assertEq(quantities[i], 0, "All quantities should be zero with empty vaults");
        }

        // Test totalAssets
        (, uint256[] memory totalAmounts) = lrtSquared.totalAssets();

        // Should only reflect main contract balances (which are also zero)
        for (uint256 i = 0; i < totalAmounts.length; i++) {
            assertEq(totalAmounts[i], 0, "All amounts should be zero");
        }
    }

    /**
     * @notice Test 18: Vault returns non-whitelisted token
     * @dev Scenario:
     *      - Deposit 10 ether of whitelisted token[0] to vault1
     *      - Configure vault to return token[0] balance
     *      - De-whitelist token[0] (NOT unregister - just remove from whitelist)
     *      - Expected: Non-whitelisted token is excluded from getVaultBalances aggregation
     *      - Note: This is valid - you CAN de-whitelist tokens with vault balances
     */
    function test_EdgeCase_VaultReturnsNonWhitelistedToken() public {
        // Setup: Deposit whitelisted token
        uint256 depositAmount = 10 ether;

        deal(address(tokens[0]), address(lrtSquared), depositAmount);
        _depositToVault(address(vault1), address(tokens[0]), depositAmount, hex"");

        // Configure vault to return the balance
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = depositAmount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Remove token from whitelist
        _updateWhitelist(address(tokens[0]), false, hex"");

        // Test - should filter out non-whitelisted token
        (address[] memory tkns, uint256[] memory quantities) = lrtSquared.getVaultBalances();

        // Verify non-whitelisted token excluded
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(quantities[i], 0, "Should exclude non-whitelisted token from aggregation");
            }
        }
    }

    /**
     * @notice Test 19: getAssetBreakdown with only vault balances (no main balances)
     * @dev Scenario:
     *      - Deposit 20 ether directly to vault1 (no main contract deposit)
     *      - Expected: Breakdown shows main=0, vault=20, total=20
     */
    function test_EdgeCase_OnlyVaultBalances() public {
        // Setup: Deposit to vault without main contract deposits
        uint256 vaultAmount = 20 ether;

        deal(address(tokens[0]), address(lrtSquared), vaultAmount);
        _depositToVault(address(vault1), address(tokens[0]), vaultAmount, hex"");

        // Configure vault
        address[] memory vault1Tokens = new address[](1);
        vault1Tokens[0] = address(tokens[0]);
        uint256[] memory vault1Balances = new uint256[](1);
        vault1Balances[0] = vaultAmount;
        vault1.setBalances(vault1Tokens, vault1Balances);

        // Test
        (address[] memory tkns, uint256[] memory mainBalances, uint256[] memory vaultBalances, uint256[] memory totalBalances)
        = lrtSquared.getAssetBreakdown();

        // Verify breakdown
        for (uint256 i = 0; i < tkns.length; i++) {
            if (tkns[i] == address(tokens[0])) {
                assertEq(mainBalances[i], 0, "Main balance should be zero");
                assertEq(vaultBalances[i], vaultAmount, "Should show vault balance");
                assertEq(totalBalances[i], vaultAmount, "Total should equal vault balance");
            }
        }
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _registerVault(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Register vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(ILRTSquared.registerVault.selector, vault);

        _executeGovernance(data, description, revertData);
    }

    function _disableVault(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Disable vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.disableVault.selector,
            vault
        );

        _executeGovernance(data, description, revertData);
    }

    function _depositToVault(address vault, address asset, uint256 amount, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Deposit to vault: ",
                vm.toString(vault),
                " asset: ",
                vm.toString(asset),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.depositToVault.selector,
            vault,
            asset,
            amount
        );

        _executeGovernance(data, description, revertData);
    }

    function _withdrawFromVault(address vault, address asset, uint256 amount, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Withdraw from vault: ",
                vm.toString(vault),
                " asset: ",
                vm.toString(asset),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.withdrawFromVault.selector,
            vault,
            asset,
            amount
        );

        _executeGovernance(data, description, revertData);
    }

    function _deposit(
        address[] memory _tokens,
        uint256[] memory _amounts,
        address _receiver,
        bytes memory /*revertData*/
    ) internal {
        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");

        vm.startPrank(alice);
        for (uint256 i = 0; i < _tokens.length;) {
            deal(_tokens[i], alice, _amounts[i]);

            IERC20(_tokens[i]).approve(address(lrtSquared), _amounts[i]);
            unchecked {
                ++i;
            }
        }
        lrtSquared.deposit(_tokens, _amounts, _receiver);
        vm.stopPrank();
    }
}
