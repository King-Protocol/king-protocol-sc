// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LRTSquaredSetup.t.sol";
import "forge-std/console2.sol";
import {MockStrategy} from "../../src/mocks/MockStrategy.sol";
import {MockPriceProvider} from "../../src/mocks/MockPriceProvider.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {LRTSquaredStorage} from "../../src/LRTSquared/LRTSquaredStorage.sol";

/**
 * @title PreviewRedeemTest
 * @notice Test suite for King Protocol's redemption calculation algorithm (previewRedeem)
 *
 * @dev This file focuses on testing the redemption calculation logic, not the execution.
 * It verifies how the native-first distribution algorithm works with various scenarios:
 * - KING token price = Total Vault Value (TVL) / KING Supply
 * - Every KING token is backed by assets in the vault
 * - Redemptions return a proportional share of vault assets
 * - Native tokens are prioritized over staked tokens
 * - Locked staked tokens cannot be used for redemptions
 *
 * Test scenarios cover progressive complexity:
 * 1. Zero redemption edge case
 * 2. Insufficient liquidity checks
 * 3. Native-only redemptions
 * 4. Cross-rebalancing with native tokens
 * 5. Staked token usage with liquidity constraints
 * 6. Locked token scenarios
 * 7. Rate limiting and complex distribution
 * 8. Proportional staked token distribution
 */
contract PreviewRedeemTest is LRTSquaredTestSetup {
    MockERC20 ethfi;
    MockERC20 eigen;
    MockERC20 swell;
    MockERC20 sethfi;
    MockERC20 eeigen;

    MockStrategy sethfiStrategy;
    MockStrategy eeigenStrategy;

    // Add reference to base test variables
    ILRTSquared vault;
    MockPriceProvider mockPriceProvider;

    // Pricing constants - all native tokens worth 0.5 ETH
    uint256 constant ETHFI_PRICE = 0.5e18; // 0.5 ETH per ETHFI
    uint256 constant EIGEN_PRICE = 0.5e18; // 0.5 ETH per EIGEN
    uint256 constant SWELL_PRICE = 0.5e18; // 0.5 ETH per SWELL

    // Staked tokens worth 2x their native counterpart
    uint256 constant SETHFI_EXCHANGE_RATE = 2e18; // 1 sETHFI = 2 ETHFI
    uint256 constant EEIGEN_EXCHANGE_RATE = 2e18; // 1 eEIGEN = 2 EIGEN

    function setUp() public override {
        super.setUp();

        // Set references to base test components
        vault = lrtSquared;
        mockPriceProvider = MockPriceProvider(address(priceProvider));

        // Create all 5 tokens
        ethfi = new MockERC20("Ether.Fi", "ETHFI", 18);
        eigen = new MockERC20("Eigen", "EIGEN", 18);
        swell = new MockERC20("Swell", "SWELL", 18);
        sethfi = new MockERC20("Staked Ether.Fi", "sETHFI", 18);
        eeigen = new MockERC20("Staked Eigen", "eEIGEN", 18);

        // Create strategies for staked tokens
        sethfiStrategy = new MockStrategy(address(vault), address(priceProvider), address(sethfi), address(ethfi));
        eeigenStrategy = new MockStrategy(address(vault), address(priceProvider), address(eeigen), address(eigen));

        // Set prices: native tokens = 0.5 ETH, staked tokens = 1 ETH (2x native)
        mockPriceProvider.setPrice(address(ethfi), ETHFI_PRICE);
        mockPriceProvider.setPrice(address(eigen), EIGEN_PRICE);
        mockPriceProvider.setPrice(address(swell), SWELL_PRICE);
        mockPriceProvider.setPrice(address(sethfi), ETHFI_PRICE * SETHFI_EXCHANGE_RATE / 1e18); // 1 ETH
        mockPriceProvider.setPrice(address(eeigen), EIGEN_PRICE * EEIGEN_EXCHANGE_RATE / 1e18); // 1 ETH

        // Skip governance and set owner as governor directly
        vm.store(
            address(lrtSquared),
            0x7d8b90e89a676f7a8a3cf40a0c23c3d2ea61cec6ae800738fbd79bc111b5ea87,
            bytes32(uint256(uint160(owner)))
        );

        vm.startPrank(owner);

        // Register all native tokens
        lrtSquared.registerToken(address(ethfi), uint64(HUNDRED_PERCENT_LIMIT), ILRTSquared.TokenType.Native);
        lrtSquared.registerToken(address(eigen), uint64(HUNDRED_PERCENT_LIMIT), ILRTSquared.TokenType.Native);
        lrtSquared.registerToken(address(swell), uint64(HUNDRED_PERCENT_LIMIT), ILRTSquared.TokenType.Native);
        lrtSquared.updateWhitelist(address(ethfi), true);
        lrtSquared.updateWhitelist(address(eigen), true);
        lrtSquared.updateWhitelist(address(swell), true);

        // Configure strategies for native tokens that have staked versions
        ILRTSquared.StrategyConfig memory ethfiStrategyConfig =
            ILRTSquared.StrategyConfig({strategyAdapter: address(sethfiStrategy), maxSlippageInBps: 100});
        lrtSquared.setTokenStrategyConfig(address(ethfi), ethfiStrategyConfig);

        ILRTSquared.StrategyConfig memory eigenStrategyConfig =
            ILRTSquared.StrategyConfig({strategyAdapter: address(eeigenStrategy), maxSlippageInBps: 100});
        lrtSquared.setTokenStrategyConfig(address(eigen), eigenStrategyConfig);

        // Register staked tokens (after strategies are configured)
        lrtSquared.registerToken(address(sethfi), uint64(HUNDRED_PERCENT_LIMIT), ILRTSquared.TokenType.Staked);
        lrtSquared.registerToken(address(eeigen), uint64(HUNDRED_PERCENT_LIMIT), ILRTSquared.TokenType.Staked);
        lrtSquared.updateWhitelist(address(sethfi), true);
        lrtSquared.updateWhitelist(address(eeigen), true);

        // Set alice as depositor
        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        lrtSquared.setDepositors(depositors, isDepositor);

        // Remove fees for cleaner test calculations
        lrtSquared.setFee(ILRTSquared.Fee({treasury: treasury, depositFeeInBps: 0, redeemFeeInBps: 0}));

        vm.stopPrank();

        // Mint initial supply to alice for testing
        ethfi.mint(alice, 10_000 ether);
        eigen.mint(alice, 10_000 ether);
        swell.mint(alice, 10_000 ether);
        sethfi.mint(alice, 10_000 ether);
        eeigen.mint(alice, 10_000 ether);

        // Depositor approves vault
        vm.startPrank(alice);
        ethfi.approve(address(vault), type(uint256).max);
        eigen.approve(address(vault), type(uint256).max);
        swell.approve(address(vault), type(uint256).max);
        sethfi.approve(address(vault), type(uint256).max);
        eeigen.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    // Helper function to deposit tokens and get KING tokens
    function _depositAndGetKing(
        address alice,
        uint256 ethfiAmount,
        uint256 eigenAmount,
        uint256 swellAmount,
        uint256 sethfiAmount,
        uint256 eeigenAmount
    ) internal returns (uint256 kingAmount) {
        vm.startPrank(alice);

        uint256 totalValue = 0;

        address[] memory depositTokens = new address[](5);
        uint256[] memory depositAmounts = new uint256[](5);
        uint256 depositCount = 0;

        if (ethfiAmount > 0) {
            depositTokens[depositCount] = address(ethfi);
            depositAmounts[depositCount] = ethfiAmount;
            depositCount++;
            totalValue += (ethfiAmount * ETHFI_PRICE) / 1e18;
        }

        if (eigenAmount > 0) {
            depositTokens[depositCount] = address(eigen);
            depositAmounts[depositCount] = eigenAmount;
            depositCount++;
            totalValue += (eigenAmount * EIGEN_PRICE) / 1e18;
        }

        if (swellAmount > 0) {
            depositTokens[depositCount] = address(swell);
            depositAmounts[depositCount] = swellAmount;
            depositCount++;
            totalValue += (swellAmount * SWELL_PRICE) / 1e18;
        }

        if (sethfiAmount > 0) {
            depositTokens[depositCount] = address(sethfi);
            depositAmounts[depositCount] = sethfiAmount;
            depositCount++;
            totalValue += (sethfiAmount * ETHFI_PRICE * SETHFI_EXCHANGE_RATE) / 1e36;
        }

        if (eeigenAmount > 0) {
            depositTokens[depositCount] = address(eeigen);
            depositAmounts[depositCount] = eeigenAmount;
            depositCount++;
            totalValue += (eeigenAmount * EIGEN_PRICE * EEIGEN_EXCHANGE_RATE) / 1e36;
        }

        // Resize arrays to actual count
        if (depositCount > 0) {
            address[] memory actualTokens = new address[](depositCount);
            uint256[] memory actualAmounts = new uint256[](depositCount);
            for (uint256 i = 0; i < depositCount; i++) {
                actualTokens[i] = depositTokens[i];
                actualAmounts[i] = depositAmounts[i];
            }
            vault.deposit(actualTokens, actualAmounts, alice);
        }

        kingAmount = vault.balanceOf(alice);
        vm.stopPrank();
    }

    // Helper to set locked amounts in strategies
    function _setLockedAmounts(uint256 sethfiLocked, uint256 eeigenLocked) internal {
        sethfiStrategy.setTransferableAmount(sethfi.balanceOf(address(vault)) - sethfiLocked);
        eeigenStrategy.setTransferableAmount(eeigen.balanceOf(address(vault)) - eeigenLocked);
    }

    // Test 1: Redemption with 0 KING provided, should return empty amounts
    function test_01_ZeroRedemption() public {
        // Setup: Deposit some assets first (need backing for KING)
        // 100 ETHFI (50 ETH), 100 EIGEN (50 ETH), 50 SWELL (25 ETH)
        // Total: 125 ETH value
        _depositAndGetKing(alice, 100 ether, 100 ether, 50 ether, 0, 0);

        // Try to redeem 0 KING tokens
        uint256 redeemAmount = 0;

        vm.startPrank(alice);
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        // Should return empty arrays for zero redemption
        assertEq(tokens.length, 0, "Should return empty token array for zero redemption");
        assertEq(amounts.length, 0, "Should return empty amounts array for zero redemption");
        vm.stopPrank();
    }

    // Test 2: Not enough liquidity for a redemption, should return error InsufficientLiquidity
    function test_02_InsufficientLiquidity() public {
        // Setup: Most assets locked, redemption exceeds available
        // 10 ETHFI (5 ETH), 10 EIGEN (5 ETH), 20 SWELL (10 ETH), 100 sETHFI (100 ETH), 100 eEIGEN (100 ETH)
        // Total vault value: 220 ETH
        // Lock 95 sETHFI and 95 eEIGEN
        // Available liquidity: 5 + 5 + 10 + 5 + 5 = 30 ETH
        _depositAndGetKing(alice, 10 ether, 10 ether, 20 ether, 100 ether, 100 ether);
        _setLockedAmounts(95 ether, 95 ether);

        uint256 totalKing = vault.totalSupply();

        // Try to redeem 50% (110 ETH worth), but only 30 ETH available
        uint256 redeemAmount = totalKing / 2;

        vm.startPrank(alice);

        // Both preview and actual redeem should revert
        vm.expectRevert(ILRTSquared.InsufficientLiquidity.selector);
        vault.previewRedeem(redeemAmount);

        vm.expectRevert(ILRTSquared.InsufficientLiquidity.selector);
        vault.redeem(redeemAmount);

        vm.stopPrank();
    }

    // Test 3: Redemption that only needs native tokens, only native tokens in the vault
    function test_03_NativeOnly_OnlyNativeInVault() public {
        // Setup: Only native tokens in vault
        // 100 ETHFI (50 ETH), 100 EIGEN (50 ETH), 50 SWELL (25 ETH)
        // Total: 125 ETH value
        _depositAndGetKing(alice, 100 ether, 100 ether, 50 ether, 0, 0);

        uint256 totalKing = vault.totalSupply();

        // Redeem 20% of KING (20% of 125 ETH = 25 ETH worth)
        uint256 redeemAmount = totalKing / 5;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        // Should receive proportional amounts from each native token
        // ETHFI: 50/125 = 40% of vault, so 40% of 25 ETH = 10 ETH worth = 20 ETHFI
        // EIGEN: 50/125 = 40% of vault, so 40% of 25 ETH = 10 ETH worth = 20 EIGEN
        // SWELL: 25/125 = 20% of vault, so 20% of 25 ETH = 5 ETH worth = 10 SWELL

        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 swellAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) {
                ethfiAmount = amounts[i];
            } else if (tokens[i] == address(eigen)) {
                eigenAmount = amounts[i];
            } else if (tokens[i] == address(swell)) {
                swellAmount = amounts[i];
            } else if (amounts[i] > 0) {
                // Should not receive any staked tokens
                ILRTSquared.TokenInfo memory tokenInfo = vault.tokenInfos(tokens[i]);
                assertEq(
                    uint8(tokenInfo.tokenType), uint8(ILRTSquared.TokenType.Native), "Should only receive native tokens"
                );
            }
        }

        assertApproxEqRel(ethfiAmount, 20 ether, 1e15, "Should receive ~20 ETHFI");
        assertApproxEqRel(eigenAmount, 20 ether, 1e15, "Should receive ~20 EIGEN");
        assertApproxEqRel(swellAmount, 10 ether, 1e15, "Should receive ~10 SWELL");

        vm.stopPrank();
    }

    // Test 4: Redemption that only needs native tokens, staked assets in the vault but not required
    function test_04_NativeOnly_WithStakedInVault() public {
        // Setup: Mixed vault but redemption small enough for native-only
        // 200 ETHFI (100 ETH), 200 EIGEN (100 ETH), 100 SWELL (50 ETH), 100 sETHFI (100 ETH), 100 eEIGEN (100 ETH)
        // Total: 450 ETH value, native portion: 250 ETH
        _depositAndGetKing(alice, 200 ether, 200 ether, 100 ether, 100 ether, 100 ether);

        uint256 totalKing = vault.totalSupply();

        // Redeem 10% of KING (10% of 450 ETH = 45 ETH worth)
        // Native liquidity (250 ETH) is more than enough
        uint256 redeemAmount = totalKing / 10;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        // Following the fair distribution algorithm:
        // Token pairs proportions:
        // - SWELL: 50/450 = 11.11% → 45 * 0.1111 = 5 ETH worth = 10 SWELL
        // - EIGEN+eEIGEN: 200/450 = 44.44% → 45 * 0.4444 = 20 ETH worth = 40 EIGEN
        // - ETHFI+sETHFI: 200/450 = 44.44% → 45 * 0.4444 = 20 ETH worth = 40 ETHFI

        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 swellAmount = 0;
        uint256 sethfiAmount = 0;
        uint256 eeigenAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) ethfiAmount = amounts[i];
            else if (tokens[i] == address(eigen)) eigenAmount = amounts[i];
            else if (tokens[i] == address(swell)) swellAmount = amounts[i];
            else if (tokens[i] == address(sethfi)) sethfiAmount = amounts[i];
            else if (tokens[i] == address(eeigen)) eeigenAmount = amounts[i];
        }

        // Should only use native tokens
        assertApproxEqRel(ethfiAmount, 40 ether, 1e15, "Should receive ~40 ETHFI");
        assertApproxEqRel(eigenAmount, 40 ether, 1e15, "Should receive ~40 EIGEN");
        assertApproxEqRel(swellAmount, 10 ether, 1e15, "Should receive ~10 SWELL");
        assertEq(sethfiAmount, 0, "Should not receive any sETHFI");
        assertEq(eeigenAmount, 0, "Should not receive any eEIGEN");

        vm.stopPrank();
    }

    // Test 5: Cross-rebalancing among native tokens when sufficient native liquidity exists
    function test_05_NativeCrossRebalancing() public {
        /**
         * Initial inventory (using smaller amounts to stay under rate limit):
         * - SWELL: 100 tokens (50 ETH worth)
         * - ETHFI: 100 tokens (50 ETH worth)
         * - EIGEN: 300 tokens (150 ETH worth)
         * - sETHFI: 500 tokens (500 ETH worth, 50% locked = 250 ETH available)
         * - eEIGEN: 200 tokens (200 ETH worth)
         * TVL = 950 ETH
         *
         * Redemption: 95 ETH worth (10% of TVL)
         *
         * Proportional targets per token pair:
         * - SWELL: 50 * 0.1 = 5 ETH worth
         * - ETHFI+sETHFI: 550 * 0.1 = 55 ETH worth
         * - EIGEN+eEIGEN: 350 * 0.1 = 35 ETH worth
         *
         * First pass - native token distribution:
         * - SWELL: Take 10 tokens (5 ETH worth), Remaining: 90 tokens (45 ETH worth)
         * - ETHFI: Take all 100 tokens (50 ETH worth), Remaining: 0, Shortfall: 5 ETH worth
         * - EIGEN: Take 70 tokens (35 ETH worth), Remaining: 230 tokens (115 ETH worth)
         *
         * Total shortfall: 5 ETH worth
         * Available native liquidity for rebalancing: 45 + 115 = 160 ETH worth
         *
         * Cross-rebalancing ratio: 5 / 160 = 0.03125 (~3.125%)
         *
         * Cross-rebalancing distribution:
         * - SWELL: 45 * 0.03125 = 1.40625 ETH worth (2.8125 tokens)
         * - EIGEN: 115 * 0.03125 = 3.59375 ETH worth (7.1875 tokens)
         *
         * Final native token distribution:
         * - SWELL: 5 + 1.40625 = 6.40625 ETH worth (12.8125 tokens)
         * - ETHFI: 50 ETH worth (100 tokens)
         * - EIGEN: 35 + 3.59375 = 38.59375 ETH worth (77.1875 tokens)
         *
         * Total distributed: 6.40625 + 50 + 38.59375 = 95 ETH worth ✓
         * No staked tokens needed since native liquidity was sufficient after cross-rebalancing.
         */

        // Setup with smaller amounts to stay under rate limit
        _depositAndGetKing(alice, 100 ether, 300 ether, 100 ether, 500 ether, 200 ether);
        _setLockedAmounts(250 ether, 0); // 50% of sETHFI locked

        uint256 totalKing = vault.totalSupply();

        // Redeem 10% of TVL
        uint256 redeemAmount = totalKing / 10;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 swellAmount = 0;
        uint256 sethfiAmount = 0;
        uint256 eeigenAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) ethfiAmount = amounts[i];
            else if (tokens[i] == address(eigen)) eigenAmount = amounts[i];
            else if (tokens[i] == address(swell)) swellAmount = amounts[i];
            else if (tokens[i] == address(sethfi)) sethfiAmount = amounts[i];
            else if (tokens[i] == address(eeigen)) eeigenAmount = amounts[i];
        }

        // Expected results from cross-rebalancing calculation
        assertApproxEqRel(swellAmount, 12.8125 ether, 1e15, "Should use ~12.8125 SWELL after cross-rebalancing");
        assertEq(ethfiAmount, 100 ether, "Should use all 100 ETHFI");
        assertApproxEqRel(eigenAmount, 77.1875 ether, 1e15, "Should use ~77.1875 EIGEN after cross-rebalancing");
        assertEq(sethfiAmount, 0, "Should not use any sETHFI");
        assertEq(eeigenAmount, 0, "Should not use any eEIGEN");

        vm.stopPrank();
    }

    // Test 6: Redemption with not enough native liquidity, exhausting all native tokens then using staked
    function test_06_InsufficientNative_UseStaked() public {
        /**
         * Tests the scenario where native tokens alone cannot fulfill the redemption.
         * Algorithm must exhaust all native tokens first, then use staked tokens.
         *
         * Initial vault inventory:
         * - 10 ETHFI (5 ETH worth at 0.5 ETH per token)
         * - 10 EIGEN (5 ETH worth at 0.5 ETH per token)
         * - 20 SWELL (10 ETH worth at 0.5 ETH per token)
         * - 100 sETHFI (100 ETH worth at 1 ETH per token)
         * - 50 eEIGEN (50 ETH worth at 1 ETH per token)
         *
         * Total vault value: 170 ETH
         * Native tokens total: 20 ETH
         * Staked tokens total: 150 ETH
         *
         * Redemption request: 50 ETH worth (29.4% of 170 ETH TVL)
         *
         * Distribution process:
         * 1. Use ALL native tokens first: 10 ETHFI + 10 EIGEN + 20 SWELL = 20 ETH
         * 2. Still need: 50 - 20 = 30 ETH from staked tokens
         * 3. Distribute the 30 ETH proportionally among available staked tokens:
         *    - sETHFI gets: 30 × (100/150) = 20 ETH worth = 20 sETHFI tokens
         *    - eEIGEN gets: 30 × (50/150) = 10 ETH worth = 10 eEIGEN tokens
         */
        _depositAndGetKing(alice, 10 ether, 10 ether, 20 ether, 100 ether, 50 ether);

        uint256 totalKing = vault.totalSupply();

        // Redeem 50 ETH worth (50/170 ≈ 29.4%)
        uint256 redeemAmount = totalKing * 50 / 170;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 swellAmount = 0;
        uint256 sethfiAmount = 0;
        uint256 eeigenAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) ethfiAmount = amounts[i];
            else if (tokens[i] == address(eigen)) eigenAmount = amounts[i];
            else if (tokens[i] == address(swell)) swellAmount = amounts[i];
            else if (tokens[i] == address(sethfi)) sethfiAmount = amounts[i];
            else if (tokens[i] == address(eeigen)) eeigenAmount = amounts[i];
        }

        // Should exhaust ALL native tokens first
        assertEq(ethfiAmount, 10 ether, "Should use all 10 ETHFI");
        assertEq(eigenAmount, 10 ether, "Should use all 10 EIGEN");
        assertEq(swellAmount, 20 ether, "Should use all 20 SWELL");

        // Then use staked tokens proportionally for unfulfilled amount (30 ETH)
        assertApproxEqRel(sethfiAmount, 20 ether, 1e15, "Should use ~20 sETHFI for unfulfilled portion");
        assertApproxEqRel(eeigenAmount, 10 ether, 1e15, "Should use ~10 eEIGEN for unfulfilled portion");

        // Verify total value
        uint256 totalValue = ethfiAmount * ETHFI_PRICE / 1e18 + eigenAmount * EIGEN_PRICE / 1e18
            + swellAmount * SWELL_PRICE / 1e18 + sethfiAmount * 1e18 / 1e18 + eeigenAmount * 1e18 / 1e18;

        assertApproxEqRel(totalValue, 50 ether, 1e15, "Total redemption value should be ~50 ETH");

        vm.stopPrank();
    }

    // Test 7: With locked sETHFI, but no rebalancing necessary among staked tokens
    function test_07_LockedTokens_NoStakedRebalancing() public {
        // Setup: Some sETHFI locked but enough other liquidity
        // 10 ETHFI (5 ETH), 10 EIGEN (5 ETH), 10 SWELL (5 ETH), 100 sETHFI (100 ETH, 50 locked), 100 eEIGEN (100 ETH)
        // Total: 215 ETH, available: 165 ETH
        _depositAndGetKing(alice, 10 ether, 10 ether, 10 ether, 100 ether, 100 ether);
        _setLockedAmounts(50 ether, 0); // 50 sETHFI locked

        uint256 totalKing = vault.totalSupply();

        // Redeem 30% (30% of 215 ETH = 64.5 ETH worth)
        // Available liquidity sufficient despite locks
        uint256 redeemAmount = (totalKing * 30) / 100;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        // Expected distribution:
        // Proportional targets:
        // - SWELL: 5/215 * 64.5 = 1.5 ETH
        // - EIGEN+eEIGEN: 105/215 * 64.5 = 31.5 ETH
        // - ETHFI+sETHFI: 105/215 * 64.5 = 31.5 ETH
        //
        // All natives used first, then staked tokens fill the gap
        // No cross-rebalancing needed among staked despite sETHFI lock

        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 swellAmount = 0;
        uint256 sethfiAmount = 0;
        uint256 eeigenAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) ethfiAmount = amounts[i];
            else if (tokens[i] == address(eigen)) eigenAmount = amounts[i];
            else if (tokens[i] == address(swell)) swellAmount = amounts[i];
            else if (tokens[i] == address(sethfi)) sethfiAmount = amounts[i];
            else if (tokens[i] == address(eeigen)) eeigenAmount = amounts[i];
        }

        // Should use all natives and some staked tokens
        assertEq(swellAmount, 10 ether, "Should use all 10 SWELL");
        assertEq(eigenAmount, 10 ether, "Should use all 10 EIGEN");
        assertEq(ethfiAmount, 10 ether, "Should use all 10 ETHFI");
        // Staked tokens used to cover remaining ~49.5 ETH
        assertGt(sethfiAmount, 0, "Should use some sETHFI");
        assertLe(sethfiAmount, 50 ether, "Should not exceed available sETHFI");
        assertGt(eeigenAmount, 0, "Should use some eEIGEN");

        vm.stopPrank();
    }

    // Test 8: With locked sETHFI forcing rebalancing among staked tokens
    function test_08_LockedTokens_RequiresStakedRebalancing() public {
        /**
         * Tests proper distribution when most staked tokens are locked.
         * Must distribute based on available liquidity ratios.
         *
         * Initial vault inventory:
         * - 5 ETHFI (2.5 ETH worth at 0.5 ETH per token)
         * - 5 EIGEN (2.5 ETH worth at 0.5 ETH per token)
         * - 0 SWELL
         * - 100 sETHFI (100 ETH worth at 1 ETH per token, but 99 are locked)
         * - 31 eEIGEN (31 ETH worth at 1 ETH per token, all unlocked)
         *
         * Total vault value: 136 ETH
         * Available liquidity: 5 ETH (natives) + 1 ETH (sETHFI) + 31 ETH (eEIGEN) = 37 ETH
         */
        _depositAndGetKing(alice, 5 ether, 5 ether, 0, 100 ether, 31 ether);
        _setLockedAmounts(99 ether, 0); // 99% of sETHFI locked

        uint256 totalKing = vault.totalSupply();

        // Redeem 15% (15% of 136 ETH = 20.4 ETH worth)
        uint256 redeemAmount = (totalKing * 15) / 100;

        vm.startPrank(alice);

        // Preview redemption
        (address[] memory tokens, uint256[] memory amounts,) = vault.previewRedeem(redeemAmount);

        /**
         * Expected distribution for 20.4 ETH redemption (15% of 136 ETH TVL):
         *
         * Step 1: Use all native tokens first
         * - Take all 5 ETHFI (2.5 ETH worth)
         * - Take all 5 EIGEN (2.5 ETH worth)
         * - Total from natives: 5 ETH
         *
         * Step 2: Calculate remaining need
         * - Still need: 20.4 - 5 = 15.4 ETH from staked tokens
         *
         * Step 3: Check available staked liquidity
         * - sETHFI: Only 1 token unlocked = 1 ETH available (99 are locked)
         * - eEIGEN: All 31 tokens unlocked = 31 ETH available
         * - Total available from staked: 32 ETH
         *
         * Step 4: Distribute 15.4 ETH proportionally based on available liquidity
         * - sETHFI gets: 15.4 × (1/32) = 0.48125 ETH = 0.48125 sETHFI tokens
         * - eEIGEN gets: 15.4 × (31/32) = 14.91875 ETH = 14.91875 eEIGEN tokens
         *
         * Total distributed: 5 + 0.48125 + 14.91875 = 20.4 ETH ✓
         */
        uint256 ethfiAmount = 0;
        uint256 eigenAmount = 0;
        uint256 sethfiAmount = 0;
        uint256 eeigenAmount = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(ethfi)) ethfiAmount = amounts[i];
            else if (tokens[i] == address(eigen)) eigenAmount = amounts[i];
            else if (tokens[i] == address(sethfi)) sethfiAmount = amounts[i];
            else if (tokens[i] == address(eeigen)) eeigenAmount = amounts[i];
        }

        // Verify proper distribution based on available liquidity
        assertEq(ethfiAmount, 5 ether, "Should use all 5 ETHFI");
        assertEq(eigenAmount, 5 ether, "Should use all 5 EIGEN");
        assertApproxEqRel(sethfiAmount, 0.48125 ether, 1e15, "Should use ~0.48125 sETHFI (proportional)");
        assertApproxEqRel(eeigenAmount, 14.91875 ether, 1e15, "Should use ~14.91875 eEIGEN (proportional)");

        // Verify total value
        uint256 totalValue = ethfiAmount * ETHFI_PRICE / 1e18 // 2.5 ETH
            + eigenAmount * EIGEN_PRICE / 1e18 // 2.5 ETH
            + sethfiAmount * 1e18 / 1e18 // 0.48125 ETH
            + eeigenAmount * 1e18 / 1e18; // 14.91875 ETH

        assertApproxEqRel(totalValue, 20.4 ether, 1e15, "Total value should be ~20.4 ETH");

        vm.stopPrank();
    }
}
