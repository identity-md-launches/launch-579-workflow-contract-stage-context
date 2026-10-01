// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TipJar} from "../src/TipJar.sol";

contract TipJarHandler is Test {
    TipJar public immutable jar;
    uint256 public sent;
    uint256 public withdrawn;

    constructor() {
        jar = new TipJar(address(this));
        vm.deal(address(this), 1_000_000 ether);
    }

    function tip(uint96 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1 ether);
        jar.tip{value: amount}("stateful tip");
        sent += amount;
    }

    function plainTip(uint96 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1 ether);
        (bool success,) = address(jar).call{value: amount}("");
        assertTrue(success);
        sent += amount;
    }

    function withdraw() external {
        uint256 balance = address(jar).balance;
        if (balance == 0) return;
        jar.withdraw();
        withdrawn += balance;
    }

    function rejectZeroTip() external {
        (bool success, bytes memory result) = address(jar).call(abi.encodeCall(TipJar.tip, ("zero")));
        assertFalse(success);
        assertEq(result, abi.encodeWithSelector(TipJar.ZeroTip.selector));
    }

    receive() external payable {}
}

contract TipJarInvariantTest is Test {
    TipJarHandler private handler;
    TipJar private jar;

    function setUp() public {
        handler = new TipJarHandler();
        jar = handler.jar();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TipJarHandler.tip.selector;
        selectors[1] = TipJarHandler.plainTip.selector;
        selectors[2] = TipJarHandler.withdraw.selector;
        selectors[3] = TipJarHandler.rejectZeroTip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_lifetimeTipsEqualIndependentAccounting() public view {
        assertEq(jar.totalTipped(), handler.sent());
    }

    function invariant_everyTippedWeiIsHeldOrWithdrawn() public view {
        assertEq(address(jar).balance + handler.withdrawn(), handler.sent());
        assertEq(address(jar).balance + address(handler).balance, 1_000_000 ether);
    }

    function invariant_ownerNeverChanges() public view {
        assertEq(jar.owner(), address(handler));
    }
}
