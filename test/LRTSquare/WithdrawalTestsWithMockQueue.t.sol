// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockStrategy} from "../../src/mocks/MockStrategy.sol";
import {BoringVaultStrategyBase} from "../../src/strategies/BoringVaultStrategyBase.sol";
import {BaseStrategy} from "../../src/strategies/BaseStrategy.sol";

interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }
    function updateAtomicRequest(address offer, address want, AtomicRequest calldata atomicRequest) external;
}

contract MockAtomicQueue {
    address public lastOffer;
    address public lastWant;
    uint64 public lastDeadline;
    uint88 public lastAtomicPrice;
    uint96 public lastOfferAmount;
    bool public lastInSolve;
    bool public wasCalled;
    
    // Storage for user requests: user => offer => want => request
    mapping(address => mapping(address => mapping(address => IAtomicQueue.AtomicRequest))) public userRequests;
    
    function updateAtomicRequest(address offer, address want, IAtomicQueue.AtomicRequest calldata atomicRequest) external {
        lastOffer = offer;
        lastWant = want;
        lastDeadline = atomicRequest.deadline;
        lastAtomicPrice = atomicRequest.atomicPrice;
        lastOfferAmount = atomicRequest.offerAmount;
        lastInSolve = atomicRequest.inSolve;
        wasCalled = true;
        
        // Store the request for getUserAtomicRequest
        userRequests[msg.sender][offer][want] = atomicRequest;
    }
    
    function getUserAtomicRequest(address user, address offer, address want) external view returns (IAtomicQueue.AtomicRequest memory) {
        return userRequests[user][offer][want];
    }
}

contract TestableBoringStrategy is BoringVaultStrategyBase {
    address immutable boringVault;
    address immutable withdrawalQueue;
    address immutable stakedToken;
    address immutable nativeToken;
    
    constructor(
        address _vault,
        address _priceProvider,
        address _boringVault,
        address _withdrawalQueue,
        address _stakedToken,
        address _nativeToken
    ) BoringVaultStrategyBase(_vault, _priceProvider) {
        boringVault = _boringVault;
        withdrawalQueue = _withdrawalQueue;
        stakedToken = _stakedToken;
        nativeToken = _nativeToken;
    }
    
    function returnToken() external view override returns (address) {
        return stakedToken;
    }
    
    function getBoringVault() public view override returns (address) {
        return boringVault;
    }
    
    function getWithdrawalQueue() public view override returns (address) {
        return withdrawalQueue;
    }
    
    function token() public view override returns (address) {
        return nativeToken;
    }
    
    // Override _calculateAtomicPrice to avoid external calls
    function _calculateAtomicPrice() internal pure override returns (uint256) {
        return 1e18; // 1:1 ratio for testing
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract WithdrawalTestsWithMockQueue is Test {
    MockAtomicQueue mockQueue;
    TestableBoringStrategy strategy;
    MockERC20 stakedToken;
    MockERC20 nativeToken;
    address vault = address(0x1234);
    address priceProvider = address(0x5678);
    address boringVault = address(0x9999);
    
    function setUp() public {
        mockQueue = new MockAtomicQueue();
        stakedToken = new MockERC20("Staked Token", "STK");
        nativeToken = new MockERC20("Native Token", "NTV");
        
        strategy = new TestableBoringStrategy(
            vault,
            priceProvider,
            boringVault,
            address(mockQueue),
            address(stakedToken),
            address(nativeToken)
        );
        
        // Mint some tokens to the vault for testing
        stakedToken.mint(vault, 10000e18);
    }
    
    function test_InitiateWithdrawal_CallsAtomicQueueWithCorrectParameters() public {
        uint256 withdrawalAmount = 5e18;
        
        vm.prank(vault);
        strategy.initiateWithdrawal(withdrawalAmount);
        
        assertTrue(mockQueue.wasCalled(), "updateAtomicRequest should have been called");
        assertEq(mockQueue.lastOffer(), address(stakedToken), "Offer token should be staked token");
        assertEq(mockQueue.lastWant(), address(nativeToken), "Want token should be native token");
        assertEq(mockQueue.lastOfferAmount(), withdrawalAmount, "Offer amount should match withdrawal amount");
        assertEq(mockQueue.lastDeadline(), block.timestamp + 10 days, "Deadline should be 10 days from now");
        assertFalse(mockQueue.lastInSolve(), "inSolve should be false");
        
        // Our test strategy returns 1e18 for atomic price (1:1 ratio)
        assertEq(mockQueue.lastAtomicPrice(), 1e18, "Atomic price should be 1:1 for test");
    }
    
    function test_InitiateWithdrawal_RejectsExistingRequest() public {
        // First withdrawal should succeed
        vm.prank(vault);
        strategy.initiateWithdrawal(1e18);
        assertTrue(mockQueue.wasCalled(), "First request should succeed");
        
        // Check that the request was actually stored (by the strategy address since it's calling updateAtomicRequest)
        IAtomicQueue.AtomicRequest memory storedRequest = mockQueue.getUserAtomicRequest(
            address(strategy), // The strategy is the one calling updateAtomicRequest
            address(stakedToken), 
            address(nativeToken)
        );
        assertEq(storedRequest.offerAmount, 1e18, "Request should be stored with correct amount");
        
        // Second withdrawal should be rejected because there's already an active request
        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSignature("ExistingWithdrawalRequestActive()"));
        strategy.initiateWithdrawal(5e17);
    }
    
    function test_CancelWithdrawal() public {
        // First create a withdrawal request
        vm.prank(vault);
        strategy.initiateWithdrawal(1e18);
        assertTrue(mockQueue.wasCalled(), "Initial request should succeed");
        assertEq(mockQueue.lastOfferAmount(), 1e18, "Offer amount should be 1e18");
        
        // Cancel the withdrawal
        vm.prank(vault);
        strategy.cancelWithdrawal();
        assertEq(mockQueue.lastOfferAmount(), 0, "After cancellation, offer amount should be 0");
        assertEq(mockQueue.lastDeadline(), 0, "After cancellation, deadline should be 0");
        assertEq(mockQueue.lastAtomicPrice(), 0, "After cancellation, atomic price should be 0");
    }
    
    function test_WorkflowAfterCancellation() public {
        // Create initial request
        vm.prank(vault);
        strategy.initiateWithdrawal(1e18);
        
        // Cancel it
        vm.prank(vault);
        strategy.cancelWithdrawal();
        assertEq(mockQueue.lastOfferAmount(), 0, "Request should be cancelled");
        
        // Should be able to create new request after cancellation
        vm.prank(vault);
        strategy.initiateWithdrawal(5e17);
        assertEq(mockQueue.lastOfferAmount(), 5e17, "New request should succeed");
    }
    
    function test_InitiateWithdrawal_InvalidAmount() public {
        vm.prank(vault);
        vm.expectRevert(bytes("Invalid amount"));
        strategy.initiateWithdrawal(0);
        
        vm.prank(vault);
        vm.expectRevert(bytes("Invalid amount"));
        strategy.initiateWithdrawal(type(uint256).max);
    }
}