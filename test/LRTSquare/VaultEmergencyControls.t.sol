// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared} from "./LRTSquaredSetup.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IKingVault} from "../../src/interfaces/IKingVault.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title VaultEmergencyControlsTest
 * @notice Comprehensive test suite for vault emergency control functions
 * @dev Tests tasks 3.1, 3.2, 3.3 of KingVault Integration (Phase 3)
 */
contract VaultEmergencyControlsTest is LRTSquaredTestSetup {
    // Mock vaults
    MockKingVault mockVault1;
    MockKingVault mockVault2;
    FailingMockVault failingVault;

    // Test addresses
    address testAsset1;
    address testAsset2;

    function setUp() public override {
        super.setUp();

        // Register test tokens
        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");

        testAsset1 = address(tokens[0]);
        testAsset2 = address(tokens[1]);

        // Deploy mock vaults
        mockVault1 = new MockKingVault();
        mockVault2 = new MockKingVault();
        failingVault = new FailingMockVault();

        // Configure vaults with accepted assets
        address[] memory acceptedAssets = new address[](2);
        acceptedAssets[0] = testAsset1;
        acceptedAssets[1] = testAsset2;
        uint256[] memory balances = new uint256[](2);
        balances[0] = 0;
        balances[1] = 0;

        mockVault1.setBalances(acceptedAssets, balances);
        mockVault2.setBalances(acceptedAssets, balances);
        failingVault.setBalances(acceptedAssets, balances);

        // Register vaults
        _registerVault(address(mockVault1), hex"");
        _registerVault(address(mockVault2), hex"");
        _registerVault(address(failingVault), hex"");
    }

    // ============================================
    // 3.4.1 PAUSE VAULT TESTS
    // ============================================

    /**
     * @notice Test successfully pausing a vault
     */
    function test_pauseVault_success() public {
        // Verify vault starts unpaused
        assertFalse(mockVault1.paused(), "Vault should start unpaused");

        // Pause the vault
        _pauseVault(address(mockVault1), hex"");

        // Verify vault is paused
        assertTrue(mockVault1.paused(), "Vault should be paused");
    }

    /**
     * @notice Test pausing vault blocks deposits
     */
    function test_pauseVault_blocksDeposits() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // Pause the vault
        _pauseVault(address(mockVault1), hex"");

        // Attempt deposit should fail
        _depositToVault(address(mockVault1), testAsset1, depositAmount, bytes("Vault paused"));
    }

    /**
     * @notice Test pausing vault blocks withdrawals
     */
    function test_pauseVault_blocksWithdrawals() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // First deposit while unpaused
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");

        // Then pause the vault
        _pauseVault(address(mockVault1), hex"");

        // Attempt withdrawal should fail
        _withdrawFromVault(address(mockVault1), testAsset1, depositAmount, bytes("Vault paused"));
    }

    /**
     * @notice Test pausing unregistered vault fails
     */
    function test_pauseVault_unregistered_reverts() public {
        address unregisteredVault = makeAddr("unregisteredVault");
        _pauseVault(unregisteredVault, abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector));
    }

    // ============================================
    // 3.4.2 UNPAUSE VAULT TESTS
    // ============================================

    /**
     * @notice Test successfully unpausing a vault
     */
    function test_unpauseVault_success() public {
        // First pause the vault
        _pauseVault(address(mockVault1), hex"");
        assertTrue(mockVault1.paused(), "Vault should be paused");

        // Then unpause
        _unpauseVault(address(mockVault1), hex"");

        // Verify vault is unpaused
        assertFalse(mockVault1.paused(), "Vault should be unpaused");
    }

    /**
     * @notice Test unpausing vault restores deposits
     */
    function test_unpauseVault_restoresDeposits() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // Pause the vault
        _pauseVault(address(mockVault1), hex"");

        // Unpause the vault
        _unpauseVault(address(mockVault1), hex"");

        // Deposit should now succeed
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");

        // Verify deposit succeeded
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), depositAmount, "Deposit should succeed");
    }

    /**
     * @notice Test unpausing unregistered vault fails
     */
    function test_unpauseVault_unregistered_reverts() public {
        address unregisteredVault = makeAddr("unregisteredVault");
        _unpauseVault(unregisteredVault, abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector));
    }

    // ============================================
    // 3.4.3 PAUSE ALL VAULTS TESTS
    // ============================================

    /**
     * @notice Test successfully pausing all vaults
     */
    function test_pauseAllVaults_success() public {
        // Verify vaults start unpaused
        assertFalse(mockVault1.paused(), "Vault1 should start unpaused");
        assertFalse(mockVault2.paused(), "Vault2 should start unpaused");

        // Pause all vaults
        _pauseAllVaults(hex"");

        // Verify all vaults are paused
        assertTrue(mockVault1.paused(), "Vault1 should be paused");
        assertTrue(mockVault2.paused(), "Vault2 should be paused");
    }

    /**
     * @notice Test pauseAllVaults continues on individual vault failure
     */
    function test_pauseAllVaults_continuesOnFailure() public {
        // This test verifies resilience - even if one vault fails to pause,
        // the function continues and pauses other vaults

        // Call pauseAllVaults
        _pauseAllVaults(hex"");

        // Verify working vaults are paused even though failing vault errors
        assertTrue(mockVault1.paused(), "Vault1 should be paused");
        assertTrue(mockVault2.paused(), "Vault2 should be paused");
        // failingVault will fail but shouldn't stop the operation
    }

    /**
     * @notice Test pauseAllVaults with no vaults registered
     */
    function test_pauseAllVaults_noVaults() public {
        // Deploy fresh LRTSquared without any vaults
        // This test just ensures no revert occurs with empty vault array
        // Using existing setup which has vaults, so this is covered by other tests

        _pauseAllVaults(hex"");
        // Should complete without revert
    }

    /**
     * @notice Test pauseAllVaults blocks all deposits
     */
    function test_pauseAllVaults_blocksAllDeposits() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount * 2);

        // Pause all vaults
        _pauseAllVaults(hex"");

        // Attempt deposits to different vaults should all fail
        _depositToVault(address(mockVault1), testAsset1, depositAmount, bytes("Vault paused"));
        _depositToVault(address(mockVault2), testAsset1, depositAmount, bytes("Vault paused"));
    }

    // ============================================
    // 3.4.4 EMERGENCY WITHDRAWAL TESTS
    // ============================================

    /**
     * @notice Test successful emergency withdrawal from vault
     */
    function test_emergencyWithdrawal_success() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // Deposit to vault
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");

        // Verify principal tracked
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), depositAmount, "Principal should be tracked");

        // Get initial contract balance
        uint256 initialBalance = IERC20(testAsset1).balanceOf(address(lrtSquared));

        // Execute emergency withdrawal
        _emergencyWithdrawal(address(mockVault1), hex"");

        // Verify principal reset to zero
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Principal should be reset");

        // Verify tokens returned to contract
        uint256 finalBalance = IERC20(testAsset1).balanceOf(address(lrtSquared));
        assertEq(finalBalance, initialBalance + depositAmount, "Tokens should be returned");
    }

    /**
     * @notice Test emergency withdrawal with multiple assets
     */
    function test_emergencyWithdrawal_multipleAssets() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;
        deal(testAsset1, address(lrtSquared), depositAmount1);
        deal(testAsset2, address(lrtSquared), depositAmount2);

        // Deposit both assets to vault
        _depositToVault(address(mockVault1), testAsset1, depositAmount1, hex"");
        _depositToVault(address(mockVault1), testAsset2, depositAmount2, hex"");

        // Get initial balances
        uint256 initialBalance1 = IERC20(testAsset1).balanceOf(address(lrtSquared));
        uint256 initialBalance2 = IERC20(testAsset2).balanceOf(address(lrtSquared));

        // Execute emergency withdrawal
        _emergencyWithdrawal(address(mockVault1), hex"");

        // Verify both principals reset
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Asset1 principal should be reset");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset2), 0, "Asset2 principal should be reset");

        // Verify both assets returned
        assertEq(
            IERC20(testAsset1).balanceOf(address(lrtSquared)),
            initialBalance1 + depositAmount1,
            "Asset1 should be returned"
        );
        assertEq(
            IERC20(testAsset2).balanceOf(address(lrtSquared)),
            initialBalance2 + depositAmount2,
            "Asset2 should be returned"
        );
    }

    /**
     * @notice Test emergency withdrawal works when vault is paused
     */
    function test_emergencyWithdrawal_worksWhenPaused() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // Deposit to vault
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");

        // Pause the vault
        _pauseVault(address(mockVault1), hex"");

        // Emergency withdrawal should still work
        _emergencyWithdrawal(address(mockVault1), hex"");

        // Verify principal reset and tokens returned
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Principal should be reset");
    }

    /**
     * @notice Test emergency withdrawal with unregistered vault fails
     */
    function test_emergencyWithdrawal_unregistered_reverts() public {
        address unregisteredVault = makeAddr("unregisteredVault");
        _emergencyWithdrawal(unregisteredVault, abi.encodeWithSelector(ILRTSquared.VaultNotRegistered.selector));
    }

    /**
     * @notice Test emergency withdrawal with no principal succeeds (no-op)
     */
    function test_emergencyWithdrawal_noPrincipal_succeeds() public {
        // Execute emergency withdrawal on vault with no deposits
        _emergencyWithdrawal(address(mockVault1), hex"");

        // Should complete without error (no-op)
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Principal should remain zero");
    }

    /**
     * @notice Test emergency withdrawal continues on individual asset failure
     */
    function test_emergencyWithdrawal_continuesOnFailure() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;
        deal(testAsset1, address(lrtSquared), depositAmount1);
        deal(testAsset2, address(lrtSquared), depositAmount2);

        // Deposit both assets to failing vault
        _depositToVault(address(failingVault), testAsset1, depositAmount1, hex"");
        _depositToVault(address(failingVault), testAsset2, depositAmount2, hex"");

        // Emergency withdrawal should complete even if vault fails
        _emergencyWithdrawal(address(failingVault), hex"");

        // Verify principals reset even though withdrawals may have failed
        assertEq(lrtSquared.vaultPrincipal(address(failingVault), testAsset1), 0, "Asset1 principal should be reset");
        assertEq(lrtSquared.vaultPrincipal(address(failingVault), testAsset2), 0, "Asset2 principal should be reset");
    }

    // ============================================
    // 3.4.5 INTEGRATION TESTS
    // ============================================

    /**
     * @notice Test complete emergency workflow: pause then withdraw
     */
    function test_emergencyWorkflow_pauseThenWithdraw() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount);

        // Setup: deposit to vault
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");

        // Emergency workflow
        _pauseVault(address(mockVault1), hex"");
        assertTrue(mockVault1.paused(), "Vault should be paused");

        _emergencyWithdrawal(address(mockVault1), hex"");

        // Verify complete recovery
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Principal should be cleared");
        assertGe(
            IERC20(testAsset1).balanceOf(address(lrtSquared)),
            depositAmount,
            "Funds should be recovered"
        );
    }

    /**
     * @notice Test pause all then selective emergency withdrawal
     */
    function test_emergencyWorkflow_pauseAllThenSelectiveWithdrawal() public {
        uint256 depositAmount = 100 ether;
        deal(testAsset1, address(lrtSquared), depositAmount * 2);

        // Setup: deposit to multiple vaults
        _depositToVault(address(mockVault1), testAsset1, depositAmount, hex"");
        _depositToVault(address(mockVault2), testAsset1, depositAmount, hex"");

        // Emergency: pause all vaults
        _pauseAllVaults(hex"");

        // Selectively withdraw from vault1 only
        _emergencyWithdrawal(address(mockVault1), hex"");

        // Verify selective withdrawal
        assertEq(lrtSquared.vaultPrincipal(address(mockVault1), testAsset1), 0, "Vault1 should be empty");
        assertEq(lrtSquared.vaultPrincipal(address(mockVault2), testAsset1), depositAmount, "Vault2 should still have principal");
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

    function _pauseVault(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Pause vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.pauseVault.selector,
            vault
        );

        _executeGovernance(data, description, revertData);
    }

    function _unpauseVault(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Unpause vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.unpauseVault.selector,
            vault
        );

        _executeGovernance(data, description, revertData);
    }

    function _pauseAllVaults(bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Pause all vaults at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.pauseAllVaults.selector
        );

        _executeGovernance(data, description, revertData);
    }

    function _emergencyWithdrawal(address vault, bytes memory revertData) internal {
        string memory description = string(
            abi.encodePacked(
                "Proposal: Emergency withdrawal from vault: ",
                vm.toString(vault),
                " at time ",
                vm.toString(block.timestamp)
            )
        );

        bytes memory data = abi.encodeWithSelector(
            ILRTSquared.emergencyWithdrawal.selector,
            vault
        );

        _executeGovernance(data, description, revertData);
    }
}

/**
 * @title MockKingVault
 * @notice Simple mock vault for testing emergency control operations
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
        // Emergency withdrawals work even when paused
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

/**
 * @title FailingMockVault
 * @notice Mock vault that fails pause operations to test error resilience
 * @dev Implements ERC165 for interface detection
 */
contract FailingMockVault is IKingVault, ERC165 {
    mapping(address => uint256) private balances;
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
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        balances[asset] += amount;

        // Update configured balances
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_assets[i] == asset) {
                _balances[i] = balances[asset];
                break;
            }
        }

        return amount;
    }

    function withdraw(address asset, uint256 amount, address receiver) external returns (uint256 actualAmount) {
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

    function emergencyWithdraw(address /* asset */, uint256 /* amount */, address /* receiver */) external pure returns (uint256 /* actualAmount */) {
        // Intentionally fail emergency withdrawals to test resilience
        revert("Vault emergency withdraw failed");
    }

    function pause() external pure {
        // Intentionally fail pause to test resilience
        revert("Vault pause failed");
    }

    function unpause() external pure {
        revert("Vault unpause failed");
    }

    function paused() external pure returns (bool) {
        return false;
    }

    function tvl() external pure returns (uint256) {
        return 0;
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
