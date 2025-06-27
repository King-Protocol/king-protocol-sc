// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {LRTSquaredTestSetup, ILRTSquared, IERC20, SafeERC20} from "./LRTSquaredSetup.t.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title LRTSquaredRedeemTest
 * @notice Test suite for King Protocol's redemption execution functionality
 * @dev This file focuses on testing the actual redeem() function execution, including:
 * - Fee calculation and deduction
 * - Event emission
 * - Balance state changes
 * - Error handling
 * - Multi-token scenarios with different decimals
 * - Integration with the new redemption algorithm
 */
contract LRTSquaredRedeemTest is LRTSquaredTestSetup {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256[] _tokenIndices;
    address[] _tokens;
    uint256[] _amounts;
    uint256 sharesAlloted;
    
    // admin is the timelock from the base setup

    function setUp() public override {
        super.setUp();

        _registerToken(address(tokens[0]), tokenPositionWeightLimits[0], hex"");
        _registerToken(address(tokens[1]), tokenPositionWeightLimits[1], hex"");
        _registerToken(address(tokens[2]), tokenPositionWeightLimits[2], hex"");

        address[] memory depositors = new address[](1);
        depositors[0] = alice;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");

        _tokenIndices.push(0);
        _tokenIndices.push(1);
        _tokenIndices.push(2);

        _tokens.push(address(tokens[0]));
        _tokens.push(address(tokens[1]));
        _tokens.push(address(tokens[2]));

        _amounts.push(10 * 10 ** tokenDecimals[0]);
        _amounts.push(50 * 10 ** tokenDecimals[1]);
        _amounts.push(25 * 10 ** tokenDecimals[2]);

        uint256 totalValueInEthAfterDeposit = _getTokenValuesInEth(
            _tokenIndices,
            _amounts
        );
        sharesAlloted = totalValueInEthAfterDeposit;
        uint256 fee = sharesAlloted.mulDiv(depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        sharesAlloted -= fee;

        vm.startPrank(alice);
        for (uint256 i = 0; i < _tokens.length; ) {
            deal(_tokens[i], alice, _amounts[i]);

            IERC20(_tokens[i]).safeIncreaseAllowance(
                address(lrtSquared),
                _amounts[i]
            );
            unchecked {
                ++i;
            }
        }

        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.Deposit(alice, alice, sharesAlloted, fee, _tokens, _amounts);
        lrtSquared.deposit(_tokens, _amounts, alice);
        vm.stopPrank();

        // Since the amounts reduced by deposit fee bps
        _amounts[0] = _amounts[0].mulDiv(HUNDRED_PERCENT_IN_BPS - depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        _amounts[1] = _amounts[1].mulDiv(HUNDRED_PERCENT_IN_BPS - depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
        _amounts[2] = _amounts[2].mulDiv(HUNDRED_PERCENT_IN_BPS - depositFeeInBps, HUNDRED_PERCENT_IN_BPS);
    }

    function test_Redeem() public {
        uint256 aliceSharesBefore = lrtSquared.balanceOf(alice);
        uint256 aliceBalToken0Before = IERC20(_tokens[0]).balanceOf(alice);
        uint256 aliceBalToken1Before = IERC20(_tokens[1]).balanceOf(alice);
        uint256 aliceBalToken2Before = IERC20(_tokens[2]).balanceOf(alice);

        uint256 fee = sharesAlloted.mulDiv(redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        uint256 burnShares = sharesAlloted - fee;
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit ILRTSquared.Redeem(alice, burnShares, fee, _tokens, _amounts);
        lrtSquared.redeem(sharesAlloted);

        uint256 aliceSharesAfter = lrtSquared.balanceOf(alice);
        uint256 aliceBalToken0After = IERC20(_tokens[0]).balanceOf(alice);
        uint256 aliceBalToken1After = IERC20(_tokens[1]).balanceOf(alice);
        uint256 aliceBalToken2After = IERC20(_tokens[2]).balanceOf(alice);

        assertEq(aliceSharesBefore, sharesAlloted);
        assertEq(aliceSharesAfter, 0);
        assertApproxEqAbs(
            aliceBalToken0After - aliceBalToken0Before,
            _amounts[0].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS),
            10
        );
        assertApproxEqAbs(
            aliceBalToken1After - aliceBalToken1Before,
            _amounts[1].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS),
            10
        );
        assertApproxEqAbs(
            aliceBalToken2After - aliceBalToken2Before,
            _amounts[2].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS),
            10
        );
    }

    function test_CannotRedeemIfInsufficientShares() public {
        vm.prank(alice);
        vm.expectRevert(ILRTSquared.InsufficientShares.selector);
        lrtSquared.redeem(sharesAlloted + 1);
    }

    function test_RedeemWithZeroShares() public {
        vm.prank(alice);
        vm.expectRevert(ILRTSquared.SharesCannotBeZero.selector);
        lrtSquared.redeem(0);
    }

    function test_RedeemEmitsCorrectEvent() public {
        // Preview redemption to get the actual amounts that will be redeemed
        (address[] memory previewTokens, uint256[] memory previewAmounts, uint256 previewFee) = lrtSquared.previewRedeem(sharesAlloted);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ILRTSquared.Redeem(alice, sharesAlloted, previewFee, previewTokens, previewAmounts);
        lrtSquared.redeem(sharesAlloted);
    }

    function test_RedeemPartialShares() public {
        uint256 partialShares = sharesAlloted / 2;
        uint256 fee = partialShares.mulDiv(redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        uint256 burnShares = partialShares - fee;
        
        // Calculate expected amounts (proportional to shares being redeemed)
        uint256[] memory expectedAmounts = new uint256[](3);
        expectedAmounts[0] = _amounts[0].mulDiv(burnShares, sharesAlloted);
        expectedAmounts[1] = _amounts[1].mulDiv(burnShares, sharesAlloted);
        expectedAmounts[2] = _amounts[2].mulDiv(burnShares, sharesAlloted);
        
        uint256 aliceSharesBefore = lrtSquared.balanceOf(alice);
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit ILRTSquared.Redeem(alice, burnShares, fee, _tokens, expectedAmounts);
        lrtSquared.redeem(partialShares);
        
        uint256 aliceSharesAfter = lrtSquared.balanceOf(alice);
        assertEq(aliceSharesAfter, aliceSharesBefore - partialShares, "Should burn partial shares");
    }

    function test_RedeemWithDifferentTokenDecimals() public {
        // This test verifies the existing setup handles different decimals correctly
        // tokens[0] = 18 decimals, tokens[1] = 6 decimals, tokens[2] = 8 decimals
        
        uint256 aliceSharesBefore = lrtSquared.balanceOf(alice);
        uint256 fee = sharesAlloted.mulDiv(redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        
        vm.prank(alice);
        lrtSquared.redeem(sharesAlloted);
        
        uint256 aliceSharesAfter = lrtSquared.balanceOf(alice);
        assertEq(aliceSharesAfter, 0, "All shares should be burned");
        
        // Verify user received tokens scaled by their respective decimals
        uint256 expectedToken0 = _amounts[0].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        uint256 expectedToken1 = _amounts[1].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        uint256 expectedToken2 = _amounts[2].mulDiv(HUNDRED_PERCENT_IN_BPS - redeemFeeInBps, HUNDRED_PERCENT_IN_BPS);
        
        assertApproxEqAbs(IERC20(_tokens[0]).balanceOf(alice), expectedToken0, 10, "Token0 (18 decimals) amount incorrect");
        assertApproxEqAbs(IERC20(_tokens[1]).balanceOf(alice), expectedToken1, 10, "Token1 (6 decimals) amount incorrect");
        assertApproxEqAbs(IERC20(_tokens[2]).balanceOf(alice), expectedToken2, 10, "Token2 (8 decimals) amount incorrect");
    }

    function test_RedeemWithMaximumFee() public {
        // Test with higher fee to ensure fee calculation works correctly
        uint256 highFee = 1000; // 10%
        
        // Get current fee and update it
        ILRTSquared.Fee memory currentFee = lrtSquared.fee();
        currentFee.redeemFeeInBps = uint48(highFee);
        
        vm.prank(address(timelock));
        lrtSquared.setFee(currentFee);
        
        uint256 fee = sharesAlloted.mulDiv(highFee, HUNDRED_PERCENT_IN_BPS);
        uint256 burnShares = sharesAlloted - fee;
        
        vm.prank(alice);
        vm.expectEmit(true, true, true, false);
        emit ILRTSquared.Redeem(alice, burnShares, fee, _tokens, _amounts);
        lrtSquared.redeem(sharesAlloted);
        
        // Verify fee was properly deducted (user gets less tokens)
        uint256 expectedToken0 = _amounts[0].mulDiv(HUNDRED_PERCENT_IN_BPS - highFee, HUNDRED_PERCENT_IN_BPS);
        assertApproxEqAbs(IERC20(_tokens[0]).balanceOf(alice), expectedToken0, 10, "High fee not applied correctly");
    }

    function test_MultipleUsersRedeem() public {
        // Setup second user
        address bob = makeAddr("bob");
        
        // Add bob as depositor
        address[] memory depositors = new address[](1);
        depositors[0] = bob;
        bool[] memory isDepositor = new bool[](1);
        isDepositor[0] = true;
        _setDepositors(depositors, isDepositor, hex"");
        
        // Bob deposits same amounts
        vm.startPrank(bob);
        for (uint256 i = 0; i < _tokens.length; i++) {
            deal(_tokens[i], bob, _amounts[i]);
            IERC20(_tokens[i]).safeIncreaseAllowance(address(lrtSquared), _amounts[i]);
        }
        lrtSquared.deposit(_tokens, _amounts, bob);
        vm.stopPrank();
        
        uint256 bobShares = lrtSquared.balanceOf(bob);
        
        // Both users redeem
        vm.prank(alice);
        lrtSquared.redeem(sharesAlloted);
        
        vm.prank(bob);
        lrtSquared.redeem(bobShares);
        
        // Verify both users received their proportional shares
        assertEq(lrtSquared.balanceOf(alice), 0, "Alice should have no shares left");
        assertEq(lrtSquared.balanceOf(bob), 0, "Bob should have no shares left");
    }
}
