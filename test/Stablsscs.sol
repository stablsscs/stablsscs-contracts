// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {Stablsscs} from "../src/Stablsscs.sol";

contract StablsscsTest is Test {
    Stablsscs public token;
    uint256 testAmount = 100_000_000;
    uint256 MINT_CAP = 1_000_000_000_000_000_000;

    function setUp() public {
        address owner = address(0x123);
        address compliance = address(0x124);
        address accountant = address(0x125);

        token = new Stablsscs("Test", "TEST", 6, owner, compliance, accountant);
    }

    function test_Issue() public {
        vm.prank(token.owner());
        token.issue(address(this), testAmount);
        uint256 amountMinted = token.balanceOf(address(this));
        assertEq(amountMinted, testAmount);
    }

    function test_Issue_from_bad_address() public {
        vm.expectRevert();
        token.issue(address(this), testAmount);
    }

    function testFuzz_Issue(uint256 x) public {
        vm.assume(x <= MINT_CAP);
        vm.prank(token.owner());

        token.issue(address(this), x);
        uint256 amountMinted = token.balanceOf(address(this));
        assertEq(amountMinted, x);
    }

    function test_Burn() public {
        vm.startPrank(token.owner());
        token.issue(token.owner(), testAmount);
        token.burn(testAmount);
        assertEq(token.balanceOf(token.owner()), 0);
    }

    function test_Burn_from_bad_address() public {
        vm.startPrank(token.owner());
        token.issue(address(this), testAmount);
        vm.stopPrank();
        vm.expectRevert();
        token.burn(testAmount);
    }

    function testFuzz_Burn(uint256 x) public {
        vm.assume(x <= MINT_CAP);
        vm.startPrank(token.owner());
        token.issue(token.owner(), testAmount);
        if (x > testAmount) {
            vm.expectRevert();
        }
        token.burn(x);
        if (x <= testAmount) {
            assertEq(token.balanceOf(token.owner()), testAmount - x);
        }
    }

    function test_Transfer() public {
        address from = address(0x2);
        address to = address(0x3);

        uint256 amountToMint = 1_000_000_000_000;
        vm.prank(token.owner());
        token.issue(from, amountToMint);

        uint256 amountToTransfer1 = 700_000_000_000;
        vm.startPrank(from);
        token.transfer(to, amountToTransfer1);

        assertEq(token.balanceOf(from), amountToMint - amountToTransfer1);
        assertEq(token.balanceOf(to), amountToTransfer1);
        assertEq(token.totalSupply(), amountToMint);
        assertEq(token.totalLiquidity(), amountToMint);

        uint256 amountToTransfer2 = amountToMint - amountToTransfer1;
        token.transfer(to, amountToTransfer2);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), amountToMint);
        assertEq(token.totalSupply(), amountToMint);
        assertEq(token.totalLiquidity(), amountToMint);

        vm.expectRevert();
        token.transfer(to, 1);
    }

    function test_Approve() public {
        address from = address(0x2);
        address to = address(0x3);

        uint256 amountToMint = 1_000_000_000_000;
        vm.prank(token.owner());
        token.issue(from, amountToMint);

        uint256 amountToApprove = 500_000_000_000;
        vm.prank(from);
        token.approve(to, amountToApprove);

        assertEq(token.allowance(from, to), amountToApprove);
        vm.prank(from);
        token.approve(to, amountToMint);
        assertEq(token.allowance(from, to), amountToMint);
    }

    function test_TransferFrom() public {
        address from = address(0x2);
        address to = address(0x3);

        uint256 amount = 1_000_000_000_000;
        vm.prank(token.owner());
        token.issue(from, amount);

        vm.prank(from);
        token.approve(to, amount);

        vm.prank(to);
        token.transferFrom(from, to, amount);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), amount);
        assertEq(token.allowance(from, to), 0);

        vm.expectRevert();
        vm.prank(to);
        token.transferFrom(from, to, amount);
    }

    function test_Update_basis_rate_transfer() public {
        address from = address(0x2);
        address to = address(0x3);

        uint256 amount = 1_000_000_000_000;
        vm.startPrank(token.owner());
        token.issue(from, amount);
        token.updateBasisPointsRate(10);
        vm.stopPrank();

        vm.startPrank(from);
        token.transfer(to, amount);

        uint256 expectedFee = (amount * token.basisPointsRate()) / token.FEE_PRECISION();
        assertEq(token.balanceOf(token.owner()), expectedFee);
        assertEq(token.balanceOf(to), amount - expectedFee);
        assertEq(token.balanceOf(from), 0);
        assertEq(token.totalSupply(), amount);
        assertEq(token.totalLiquidity(), amount);
    }

    function test_DistributeInterest() public {
        address from = address(0x2);

        uint256 amount = 1_000;
        int256 toDistribute = 100;

        vm.prank(token.owner());
        token.issue(from, amount);

        uint256 totalSupplyBefore = token.totalShares();
        uint256 totalLiquidityBefore = token.totalLiquidity();
        vm.prank(token.accountant());
        token.distributeInterest(toDistribute);

        assertEq(token.totalShares(), totalSupplyBefore);
        assertEq(token.totalLiquidity(), totalLiquidityBefore + uint256(toDistribute));


        vm.prank(token.accountant());
        token.distributeInterest(-toDistribute);
        assertEq(token.totalShares(), totalSupplyBefore);
        assertEq(token.totalLiquidity(), totalLiquidityBefore);
    }

    function test_Pause() public {
        address to = address(0x1);

        uint256 amount = 1000;
        vm.startPrank(token.owner());
        token.issue(token.owner(), amount);
        token.pause();

        vm.expectRevert();
        token.transfer(to, amount);
    }
}