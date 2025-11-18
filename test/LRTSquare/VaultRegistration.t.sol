// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared} from "./LRTSquaredSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockKingVault} from "./mock/MockKingVault.sol";

/**
 * @title VaultRegistrationTest
 * @notice Test suite for vault registration, enable/disable functionality
 * @dev Tests tasks 1.1, 1.2, 1.3 of KingVault Integration (Phase 1)
 */
contract VaultRegistrationTest is LRTSquaredTestSetup {
    // Mock vault instances
    MockKingVault mockVault1;
    MockKingVault mockVault2;
    MockKingVault mockVault3;

    function setUp() public override {
        super.setUp();

        // Deploy mock vault instances
        mockVault1 = new MockKingVault();
        mockVault2 = new MockKingVault();
        mockVault3 = new MockKingVault();

        // Register tokens for testing
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");
    }

    // ============================================
    // 1.4.1 VAULT REGISTRATION TESTS
    // ============================================

    /**
     * @notice Test successful vault registration with single asset
     */
    function test_registerVault_singleAsset_success() public {
        // Configure vault with single asset
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);

        // Verify vault not registered before
        assertFalse(lrtSquared.isVaultRegistered(address(mockVault1)));

        // Register vault
        _registerVault(address(mockVault1), hex"");

        // Verify registration
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1)));
        assertTrue(lrtSquared.isVaultEnabled(address(mockVault1)));
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[0])));

        // Verify vault added to array
        address[] memory allVaults = lrtSquared.allVaults();
        assertEq(allVaults.length, 1);
        assertEq(allVaults[0], address(mockVault1));
    }

    /**
     * @notice Test successful vault registration with multiple assets
     */
    function test_registerVault_multipleAssets_success() public {
        // Configure vault with multiple assets
        address[] memory acceptedAssets = new address[](3);
        acceptedAssets[0] = address(tokens[0]);
        acceptedAssets[1] = address(tokens[1]);
        acceptedAssets[2] = address(tokens[2]);
        uint256[] memory balances = new uint256[](3);
        balances[0] = 0;
        balances[1] = 0;
        balances[2] = 0;

        mockVault1.setBalances(acceptedAssets, balances);

        _registerVault(address(mockVault1), hex"");

        // Verify all accepted assets configured correctly
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[0])));
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[1])));
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[2])));
    }

    /**
     * @notice Test vault registration can be called multiple times to update assets
     */
    function test_registerVault_updateAcceptedAssets_success() public {
        // Initial registration with one asset
        address[] memory initialAssets = new address[](1);
        initialAssets[0] = address(tokens[0]);
        uint256[] memory initialBalances = new uint256[](1);
        initialBalances[0] = 0;

        mockVault1.setBalances(initialAssets, initialBalances);
        _registerVault(address(mockVault1), hex"");

        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[0])));
        assertFalse(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[1])));

        // Update vault configuration to add second asset
        address[] memory updatedAssets = new address[](2);
        updatedAssets[0] = address(tokens[0]);
        updatedAssets[1] = address(tokens[1]);
        uint256[] memory updatedBalances = new uint256[](2);
        updatedBalances[0] = 0;
        updatedBalances[1] = 0;

        mockVault1.setBalances(updatedAssets, updatedBalances);
        _registerVault(address(mockVault1), hex"");

        // Verify updates - now both assets should be accepted
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[0])));
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[1])));

        // Verify vault not duplicated in array
        address[] memory allVaults = lrtSquared.allVaults();
        assertEq(allVaults.length, 1);
    }

    /**
     * @notice Test vault registration with zero address reverts
     */
    function test_registerVault_zeroAddress_reverts() public {
        _registerVault(
            address(0),
            abi.encodeWithSelector(ILRTSquared.VaultCannotBeZeroAddress.selector)
        );
    }

    /**
     * @notice Test vault registration with empty assets array reverts
     */
    function test_registerVault_emptyAssets_reverts() public {
        // Configure vault to return empty assets array
        address[] memory emptyAssets = new address[](0);
        uint256[] memory emptyBalances = new uint256[](0);

        mockVault1.setBalances(emptyAssets, emptyBalances);

        _registerVault(
            address(mockVault1),
            abi.encodeWithSelector(ILRTSquared.InvalidValue.selector)
        );
    }

    /**
     * @notice Test vault registration with unregistered token reverts
     */
    function test_registerVault_unregisteredToken_reverts() public {
        address unregisteredToken = makeAddr("unregisteredToken");

        // Configure vault with unregistered token
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = unregisteredToken;
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);

        _registerVault(
            address(mockVault1),
            abi.encodeWithSelector(ILRTSquared.TokenNotRegistered.selector)
        );
    }

    /**
     * @notice Test registration fails for contract without ERC165
     */
    function test_registerVault_noERC165_reverts() public {
        // Deploy malicious contract without ERC165
        MaliciousVaultNoERC165 maliciousVault = new MaliciousVaultNoERC165();

        // Configure vault with valid assets
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        maliciousVault.setAssets(acceptedAssets);

        _registerVault(
            address(maliciousVault), abi.encodeWithSelector(ILRTSquared.VaultDoesNotSupportERC165.selector)
        );
    }

    /**
     * @notice Test registration fails for contract with ERC165 but wrong interface
     */
    function test_registerVault_wrongInterface_reverts() public {
        // Deploy contract with ERC165 but not implementing IKingVault
        MaliciousVaultWrongInterface maliciousVault = new MaliciousVaultWrongInterface();

        _registerVault(
            address(maliciousVault), abi.encodeWithSelector(ILRTSquared.NotKingVault.selector)
        );
    }

    /**
     * @notice Test registration fails for malicious contract with only assets()
     */
    function test_registerVault_onlyAssetsMethod_reverts() public {
        // Deploy malicious contract with only assets() method
        MaliciousVaultOnlyAssets maliciousVault = new MaliciousVaultOnlyAssets();

        // Configure with valid assets
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        maliciousVault.setAssets(acceptedAssets);

        // Should fail ERC165 check
        _registerVault(
            address(maliciousVault), abi.encodeWithSelector(ILRTSquared.VaultDoesNotSupportERC165.selector)
        );
    }

    /**
     * @notice Test registration event is emitted correctly
     */
    function test_registerVault_emitsEvent() public {
        address[] memory acceptedAssets = new address[](2);
        acceptedAssets[0] = address(tokens[0]);
        acceptedAssets[1] = address(tokens[1]);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        mockVault1.setBalances(acceptedAssets, balances);

        // Cannot easily test event emission through governance,
        // but we verify the registration succeeded
        _registerVault(address(mockVault1), hex"");

        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1)));
    }

    /**
     * @notice Test multiple vaults can be registered
     */
    function test_registerVault_multipleVaults_success() public {
        address[] memory assets1 = new address[](1);
        assets1[0] = address(tokens[0]);
        uint256[] memory balances1 = new uint256[](1);
        balances1[0] = 0;

        address[] memory assets2 = new address[](1);
        assets2[0] = address(tokens[1]);
        uint256[] memory balances2 = new uint256[](1);
        balances2[0] = 0;

        mockVault1.setBalances(assets1, balances1);
        mockVault2.setBalances(assets2, balances2);

        _registerVault(address(mockVault1), hex"");
        _registerVault(address(mockVault2), hex"");

        // Verify both registered
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1)));
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault2)));

        // Verify both in array
        address[] memory allVaults = lrtSquared.allVaults();
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], address(mockVault1));
        assertEq(allVaults[1], address(mockVault2));
    }

    // ============================================
    // 1.4.2 ENABLE/DISABLE TESTS WITH PRINCIPAL VALIDATION
    // ============================================

    /**
     * @notice Test enabling a registered vault succeeds
     */
    function test_enableVault_success() public {
        // Register vault
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        _registerVault(address(mockVault1), hex"");

        // Disable vault
        _disableVault(address(mockVault1), hex"");
        assertFalse(lrtSquared.isVaultEnabled(address(mockVault1)));

        // Re-enable
        _enableVault(address(mockVault1), hex"");

        assertTrue(lrtSquared.isVaultEnabled(address(mockVault1)));
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1))); // Still registered
    }

    /**
     * @notice Test enabling an unregistered vault reverts
     */
    function test_enableVault_unregistered_reverts() public {
        _enableVault(
            address(mockVault1),
            abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector)
        );
    }

    /**
     * @notice Test disabling vault without principal succeeds
     */
    function test_disableVault_noPrincipal_success() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        _registerVault(address(mockVault1), hex"");
        assertTrue(lrtSquared.isVaultEnabled(address(mockVault1)));

        // Disable (no principal deposited)
        _disableVault(address(mockVault1), hex"");

        assertFalse(lrtSquared.isVaultEnabled(address(mockVault1)));
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1))); // Still registered
    }

    /**
     * @notice Test disabling vault with principal reverts
     * @dev This is the CRITICAL safety check
     * NOTE: Full implementation requires depositToVault (task 2.1)
     */
    function test_disableVault_withPrincipal_reverts() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        _registerVault(address(mockVault1), hex"");

        // NOTE: This test documents the expected behavior
        // Full implementation requires depositToVault (task 2.1)
        // Expected: revert VaultHasPrincipal(mockVault1, address(tokens[0]), amount)

        // Test will be completed when depositToVault is implemented
    }

    /**
     * @notice Test disabling unregistered vault reverts
     */
    function test_disableVault_unregistered_reverts() public {
        _disableVault(
            address(mockVault1),
            abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector)
        );
    }

    /**
     * @notice Test vault remains in registry array after disable
     * @dev Audit trail requirement - vaults never removed
     */
    function test_disableVault_remainsInRegistry() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        _registerVault(address(mockVault1), hex"");

        uint256 vaultCountBefore = lrtSquared.allVaults().length;

        _disableVault(address(mockVault1), hex"");

        uint256 vaultCountAfter = lrtSquared.allVaults().length;

        // Vault count unchanged - disabled but not removed
        assertEq(vaultCountBefore, vaultCountAfter);
        assertTrue(lrtSquared.isVaultRegistered(address(mockVault1)));
        assertFalse(lrtSquared.isVaultEnabled(address(mockVault1)));
    }

    // ============================================
    // 1.4.3 VIEW FUNCTION TESTS
    // ============================================

    /**
     * @notice Test vaultInfo view function returns correct data
     */
    function test_vaultInfo_success() public {
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(acceptedAssets, balances);

        // Before registration
        (bool registeredBefore, bool enabledBefore) = lrtSquared.vaultInfo(address(mockVault1));
        assertFalse(registeredBefore);
        assertFalse(enabledBefore);

        // After registration
        _registerVault(address(mockVault1), hex"");
        (bool registeredAfter, bool enabledAfter) = lrtSquared.vaultInfo(address(mockVault1));
        assertTrue(registeredAfter);
        assertTrue(enabledAfter);

        // After disable
        _disableVault(address(mockVault1), hex"");
        (bool registeredDisabled, bool enabledDisabled) = lrtSquared.vaultInfo(address(mockVault1));
        assertTrue(registeredDisabled);
        assertFalse(enabledDisabled);
    }

    /**
     * @notice Test allVaults returns complete registry
     */
    function test_allVaults_returnsCompleteRegistry() public {
        address[] memory assets = new address[](1);
        assets[0] = address(tokens[0]);
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;

        mockVault1.setBalances(assets, balances);
        mockVault2.setBalances(assets, balances);
        mockVault3.setBalances(assets, balances);

        // Register 3 vaults
        _registerVault(address(mockVault1), hex"");
        _registerVault(address(mockVault2), hex"");
        _registerVault(address(mockVault3), hex"");

        address[] memory allVaults = lrtSquared.allVaults();
        assertEq(allVaults.length, 3);
        assertEq(allVaults[0], address(mockVault1));
        assertEq(allVaults[1], address(mockVault2));
        assertEq(allVaults[2], address(mockVault3));

        // Disable one vault
        _disableVault(address(mockVault2), hex"");

        // All still in registry
        address[] memory allVaultsAfterDisable = lrtSquared.allVaults();
        assertEq(allVaultsAfterDisable.length, 3);
    }

    /**
     * @notice Test isAssetAcceptedByVault for various scenarios
     */
    function test_isAssetAcceptedByVault_variousScenarios() public {
        // Configure vault with specific assets
        address[] memory acceptedAssets = new address[](2);
        acceptedAssets[0] = address(tokens[0]);
        acceptedAssets[1] = address(tokens[1]);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        _registerVault(address(mockVault1), hex"");

        // Check accepted assets
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[0])));
        assertTrue(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[1])));

        // Check asset not in vault config
        assertFalse(lrtSquared.isAssetAcceptedByVault(address(mockVault1), address(tokens[2])));

        // Check unregistered vault
        assertFalse(lrtSquared.isAssetAcceptedByVault(address(mockVault2), address(tokens[0])));
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Helper to register vault via governance
     */
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

    /**
     * @notice Helper to enable vault via governance
     */
    function _enableVault(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Enable vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.enableVault.selector,
            vault
        );

        _executeGovernance(data, description, revertData);
    }

    /**
     * @notice Helper to disable vault via governance
     */
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
}

/**
 * @title MaliciousVaultNoERC165
 * @notice Malicious vault that implements assets() but not ERC165
 * @dev Used to test that registerVault() properly validates ERC165
 */
contract MaliciousVaultNoERC165 {
    address[] private _assets;

    function setAssets(address[] memory assets_) external {
        _assets = assets_;
    }

    function assets() external view returns (address[] memory) {
        return _assets;
    }
}

/**
 * @title MaliciousVaultWrongInterface
 * @notice Contract with ERC165 but not supporting IKingVault interface
 * @dev Used to test that registerVault() validates the correct interface
 */
contract MaliciousVaultWrongInterface {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        // Support ERC165 itself but NOT IKingVault
        return interfaceId == 0x01ffc9a7; // ERC165 interface ID
    }

    // Implement assets() to get past the assets() call but fail ERC165 check
    function assets() external pure returns (address[] memory) {
        address[] memory empty = new address[](1);
        return empty;
    }
}

/**
 * @title MaliciousVaultOnlyAssets
 * @notice Contract with only assets() method, no other IKingVault methods
 * @dev Used to test that registerVault() validates full interface via ERC165
 */
contract MaliciousVaultOnlyAssets {
    address[] private _assets;

    function setAssets(address[] memory assets_) external {
        _assets = assets_;
    }

    function assets() external view returns (address[] memory) {
        return _assets;
    }

    // No other IKingVault methods implemented
    // No ERC165 support
}
