// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Closed actor set: every possible recipient is accounted for, including self-transfers.
contract LaunchTokenHandler is Test {
    uint256 public constant SUPPLY = 1e27;
    LaunchToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = address(uint160(0x1000 + i));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
        vm.startPrank(actors[0]);
        token = new LaunchToken();
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        vm.stopPrank();
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function transferAll(uint8 fromSeed, uint8 toSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Explicitly reach both revocation and infinite approvals as well as arbitrary uint256 values.
        uint256 amount = mode % 3 == 0 ? 0 : (mode % 3 == 1 ? type(uint256).max : amountSeed);
        _approve(owner, spender, amount);
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _move(owner, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function revokeAndAttemptSpend(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        _approve(owner, spender, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(owner, to, 1);
    }

    function spendBeyondBalance(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        token.transferFrom(owner, to, amount);
        // The invariant must also see the original allowance, despite spending it before the balance check.
    }

    function transferToZero(uint8 ownerSeed, uint8 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < allowance ? expectedBalance[owner] : allowance;
        uint256 amount = bound(amountSeed, 0, maximum);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(owner, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _actor(uint8 seed) private view returns (address) {
        return actors[uint256(seed) % actors.length];
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenInvariantTest is Test {
    LaunchTokenHandler private handler;
    LaunchToken private token;

    function setUp() public {
        handler = new LaunchTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = LaunchTokenHandler.transfer.selector;
        selectors[1] = LaunchTokenHandler.transferAll.selector;
        selectors[2] = LaunchTokenHandler.approve.selector;
        selectors[3] = LaunchTokenHandler.transferFrom.selector;
        selectors[4] = LaunchTokenHandler.revokeAndAttemptSpend.selector;
        selectors[5] = LaunchTokenHandler.spendBeyondBalance.selector;
        selectors[6] = LaunchTokenHandler.transferToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_fixedSupplyEqualsAllTrackedBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "incorrect recipient or transfer amount");
            sum += balance;
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_allowancesMatchAuthorizationsAndSuccessfulSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Every holder can still move its whole balance after an arbitrary sequence, including failures.
    function afterInvariant() public {
        address recipient = handler.actors(0);
        for (uint256 i = 1; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, balance));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(recipient), 1e27);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_handlerExercisesFiniteAndInfiniteAllowancesAndSelfSpending() public {
        handler.approve(0, 1, 100, 2);
        handler.transferFrom(0, 1, 2, 60);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 40);
        handler.approve(0, 1, 0, 1);
        handler.transferFrom(0, 1, 0, 1);
        handler.spendBeyondBalance(0, 1, 2, false);
        handler.transferToZero(0, 1, 1);
        handler.revokeAndAttemptSpend(0, 1, 2);
        handler.transferAll(0, 3);
        handler.transfer(3, 0, 1);
        invariant_fixedSupplyEqualsAllTrackedBalances();
        invariant_allowancesMatchAuthorizationsAndSuccessfulSpending();
        afterInvariant();
    }
}
