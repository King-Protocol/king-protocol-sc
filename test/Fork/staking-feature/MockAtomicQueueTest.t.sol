// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAtomicQueue {
    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }
    function updateAtomicRequest(address offer, address want, AtomicRequest calldata atomicRequest) external;
}

// Mock atomic queue that captures the parameters
contract MockAtomicQueue is IAtomicQueue {
    struct CapturedCall {
        address offer;
        address want;
        AtomicRequest request;
        bool wasCalled;
    }
    
    CapturedCall public lastCall;
    
    function updateAtomicRequest(address offer, address want, AtomicRequest calldata atomicRequest) external override {
        lastCall = CapturedCall({
            offer: offer,
            want: want,
            request: atomicRequest,
            wasCalled: true
        });
    }
    
    function getLastCall() external view returns (
        address offer,
        address want,
        uint64 deadline,
        uint88 atomicPrice,
        uint96 offerAmount,
        bool inSolve
    ) {
        require(lastCall.wasCalled, "No call captured");
        return (
            lastCall.offer,
            lastCall.want,
            lastCall.request.deadline,
            lastCall.request.atomicPrice,
            lastCall.request.offerAmount,
            lastCall.request.inSolve
        );
    }
}

// Example test showing how to use the mock
contract MockAtomicQueueTest is Test {
    MockAtomicQueue mockQueue;
    
    function setUp() public {
        mockQueue = new MockAtomicQueue();
    }
    
    function test_CaptureAtomicRequestParameters() public {
        // Example of how you could test with a mock queue
        address offer = address(0x1);
        address want = address(0x2);
        
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 10 days),
            atomicPrice: 1e18,
            offerAmount: 5e18,
            inSolve: false
        });
        
        // Call the mock
        mockQueue.updateAtomicRequest(offer, want, request);
        
        // Verify the captured parameters
        (
            address capturedOffer,
            address capturedWant,
            uint64 capturedDeadline,
            uint88 capturedPrice,
            uint96 capturedAmount,
            bool capturedInSolve
        ) = mockQueue.getLastCall();
        
        assertEq(capturedOffer, offer, "Offer token mismatch");
        assertEq(capturedWant, want, "Want token mismatch");
        assertEq(capturedDeadline, request.deadline, "Deadline mismatch");
        assertEq(capturedPrice, request.atomicPrice, "Atomic price mismatch");
        assertEq(capturedAmount, request.offerAmount, "Offer amount mismatch");
        assertEq(capturedInSolve, request.inSolve, "InSolve mismatch");
    }
}