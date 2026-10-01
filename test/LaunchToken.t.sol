// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndEntireSupplyMintedToDeployer() public view {
        assertEq(token.name(), "Tip Jar");
        assertEq(token.symbol(), "TIPS");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_constructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new LaunchToken();
    }

    function test_transferMovesExactAmountWithoutFees() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 100 ether);
        assertTrue(token.transfer(alice, 100 ether));
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalAndTransferFromSpendAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), bob, 100 ether);
        assertTrue(token.approve(bob, 100 ether));
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 60 ether));
        assertEq(token.allowance(address(this), bob), 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_insufficientAllowanceRevertsWithoutStateChange() public {
        token.approve(bob, 3);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 3, 4));
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), bob), 3);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_insufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(bob, 10);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, bob), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferBeyondBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroRecipientAndSpenderRejected() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAndSelfTransfersPreserveSupplyAndBalance() public {
        assertTrue(token.transfer(alice, 0));
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceFollowsStandardERC20Behavior() public {
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_approvalCanBeRevoked() public {
        token.approve(bob, 10);
        token.approve(bob, 0);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_noMintAdminOrBurnEntrypointsEvenForDeployer() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "transferOwnership(address)",
            "setOwner(address)",
            "pause()",
            "setMinter(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "setFee(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, SUPPLY);
            (bool deployerSuccess,) = address(token).call(data);
            vm.prank(alice);
            (bool otherSuccess,) = address(token).call(data);
            assertFalse(deployerSuccess, signatures[i]);
            assertFalse(otherSuccess, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
        }
    }

    function test_tokenRejectsETH() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_transfersConserveFixedSupply(uint256 amountSeed, uint256 forwardedSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 forwarded = bound(forwardedSeed, 0, amount);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(bob, forwarded);
        assertEq(token.balanceOf(alice), amount - forwarded);
        assertEq(token.balanceOf(bob), forwarded);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
