// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {WStablsscs, IStablsscs} from "../src/wStablsscs.sol";

// Import the event for testing
import {WStablsscs as WStablsscsContract} from "../src/wStablsscs.sol";

// Interface for the real Stablsscs token on mainnet
interface _IStablsscs {
    function getScaledAmount(uint256 amount) external view returns (uint256);
    function getLiquidityAmount(uint256 shares) external view returns (uint256);
    function isBlackListed(address user) external view returns (bool);
    function paused() external view returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function addBlackList(address user) external;
    function removeBlackList(address user) external;
    function pause() external;
    function unpause() external;
    function issue(address account, uint256 amount) external;
    function destroyBlackFunds(address user) external;
}

contract WStablsscsForkTest is Test {
    WStablsscs public wStablsscs;
    _IStablsscs public stablsscs;

    // Real addresses on Ethereum mainnet
    address public constant Stablsscs_ADDRESS = 0x6fA0BE17e4beA2fCfA22ef89BF8ac9aab0AB0fc9;
    address public constant Stablsscs_OWNER = 0x7d2D47e441915Ff9C2D5A6E4A7AAdD5E02722e29;
    address public constant Stablsscs_COMPLIANCE = 0x760E226fE0767c5dB016Ef0e55A4Ac677aE869c0;

    // Test addresses
    address public user1 = address(0x111);
    address public user2 = address(0x222);
    address public user3 = address(0x333);

    // Test amounts
    uint256 public constant WRAP_AMOUNT = 1000 * 10**6; // 1000 Stablsscs tokens
    uint256 public constant UNWRAP_AMOUNT = 500 * 10**6; // 500 wStablsscs tokens

    function setUp() public {
        // Fork Ethereum mainnet
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/dEihJl038uP0z7xnJzjq7nYri_CES9pU", 23189769);

        // Get the real Stablsscs token
        stablsscs = _IStablsscs(Stablsscs_ADDRESS);

        // Deploy wStablsscs contract
        wStablsscs = new WStablsscs(IStablsscs(address(stablsscs)));

        // Fund test users with Stablsscs tokens
        // We'll need to impersonate the owner to transfer tokens
        vm.startPrank(Stablsscs_OWNER);
        stablsscs.unpause();
        stablsscs.issue(address(Stablsscs_OWNER), 1e30);
        stablsscs.transfer(user1, WRAP_AMOUNT * 2);
        stablsscs.transfer(user2, WRAP_AMOUNT * 2);
        stablsscs.transfer(user3, WRAP_AMOUNT * 2);
        vm.stopPrank();

        // Verify users have tokens
        assertGt(stablsscs.balanceOf(user1), 0, "User1 should have Stablsscs tokens");
        assertGt(stablsscs.balanceOf(user2), 0, "User2 should have Stablsscs tokens");
        assertGt(stablsscs.balanceOf(user3), 0, "User3 should have Stablsscs tokens");
    }

    function test_UnwrapWStablsscsToStablsscs() public {
        // First wrap some tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        uint256 wStablsscsReceived = wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        uint256 initialStablsscsBalance = stablsscs.balanceOf(user1);
        uint256 initialWStablsscsBalance = wStablsscs.balanceOf(user1);

        // Unwrap wStablsscs back to Stablsscs
        vm.startPrank(user1);
        uint256 stablsscsReceived = wStablsscs.unwrap(UNWRAP_AMOUNT);
        vm.stopPrank();

        // Verify balances
        assertGe(stablsscs.balanceOf(user1), initialStablsscsBalance + stablsscsReceived - 1, "Stablsscs balance should increase");
        assertEq(wStablsscs.balanceOf(user1), initialWStablsscsBalance - UNWRAP_AMOUNT, "wStablsscs balance should decrease");

        // Verify the conversion rate
        uint256 expectedStablsscs = stablsscs.getLiquidityAmount(UNWRAP_AMOUNT);
        assertEq(stablsscsReceived, expectedStablsscs, "Stablsscs amount should match getLiquidityAmount");
    }

    function test_TransferWStablsscsBetweenUsers() public {
        // User1 wraps some tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        uint256 transferAmount = 100 * 10**6; // 100 wStablsscs tokens
        uint256 user1InitialBalance = wStablsscs.balanceOf(user1);
        uint256 user2InitialBalance = wStablsscs.balanceOf(user2);

        // Transfer wStablsscs from user1 to user2
        vm.prank(user1);
        bool success = wStablsscs.transfer(user2, transferAmount);

        assertTrue(success, "Transfer should succeed");
        assertEq(wStablsscs.balanceOf(user1), user1InitialBalance - transferAmount, "User1 balance should decrease");
        assertEq(wStablsscs.balanceOf(user2), user2InitialBalance + transferAmount, "User2 balance should increase");
    }

    function test_TransferFromWStablsscs() public {
        // User1 wraps some tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        uint256 transferAmount = 100 * 10**6; // 100 wStablsscs tokens

        // User1 approves user2 to spend wStablsscs tokens
        vm.prank(user1);
        wStablsscs.approve(user2, transferAmount);

        uint256 user1InitialBalance = wStablsscs.balanceOf(user1);
        uint256 user3InitialBalance = wStablsscs.balanceOf(user3);

        // User2 transfers wStablsscs from user1 to user3
        vm.prank(user2);
        bool success = wStablsscs.transferFrom(user1, user3, transferAmount);

        assertTrue(success, "TransferFrom should succeed");
        assertEq(wStablsscs.balanceOf(user1), user1InitialBalance - transferAmount, "User1 balance should decrease");
        assertEq(wStablsscs.balanceOf(user3), user3InitialBalance + transferAmount, "User3 balance should increase");
    }

    function test_ViewFunctions() public {
        uint256 stablsscsAmount = 1000 * 10**6;
        uint256 wStablsscsAmount = 500 * 10**6;

        // Test getwStablsscsByStablsscs
        uint256 wStablsscsResult = wStablsscs.getwStablsscsByStablsscs(stablsscsAmount);
        uint256 expectedWStablsscs = stablsscs.getScaledAmount(stablsscsAmount);
        assertEq(wStablsscsResult, expectedWStablsscs, "getwStablsscsByStablsscs should return correct amount");

        // Test getStablsscsBywStablsscs
        uint256 stablsscsResult = wStablsscs.getStablsscsBywStablsscs(wStablsscsAmount);
        uint256 expectedStablsscs = stablsscs.getLiquidityAmount(wStablsscsAmount);
        assertEq(stablsscsResult, expectedStablsscs, "getStablsscsBywStablsscs should return correct amount");

        // Test StablsscsPerToken
        uint256 stablsscsPerToken = wStablsscs.StablsscsPerToken();
        uint256 expectedStablsscsPerToken = stablsscs.getLiquidityAmount(1e6);
        assertEq(stablsscsPerToken, expectedStablsscsPerToken, "StablsscsPerToken should return correct amount");

        // Test tokensPerStablsscs
        uint256 tokensPerStablsscs = wStablsscs.tokensPerStablsscs();
        uint256 expectedTokensPerStablsscs = stablsscs.getScaledAmount(1e6);
        assertEq(tokensPerStablsscs, expectedTokensPerStablsscs, "tokensPerStablsscs should return correct amount");
    }

    function test_Decimals() public {
        assertEq(wStablsscs.decimals(), 6, "wStablsscs should have 6 decimals");
    }

    function test_ZeroAmountWrap() public {
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), 1);

        vm.expectRevert("wStablsscs: can't wrap zero Stablsscs");
        wStablsscs.wrap(0);
        vm.stopPrank();
    }

    function test_ZeroAmountUnwrap() public {
        vm.startPrank(user1);
        vm.expectRevert("wStablsscs: zero amount unwrap not allowed");
        wStablsscs.unwrap(0);
        vm.stopPrank();
    }

    function test_StablsscsPausedBlocksWStablsscsOperations() public {
        // Impersonate Stablsscs owner and pause the contract
        vm.startPrank(Stablsscs_OWNER);
        stablsscs.pause();
        vm.stopPrank();

        // Verify Stablsscs is paused
        assertTrue(stablsscs.paused(), "Stablsscs should be paused");

        // Try to wrap Stablsscs - should fail
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);

        vm.expectRevert("protocol paused");
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Try to transfer wStablsscs - should fail
        vm.startPrank(user2);
        vm.expectRevert("protocol paused");
        wStablsscs.transfer(user3, 100 * 10**6);
        vm.stopPrank();

        // Try to transferFrom wStablsscs - should fail
        vm.startPrank(user2);
        vm.expectRevert("protocol paused");
        wStablsscs.transferFrom(user1, user3, 100 * 10**6);
        vm.stopPrank();

        // Unpause Stablsscs
        vm.startPrank(Stablsscs_OWNER);
        stablsscs.unpause();
        vm.stopPrank();

        // Verify Stablsscs is unpaused
        assertFalse(stablsscs.paused(), "Stablsscs should be unpaused");

        // Now operations should work
        vm.startPrank(user1);
        uint256 wStablsscsReceived = wStablsscs.wrap(WRAP_AMOUNT);
        assertGt(wStablsscsReceived, 0, "Wrap should work after unpause");
        vm.stopPrank();
    }

    function test_BlacklistedUserCannotTransfer() public {
        // First wrap some tokens for user1
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Impersonate Stablsscs owner and blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        vm.stopPrank();

        // Verify user1 is blacklisted
        assertTrue(stablsscs.isBlackListed(user1), "User1 should be blacklisted");

        // Try to transfer wStablsscs from blacklisted user - should fail
        vm.startPrank(user1);
        vm.expectRevert("User blacklisted");
        wStablsscs.transfer(user2, 100 * 10**6);
        vm.stopPrank();

        // Try to transfer wStablsscs to blacklisted user - should fail
        vm.startPrank(user2);
        vm.expectRevert("User blacklisted");
        wStablsscs.transfer(user1, 100 * 10**6);
        vm.stopPrank();

        // Try to transferFrom with blacklisted user - should fail
        vm.startPrank(user1);
        wStablsscs.approve(user2, 100 * 10**6);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("User blacklisted");
        wStablsscs.transferFrom(user1, user3, 100 * 10**6);
        vm.stopPrank();

        // Unblacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.removeBlackList(user1);
        vm.stopPrank();

        // Verify user1 is not blacklisted
        assertFalse(stablsscs.isBlackListed(user1), "User1 should not be blacklisted");

        // Now transfers should work
        vm.startPrank(user1);
        bool success = wStablsscs.transfer(user2, 100 * 10**6);
        assertTrue(success, "Transfer should work after unblacklist");
        vm.stopPrank();
    }

    function test_BlacklistedUserCannotWrap() public {
        // Impersonate Stablsscs owner and blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        vm.stopPrank();

        // Try to wrap Stablsscs - should fail
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);

        vm.expectRevert("User blacklisted");
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Unblacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.removeBlackList(user1);
        vm.stopPrank();

        // Now wrap should work
        vm.startPrank(user1);
        uint256 wStablsscsReceived = wStablsscs.wrap(WRAP_AMOUNT);
        assertGt(wStablsscsReceived, 0, "Wrap should work after unblacklist");
        vm.stopPrank();
    }

    function test_BlacklistedUserCannotUnwrap() public {
        // First wrap some tokens for user1
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Impersonate Stablsscs owner and blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        vm.stopPrank();

        // Try to unwrap wStablsscs - should fail
        vm.startPrank(user1);
        vm.expectRevert("User blacklisted");
        wStablsscs.unwrap(100 * 10**6);
        vm.stopPrank();

        // Unblacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.removeBlackList(user1);
        vm.stopPrank();

        // Now unwrap should work
        vm.startPrank(user1);
        uint256 stablsscsReceived = wStablsscs.unwrap(100 * 10**6);
        assertGt(stablsscsReceived, 0, "Unwrap should work after unblacklist");
        vm.stopPrank();
    }

    function test_IntegrationWithRealStablsscsToken() public {
        // Test that our wStablsscs contract correctly integrates with the real Stablsscs token

        // Check initial state
        assertFalse(stablsscs.paused(), "Stablsscs should not be paused initially");
        assertFalse(stablsscs.isBlackListed(user1), "User1 should not be blacklisted initially");

        // Test wrap and unwrap cycle
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);

        uint256 initialStablsscsBalance = stablsscs.balanceOf(user1);
        uint256 wStablsscsReceived = wStablsscs.wrap(WRAP_AMOUNT);

        // Unwrap back to Stablsscs
        uint256 stablsscsReceived = wStablsscs.unwrap(wStablsscsReceived);
        vm.stopPrank();

        // Verify the round trip (accounting for potential fees/slippage)
        assertApproxEqRel(
            stablsscs.balanceOf(user1),
            initialStablsscsBalance,
            0.01e18, // 1% tolerance
            "Round trip wrap/unwrap should preserve balance within 1%"
        );
    }

    function test_ReceiveFunction() public {
        // Test that the contract can receive ETH
        uint256 initialBalance = address(wStablsscs).balance;

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool success,) = address(wStablsscs).call{value: 0.5 ether}("");

        assertTrue(success, "Contract should receive ETH");
        assertEq(address(wStablsscs).balance, initialBalance + 0.5 ether, "Contract balance should increase");
    }

    // ========== destroyBlackFunds Tests ==========

    function test_DestroyBlackFundsSuccess() public {
        // User1 wraps some tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        uint256 user1WStablsscsBalance = wStablsscs.balanceOf(user1);
        assertGt(user1WStablsscsBalance, 0, "User1 should have wStablsscs tokens");

        // Blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.destroyBlackFunds(user1);
        vm.stopPrank();

        // Ensure user1 has no Stablsscs tokens (they were all wrapped)
        assertEq(stablsscs.balanceOf(user1), 0, "User1 should have no Stablsscs tokens");

        // Destroy black funds
        uint256 totalSupplyBefore = wStablsscs.totalSupply();
        vm.expectEmit(true, false, false, true);
        emit WStablsscsContract.DestroyedBlackFunds(user1, user1WStablsscsBalance);

        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);

        // Verify balances
        assertEq(wStablsscs.balanceOf(user1), 0, "User1 wStablsscs balance should be zero");
        assertEq(wStablsscs.totalSupply(), totalSupplyBefore - user1WStablsscsBalance, "Total supply should decrease");
    }

    function test_DestroyBlackFundsFailsWhenUserNotBlacklisted() public {
        // User1 wraps some tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Try to destroy funds for non-blacklisted user
        vm.expectRevert("user should be blacklisted");
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);
    }

    function test_DestroyBlackFundsWithZeroWStablsscsBalance() public {
        // Blacklist user1 without them having any wStablsscs tokens
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.destroyBlackFunds(user1);
        vm.stopPrank();

        // Ensure user1 has no Stablsscs tokens
        assertEq(stablsscs.balanceOf(user1), 0, "User1 should have no Stablsscs tokens");

        // Destroy black funds (should succeed even with zero balance)
        uint256 totalSupplyBefore = wStablsscs.totalSupply();
        vm.expectRevert("cannot destroy 0 black funds");
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);

        // Verify total supply remains the same
        assertEq(wStablsscs.totalSupply(), totalSupplyBefore, "Total supply should remain the same");
    }

    function test_DestroyBlackFundsMultipleUsers() public {
        // Multiple users wrap tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user2);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        vm.startPrank(user3);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Blacklist all users
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.addBlackList(user2);
        stablsscs.addBlackList(user3);
        stablsscs.destroyBlackFunds(user1);
        stablsscs.destroyBlackFunds(user2);
        stablsscs.destroyBlackFunds(user3);
        vm.stopPrank();

        uint256 totalSupplyBefore = wStablsscs.totalSupply();
        uint256 user1Balance = wStablsscs.balanceOf(user1);
        uint256 user2Balance = wStablsscs.balanceOf(user2);
        uint256 user3Balance = wStablsscs.balanceOf(user3);

        // Destroy black funds for all users
        vm.startPrank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);
        wStablsscs.destroyBlackFunds(user2);
        wStablsscs.destroyBlackFunds(user3);
        vm.stopPrank();

        // Verify all balances are zero
        assertEq(wStablsscs.balanceOf(user1), 0, "User1 balance should be zero");
        assertEq(wStablsscs.balanceOf(user2), 0, "User2 balance should be zero");
        assertEq(wStablsscs.balanceOf(user3), 0, "User3 balance should be zero");

        // Verify total supply decreased by the sum of all balances
        assertEq(wStablsscs.totalSupply(), totalSupplyBefore - user1Balance - user2Balance - user3Balance, "Total supply should decrease by all balances");
    }

    function test_DestroyBlackFundsAfterTransfer() public {
        // User1 wraps tokens and transfers some to user2
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        wStablsscs.transfer(user2, 100 * 10**6);
        vm.stopPrank();

        // Blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.destroyBlackFunds(user1);
        vm.stopPrank();

        // Destroy black funds for user1
        uint256 user1Balance = wStablsscs.balanceOf(user1);
        uint256 totalSupplyBefore = wStablsscs.totalSupply();
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);

        // Verify user1 balance is zero but user2 still has tokens
        assertEq(wStablsscs.balanceOf(user1), 0, "User1 balance should be zero");
        assertEq(wStablsscs.balanceOf(user2), 100 * 10**6, "User2 should still have tokens");
        assertEq(wStablsscs.totalSupply(), totalSupplyBefore - user1Balance, "Total supply should decrease by user1 balance");
    }

    function test_DestroyBlackFundsEventEmission() public {
        // User1 wraps tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        uint256 user1Balance = wStablsscs.balanceOf(user1);

        // Blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.destroyBlackFunds(user1);
        vm.stopPrank();

        // Test event emission with exact parameters
        vm.expectEmit(true, false, false, true);
        emit WStablsscsContract.DestroyedBlackFunds(user1, user1Balance);
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);
    }

    function test_DestroyBlackFundsCannotBeCalledTwice() public {
        // User1 wraps tokens
        vm.startPrank(user1);
        stablsscs.approve(address(wStablsscs), WRAP_AMOUNT);
        wStablsscs.wrap(WRAP_AMOUNT);
        vm.stopPrank();

        // Blacklist user1
        vm.startPrank(Stablsscs_COMPLIANCE);
        stablsscs.addBlackList(user1);
        stablsscs.destroyBlackFunds(user1);
        vm.stopPrank();

        // Destroy black funds first time
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);
        assertEq(wStablsscs.balanceOf(user1), 0, "User1 balance should be zero after first destroy");

        // Try to destroy black funds again - should succeed but with zero amount
        vm.expectRevert("cannot destroy 0 black funds");
        vm.prank(Stablsscs_COMPLIANCE);
        wStablsscs.destroyBlackFunds(user1);
    }
}
