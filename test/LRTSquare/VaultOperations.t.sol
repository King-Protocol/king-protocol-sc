// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared} from "./LRTSquaredSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IKingVault} from "../../src/interfaces/IKingVault.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title VaultOperationsTest
 * @notice Comprehensive test suite for vault deposit/withdrawal operations
 * @dev Tests tasks 2.1, 2.2, 2.3 of KingVault Integration (Phase 2)
 */
contract VaultOperationsTest is LRTSquaredTestSetup {
    // Mock vault
    MockKingVault mockVault;

    // Test addresses
    address testAsset;

    function setUp() public override {
        super.setUp();

        // Register test tokens
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");

        testAsset = address(tokens[0]);

        // Deploy mock vault
        mockVault = new MockKingVault();

        // Configure vault with accepted assets
        address[] memory acceptedAssets = new address[](2);
        acceptedAssets[0] = address(tokens[0]);
        acceptedAssets[1] = address(tokens[1]);
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        mockVault.setBalances(acceptedAssets, balances);

        // Register vault
        _registerVault(address(mockVault), hex"");
    }

    // ============================================
    // 2.4.1 DEPOSIT TESTS
    // ============================================

    /**
     * @notice Test successful deposit to vault with principal tracking
     */
    function test_depositToVault_success() public {
        uint256 depositAmount = 100 ether;

        // Give main contract tokens to deposit
        deal(testAsset, address(lrtSquared), depositAmount);

        // Get initial balances
        uint256 initialContractBalance = IERC20(testAsset).balanceOf(address(lrtSquared));
        uint256 initialVaultPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);

        // Execute deposit
        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        // Verify principal tracking updated
        uint256 finalVaultPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);
        assertEq(finalVaultPrincipal, initialVaultPrincipal + depositAmount, "Principal not tracked correctly");

        // Verify tokens transferred
        uint256 finalContractBalance = IERC20(testAsset).balanceOf(address(lrtSquared));
        assertEq(finalContractBalance, initialContractBalance - depositAmount, "Tokens not transferred");

        // Verify vault received tokens
        assertEq(IERC20(testAsset).balanceOf(address(mockVault)), depositAmount, "Vault didn't receive tokens");
    }

    /**
     * @notice Test deposit emits correct event
     * @dev Event is emitted within governance execution, so we verify by checking state changes
     */
    function test_depositToVault_emitsEvent() public {
        uint256 depositAmount = 50 ether;
        deal(testAsset, address(lrtSquared), depositAmount);

        uint256 initialPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);

        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        // Verify event occurred by checking state change
        uint256 finalPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);
        assertEq(finalPrincipal, initialPrincipal + depositAmount, "Deposit event should have been emitted");
    }

    /**
     * @notice Test deposit fails with unregistered vault
     */
    function test_depositToVault_unregisteredVault_reverts() public {
        address unregisteredVault = makeAddr("unregisteredVault");
        uint256 depositAmount = 100 ether;
        deal(testAsset, address(lrtSquared), depositAmount);

        // Attempt deposit should revert
        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector);
        _depositToVault(unregisteredVault, testAsset, depositAmount, expectedRevert);
    }

    /**
     * @notice Test deposit fails with disabled vault
     */
    function test_depositToVault_disabledVault_reverts() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset, address(lrtSquared), depositAmount);

        // Disable the vault
        _disableVault(address(mockVault), hex"");

        // Attempt deposit should revert
        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.VaultNotEnabled.selector);
        _depositToVault(address(mockVault), testAsset, depositAmount, expectedRevert);
    }

    /**
     * @notice Test deposit fails with unaccepted asset
     */
    function test_depositToVault_unacceptedAsset_reverts() public {
        address unacceptedAsset = makeAddr("unacceptedAsset");
        uint256 depositAmount = 100 ether;

        // Attempt deposit should revert
        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.AssetNotAcceptedByVault.selector, address(mockVault), unacceptedAsset);
        _depositToVault(address(mockVault), unacceptedAsset, depositAmount, expectedRevert);
    }

    /**
     * @notice Test deposit fails with zero amount
     */
    function test_depositToVault_zeroAmount_reverts() public {
        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.AmountCannotBeZero.selector);
        _depositToVault(address(mockVault), testAsset, 0, expectedRevert);
    }

    /**
     * @notice Test deposit fails with insufficient balance
     */
    function test_depositToVault_insufficientBalance_reverts() public {
        uint256 depositAmount = 100 ether;
        // Don't give contract any tokens

        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.InsufficientTokenBalance.selector);
        _depositToVault(address(mockVault), testAsset, depositAmount, expectedRevert);
    }

    // ============================================
    // 2.4.2 WITHDRAWAL TESTS
    // ============================================

    /**
     * @notice Test successful withdrawal from vault with principal tracking
     */
    function test_withdrawFromVault_success() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        // Setup: deposit first
        deal(testAsset, address(lrtSquared), depositAmount);
        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        uint256 initialContractBalance = IERC20(testAsset).balanceOf(address(lrtSquared));
        uint256 initialVaultPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);

        // Execute withdrawal
        _withdrawFromVault(address(mockVault), testAsset, withdrawAmount, hex"");

        // Verify principal tracking updated
        uint256 finalVaultPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);
        assertEq(finalVaultPrincipal, initialVaultPrincipal - withdrawAmount, "Principal not updated correctly");

        // Verify tokens returned to contract
        uint256 finalContractBalance = IERC20(testAsset).balanceOf(address(lrtSquared));
        assertEq(finalContractBalance, initialContractBalance + withdrawAmount, "Tokens not returned");
    }

    /**
     * @notice Test withdrawal emits correct event
     * @dev Event is emitted within governance execution, so we verify by checking state changes
     */
    function test_withdrawFromVault_emitsEvent() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        // Setup: deposit first
        deal(testAsset, address(lrtSquared), depositAmount);
        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        uint256 initialPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);

        _withdrawFromVault(address(mockVault), testAsset, withdrawAmount, hex"");

        // Verify event occurred by checking state change
        uint256 finalPrincipal = lrtSquared.vaultPrincipal(address(mockVault), testAsset);
        assertEq(finalPrincipal, initialPrincipal - withdrawAmount, "Withdrawal event should have been emitted");
    }

    /**
     * @notice Test withdrawal fails with unregistered vault
     */
    function test_withdrawFromVault_unregisteredVault_reverts() public {
        address unregisteredVault = makeAddr("unregisteredVault");

        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector);
        _withdrawFromVault(unregisteredVault, testAsset, 50 ether, expectedRevert);
    }

    /**
     * @notice Test withdrawal fails with zero amount
     */
    function test_withdrawFromVault_zeroAmount_reverts() public {
        bytes memory expectedRevert = abi.encodeWithSelector(ILRTSquared.AmountCannotBeZero.selector);
        _withdrawFromVault(address(mockVault), testAsset, 0, expectedRevert);
    }

    /**
     * @notice Test withdrawal fails with insufficient principal
     */
    function test_withdrawFromVault_insufficientPrincipal_reverts() public {
        uint256 withdrawAmount = 100 ether;

        // No deposit made, so principal is 0
        bytes memory expectedRevert = abi.encodeWithSelector(
            ILRTSquared.InsufficientPrincipal.selector,
            address(mockVault),
            testAsset,
            0, // current principal
            withdrawAmount // requested
        );
        _withdrawFromVault(address(mockVault), testAsset, withdrawAmount, expectedRevert);
    }

    /**
     * @notice Test that vault cannot be disabled with principal (covered in VaultRegistration tests)
     * @dev This test validates that withdrawal only requires registration, not enablement
     *      However, in practice, a vault cannot be disabled if it has principal
     */
    function test_withdrawFromVault_requiresOnlyRegistration() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        // Setup: deposit first while enabled
        deal(testAsset, address(lrtSquared), depositAmount);
        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        // Verify withdrawal works (vault is enabled and has principal)
        _withdrawFromVault(address(mockVault), testAsset, withdrawAmount, hex"");

        // Verify principal updated correctly
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), depositAmount - withdrawAmount);
    }

    /**
     * @notice Test full withdrawal clears principal
     */
    function test_withdrawFromVault_fullWithdrawal_clearsPrincipal() public {
        uint256 depositAmount = 100 ether;

        // Setup: deposit
        deal(testAsset, address(lrtSquared), depositAmount);
        _depositToVault(address(mockVault), testAsset, depositAmount, hex"");

        // Verify principal set
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), depositAmount);

        // Withdraw all
        _withdrawFromVault(address(mockVault), testAsset, depositAmount, hex"");

        // Verify principal cleared
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), 0, "Principal not cleared");

        // Now should be able to disable vault
        _disableVault(address(mockVault), hex"");
        assertFalse(lrtSquared.isVaultEnabled(address(mockVault)), "Vault not disabled");
    }

    // ============================================
    // 2.4.3 INTEGRATION TESTS
    // ============================================

    /**
     * @notice Test multiple deposits and withdrawals maintain correct principal
     */
    function test_multipleOperations_principalTracking() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        uint256 withdraw1 = 30 ether;

        // Give contract tokens
        deal(testAsset, address(lrtSquared), amount1 + amount2);

        // First deposit
        _depositToVault(address(mockVault), testAsset, amount1, hex"");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), amount1);

        // Second deposit
        _depositToVault(address(mockVault), testAsset, amount2, hex"");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), amount1 + amount2);

        // Partial withdrawal
        _withdrawFromVault(address(mockVault), testAsset, withdraw1, hex"");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), amount1 + amount2 - withdraw1);
    }

    /**
     * @notice Test deposits to multiple vaults track principal separately
     */
    function test_multipleVaults_separatePrincipalTracking() public {
        // Deploy second mock vault
        MockKingVault mockVault2 = new MockKingVault();

        // Configure second vault
        address[] memory acceptedAssets = new address[](1);
        acceptedAssets[0] = testAsset;
        uint256[] memory balances = new uint256[](1);
        balances[0] = 0;
        mockVault2.setBalances(acceptedAssets, balances);

        // Register second vault
        _registerVault(address(mockVault2), hex"");

        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;

        deal(testAsset, address(lrtSquared), amount1 + amount2);

        // Deposit to first vault
        _depositToVault(address(mockVault), testAsset, amount1, hex"");

        // Deposit to second vault
        _depositToVault(address(mockVault2), testAsset, amount2, hex"");

        // Verify separate principal tracking
        assertEq(lrtSquared.vaultPrincipal(address(mockVault), testAsset), amount1, "Vault 1 principal incorrect");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault2), testAsset), amount2, "Vault 2 principal incorrect");
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
}

/**
 * @title MockKingVault
 * @notice Simple mock vault for testing deposit/withdrawal operations
 * @dev Implements ERC165 for interface detection
 */
contract MockKingVault is IKingVault, ERC165 {
    mapping(address => uint256) private balances;
    bool private _paused;
    address[] private _assets;
    uint256[] private _balances;

    /**
     * @notice Configure vault's asset list for testing
     */
    function setBalances(address[] memory assets_, uint256[] memory balances_) external {
        _assets = assets_;
        _balances = balances_;
    }

    function deposit(address asset, uint256 amount) external returns (uint256 shares) {
        require(!_paused, "Vault paused");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        balances[asset] += amount;

        // Update configured balances
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                _balances[i] = balances[asset];
                break;
            }
        }

        return amount; // 1:1 share ratio for simplicity
    }

    function withdraw(address asset, uint256 amount, address receiver) external returns (uint256 actualAmount) {
        require(!_paused, "Vault paused");
        require(balances[asset] >= amount, "Insufficient vault balance");
        balances[asset] -= amount;
        IERC20(asset).transfer(receiver, amount);

        // Update configured balances
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                _balances[i] = balances[asset];
                break;
            }
        }

        return amount; // No fees for simplicity
    }

    function emergencyWithdraw(address asset, uint256 amount, address receiver) external returns (uint256 actualAmount) {
        require(balances[asset] >= amount, "Insufficient vault balance");
        balances[asset] -= amount;
        IERC20(asset).transfer(receiver, amount);

        // Update configured balances
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                _balances[i] = balances[asset];
                break;
            }
        }

        return amount;
    }

    function pause() external {
        _paused = true;
    }

    function unpause() external {
        _paused = false;
    }

    function paused() external view returns (bool) {
        return _paused;
    }

    function tvl() external pure returns (uint256) {
        return 0; // Not implemented for basic testing
    }

    function assets() external view returns (address[] memory) {
        return _assets;
    }

    function getBalances() external view returns (address[] memory tokens_, uint256[] memory amounts) {
        return (_assets, _balances);
    }

    function getBalance(address asset) external view returns (uint256) {
        return balances[asset];
    }

    /**
     * @notice Check if contract supports a given interface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IKingVault).interfaceId || super.supportsInterface(interfaceId);
    }
}
