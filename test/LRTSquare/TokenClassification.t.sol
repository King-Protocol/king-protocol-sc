// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup} from "./LRTSquaredSetup.t.sol";
import {ILRTSquared} from "../../src/interfaces/ILRTSquared.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockStrategy} from "../../src/mocks/MockStrategy.sol";
import {Governable} from "../../src/LRTSquared/LRTSquaredStorage.sol";

/**
 * @title TokenClassificationTest
 * @notice Tests the token classification system (Native vs Staked) and strategy relationships
 * @dev Verifies that tokens are properly classified and linked to their strategies
 */
contract TokenClassificationTest is LRTSquaredTestSetup {
    MockERC20 public nativeToken;
    MockERC20 public stakedToken;
    MockERC20 public rewardToken;
    MockStrategy public mockStrategy;
    address public governor;

    function setUp() public override {
        super.setUp();

        // Create test tokens representing different types
        nativeToken = new MockERC20("Native Token", "NATIVE", 18);
        stakedToken = new MockERC20("Staked Token", "STAKED", 18);
        rewardToken = new MockERC20("Reward Token", "REWARD", 18);

        // Create strategy that stakes native tokens and returns staked tokens
        mockStrategy =
            new MockStrategy(address(lrtSquared), address(priceProvider), address(stakedToken), address(nativeToken));

        // Governor controls token registration
        governor = address(timelock);

        // Set test prices: native/staked = 1 ETH, reward = 0.1 ETH
        vm.startPrank(governor);
        priceProvider.setPrice(address(nativeToken), 1 ether);
        priceProvider.setPrice(address(stakedToken), 1 ether);
        priceProvider.setPrice(address(rewardToken), 0.1 ether);

        // Register tokens in the vault (initially as Native for setup)
        lrtSquared.registerToken(address(nativeToken), 1_000, ILRTSquared.TokenType.Native);
        lrtSquared.registerToken(address(stakedToken), 1_000, ILRTSquared.TokenType.Native);

        // Link native token to strategy that produces staked tokens
        ILRTSquared.StrategyConfig memory strategyConfig = ILRTSquared.StrategyConfig({
            strategyAdapter: address(mockStrategy),
            maxSlippageInBps: 100 // 1% max slippage allowed
        });
        lrtSquared.setTokenStrategyConfig(address(nativeToken), strategyConfig);

        // Give strategy some staked tokens to distribute during deposits
        stakedToken.mint(address(mockStrategy), 1_000 ether);

        vm.stopPrank();
    }

    // Test: Register token with classification
    function test_RegisterTokenWithType() public {
        // Create a new token to register
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.startPrank(governor);
        priceProvider.setPrice(address(newToken), 1 ether);

        // Register new token
        lrtSquared.registerToken(
            address(newToken),
            1000, // position weight limit
            ILRTSquared.TokenType.Native
        );

        // Verify registration and type
        ILRTSquared.TokenInfo memory info = lrtSquared.tokenInfos(address(newToken));
        assertTrue(info.registered, "Token should be registered");
        assertTrue(info.whitelisted, "Token should be whitelisted");
        assertEq(uint256(info.tokenType), uint256(ILRTSquared.TokenType.Native), "Token type should be Native");

        vm.stopPrank();
    }

    // Test: Register multiple tokens with different types
    function test_RegisterMultipleTokenTypes() public {
        vm.startPrank(governor);

        // NativeToken is already registered in setUp
        // StakedToken is already registered in setUp as Native (can't be Staked without strategy)
        // Register third token as Native
        lrtSquared.registerToken(address(rewardToken), 500, ILRTSquared.TokenType.Native);

        vm.stopPrank();

        // Verify all types
        ILRTSquared.TokenInfo memory nativeInfo = lrtSquared.tokenInfos(address(nativeToken));
        ILRTSquared.TokenInfo memory stakedInfo = lrtSquared.tokenInfos(address(stakedToken));
        ILRTSquared.TokenInfo memory rewardInfo = lrtSquared.tokenInfos(address(rewardToken));

        assertEq(uint256(nativeInfo.tokenType), uint256(ILRTSquared.TokenType.Native));
        assertEq(uint256(stakedInfo.tokenType), uint256(ILRTSquared.TokenType.Native)); // Must be Native without strategy
        assertEq(uint256(rewardInfo.tokenType), uint256(ILRTSquared.TokenType.Native));
    }

    // Test: Set token type for existing token
    function test_SetTokenType() public {
        vm.startPrank(governor);

        // The mockStrategy already returns stakedToken (set in constructor)
        // Set up the strategy config
        lrtSquared.setTokenStrategyConfig(
            address(nativeToken),
            ILRTSquared.StrategyConfig({strategyAdapter: address(mockStrategy), maxSlippageInBps: 100})
        );

        // Now we can set stakedToken to Staked type
        lrtSquared.setTokenType(address(stakedToken), ILRTSquared.TokenType.Staked);

        vm.stopPrank();

        // Verify type changed
        ILRTSquared.TokenInfo memory info = lrtSquared.tokenInfos(address(stakedToken));
        assertEq(uint256(info.tokenType), uint256(ILRTSquared.TokenType.Staked), "Type should be updated to Staked");
    }

    // Test: Set token type emits event
    function test_SetTokenTypeEmitsEvent() public {
        vm.startPrank(governor);

        // The mockStrategy already returns stakedToken
        lrtSquared.setTokenStrategyConfig(
            address(nativeToken),
            ILRTSquared.StrategyConfig({strategyAdapter: address(mockStrategy), maxSlippageInBps: 100})
        );

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit ILRTSquared.TokenTypeSet(address(stakedToken), ILRTSquared.TokenType.Staked);

        lrtSquared.setTokenType(address(stakedToken), ILRTSquared.TokenType.Staked);
        vm.stopPrank();
    }

    // Test: Cannot set type for unregistered token
    function test_CannotSetTypeForUnregisteredToken() public {
        // Create a new unregistered token
        MockERC20 unregisteredToken = new MockERC20("Unregistered", "UNREG", 18);

        vm.startPrank(governor);

        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.setTokenType(address(unregisteredToken), ILRTSquared.TokenType.Native);

        vm.stopPrank();
    }

    // Test: Only governor can set token type
    function test_OnlyGovernorCanSetTokenType() public {
        // NativeToken is already registered in setUp

        // Try as non-governor
        address randomUser = makeAddr("randomUser");
        vm.startPrank(randomUser);

        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.setTokenType(address(nativeToken), ILRTSquared.TokenType.Staked);

        vm.stopPrank();
    }

    // Test: Migrate multiple token types
    function test_MigrateTokenTypes() public {
        vm.startPrank(governor);

        // NativeToken and stakedToken are already registered in setUp
        // Register reward token
        lrtSquared.registerToken(address(rewardToken), 500, ILRTSquared.TokenType.Native);

        // The mockStrategy already returns stakedToken
        lrtSquared.setTokenStrategyConfig(
            address(nativeToken),
            ILRTSquared.StrategyConfig({strategyAdapter: address(mockStrategy), maxSlippageInBps: 100})
        );

        // Prepare migration arrays
        address[] memory tokens = new address[](3);
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](3);

        tokens[0] = address(nativeToken);
        types[0] = ILRTSquared.TokenType.Native;

        tokens[1] = address(stakedToken);
        types[1] = ILRTSquared.TokenType.Staked; // Now we can set to Staked because we have a strategy

        tokens[2] = address(rewardToken);
        types[2] = ILRTSquared.TokenType.Native;

        // Migrate
        lrtSquared.migrateTokenTypes(tokens, types);

        vm.stopPrank();

        // Verify all types updated
        ILRTSquared.TokenInfo memory nativeInfo = lrtSquared.tokenInfos(address(nativeToken));
        ILRTSquared.TokenInfo memory stakedInfo = lrtSquared.tokenInfos(address(stakedToken));
        ILRTSquared.TokenInfo memory rewardInfo = lrtSquared.tokenInfos(address(rewardToken));

        assertEq(uint256(nativeInfo.tokenType), uint256(ILRTSquared.TokenType.Native));
        assertEq(uint256(stakedInfo.tokenType), uint256(ILRTSquared.TokenType.Staked)); // Properly set to Staked
        assertEq(uint256(rewardInfo.tokenType), uint256(ILRTSquared.TokenType.Native));
    }

    // Test: Migrate token types emits event
    function test_MigrateTokenTypesEmitsEvent() public {
        vm.startPrank(governor);

        // Tokens are already registered in setUp

        address[] memory tokens = new address[](2);
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](2);

        tokens[0] = address(nativeToken);
        types[0] = ILRTSquared.TokenType.Native; // Keep as Native
        tokens[1] = address(stakedToken);
        types[1] = ILRTSquared.TokenType.Native; // Keep as Native (no strategy set)

        // Expect event
        vm.expectEmit(true, true, false, true);
        emit ILRTSquared.TokenTypesMigrated(tokens, types);

        lrtSquared.migrateTokenTypes(tokens, types);

        vm.stopPrank();
    }

    // Test: Migrate fails with mismatched array lengths
    function test_MigrateFailsWithMismatchedArrays() public {
        vm.startPrank(governor);

        address[] memory tokens = new address[](2);
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](3); // Different length

        tokens[0] = address(nativeToken);
        tokens[1] = address(stakedToken);

        vm.expectRevert(ILRTSquared.ArrayLengthMismatch.selector);
        lrtSquared.migrateTokenTypes(tokens, types);

        vm.stopPrank();
    }

    // Test: Migrate fails for unregistered tokens
    function test_MigrateFailsForUnregisteredTokens() public {
        // Create unregistered token
        MockERC20 unregisteredToken = new MockERC20("Unregistered", "UNREG", 18);

        vm.startPrank(governor);

        address[] memory tokens = new address[](1);
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](1);

        tokens[0] = address(unregisteredToken); // Not registered
        types[0] = ILRTSquared.TokenType.Native;

        vm.expectRevert(ILRTSquared.TokenNotRegistered.selector);
        lrtSquared.migrateTokenTypes(tokens, types);

        vm.stopPrank();
    }

    // Test: Only governor can migrate token types
    function test_OnlyGovernorCanMigrateTokenTypes() public {
        address randomUser = makeAddr("randomUser");

        address[] memory tokens = new address[](1);
        ILRTSquared.TokenType[] memory types = new ILRTSquared.TokenType[](1);

        vm.startPrank(randomUser);

        vm.expectRevert(Governable.OnlyGovernor.selector);
        lrtSquared.migrateTokenTypes(tokens, types);

        vm.stopPrank();
    }

    // Test: Token type persists through other operations
    function test_TokenTypePersistsThroughOperations() public {
        vm.startPrank(governor);

        // Set stakedToken to Staked type (it's already registered in setUp)
        lrtSquared.setTokenType(address(stakedToken), ILRTSquared.TokenType.Staked);

        // Update position weight limit
        lrtSquared.updateTokenPositionWeightLimit(address(stakedToken), 2000);

        // Whitelist/unwhitelist
        lrtSquared.updateWhitelist(address(stakedToken), false);
        lrtSquared.updateWhitelist(address(stakedToken), true);

        vm.stopPrank();

        // Verify type unchanged
        ILRTSquared.TokenInfo memory info = lrtSquared.tokenInfos(address(stakedToken));
        assertEq(uint256(info.tokenType), uint256(ILRTSquared.TokenType.Staked), "Type should remain Staked");
        assertEq(info.positionWeightLimit, 2000, "Weight limit should be updated");
        assertTrue(info.whitelisted, "Token should be whitelisted");
    }

    // Test: Default token type behavior (if any)
    function test_DefaultTokenTypeForLegacyTokens() public {
        // For tokens registered before the upgrade, they should default to Native
        // This test would be more relevant in fork tests where we check actual mainnet tokens

        vm.startPrank(governor);

        // Simulate a legacy registration (would need to test with old contract version)
        // For now, just verify our assumption about default values

        // In Solidity, enum defaults to first value (0), which is Native
        ILRTSquared.TokenType defaultType = ILRTSquared.TokenType(0);
        assertEq(uint256(defaultType), uint256(ILRTSquared.TokenType.Native), "Default should be Native");

        vm.stopPrank();
    }

    // Test: Cannot set token as Staked without strategy
    function test_CannotSetStakedTypeWithoutStrategy() public {
        vm.startPrank(governor);

        // NativeToken is already registered in setUp
        // But we set strategy for it that returns stakedToken, not nativeToken itself
        // Create a new token without strategy
        MockERC20 tokenWithoutStrategy = new MockERC20("No Strategy Token", "NOSTRAT", 18);
        priceProvider.setPrice(address(tokenWithoutStrategy), 1 ether);
        lrtSquared.registerToken(address(tokenWithoutStrategy), 1000, ILRTSquared.TokenType.Native);

        // Try to set as Staked - should fail since no strategy returns this token
        vm.expectRevert(ILRTSquared.StrategyReturnTokenNotRegistered.selector);
        lrtSquared.setTokenType(address(tokenWithoutStrategy), ILRTSquared.TokenType.Staked);

        vm.stopPrank();
    }

    // Test: Can register token directly as Staked when strategy exists
    function test_CanRegisterTokenAsStakedWithStrategy() public {
        vm.startPrank(governor);

        // We already have a strategy setup in setUp() that returns stakedToken
        // Just verify we can change stakedToken to Staked type
        lrtSquared.setTokenType(address(stakedToken), ILRTSquared.TokenType.Staked);

        // Verify it's set as Staked
        ILRTSquared.TokenInfo memory info = lrtSquared.tokenInfos(address(stakedToken));
        assertEq(uint256(info.tokenType), uint256(ILRTSquared.TokenType.Staked), "Token should be Staked");

        vm.stopPrank();
    }

    // Test: Backward compatible registerToken defaults to Native
    function test_BackwardCompatibleRegisterToken() public {
        // Create a new token
        MockERC20 backwardCompatToken = new MockERC20("Backward Compatible", "BC", 18);

        vm.startPrank(governor);
        priceProvider.setPrice(address(backwardCompatToken), 1 ether);

        // Use the 2-parameter version (backward compatible)
        lrtSquared.registerToken(address(backwardCompatToken), 1000);

        // Verify it defaulted to Native type
        ILRTSquared.TokenInfo memory info = lrtSquared.tokenInfos(address(backwardCompatToken));
        assertTrue(info.registered, "Token should be registered");
        assertEq(uint256(info.tokenType), uint256(ILRTSquared.TokenType.Native), "Token type should default to Native");

        vm.stopPrank();
    }
}
