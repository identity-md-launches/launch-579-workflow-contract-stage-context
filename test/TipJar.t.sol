// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TipJar} from "../src/TipJar.sol";
import {OwnerReceiver} from "./helpers/OwnerReceiver.sol";

contract TipJarTest is Test {
    TipJar private jar;
    address private owner = makeAddr("owner");
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    event Tip(address indexed sender, uint256 amount, string message);
    event Withdrawal(address indexed owner, uint256 amount);

    function setUp() public {
        jar = new TipJar(owner);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_initialConfiguration() public view {
        assertEq(jar.owner(), owner);
        assertEq(jar.totalTipped(), 0);
        assertEq(jar.MAX_MESSAGE_CHARACTERS(), 140);
        assertEq(address(jar).balance, 0);
    }

    function test_zeroOwnerRejected() public {
        vm.expectRevert(TipJar.InvalidOwner.selector);
        new TipJar(address(0));
    }

    function test_tipEmitsExactEventAndChargesNoFee() public {
        vm.expectEmit(true, false, false, true, address(jar));
        emit Tip(alice, 3 ether, "Thank you!");
        vm.prank(alice);
        jar.tip{value: 3 ether}("Thank you!");
        assertEq(alice.balance, 97 ether);
        assertEq(address(jar).balance, 3 ether);
        assertEq(jar.totalTipped(), 3 ether);
        assertEq(owner.balance, 0);
    }

    function test_emptyMessageAndRepeatedTipsAreAllowed() public {
        vm.startPrank(alice);
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, false, false, true, address(jar));
            emit Tip(alice, 1, "");
            jar.tip{value: 1}("");
        }
        vm.stopPrank();
        assertEq(address(jar).balance, 2);
        assertEq(jar.totalTipped(), 2);
    }

    function test_plainETHTransferEmitsEmptyMessageTip() public {
        vm.expectEmit(true, false, false, true, address(jar));
        emit Tip(bob, 2 ether, "");
        vm.prank(bob);
        (bool success,) = address(jar).call{value: 2 ether}("");
        assertTrue(success);
        assertEq(address(jar).balance, 2 ether);
        assertEq(jar.totalTipped(), 2 ether);
    }

    function test_zeroValueRejectedOnBothEntryPoints() public {
        vm.prank(alice);
        vm.expectRevert(TipJar.ZeroTip.selector);
        jar.tip("not a donation");
        vm.prank(alice);
        (bool success, bytes memory result) = address(jar).call("");
        assertFalse(success);
        assertEq(result, abi.encodeWithSelector(TipJar.ZeroTip.selector));
        assertEq(jar.totalTipped(), 0);
        assertEq(address(jar).balance, 0);
    }

    function test_unknownCalldataRejectedWithoutTakingETH() public {
        vm.prank(alice);
        (bool success,) = address(jar).call{value: 1 ether}(hex"deadbeef");
        assertFalse(success);
        assertEq(address(jar).balance, 0);
        assertEq(jar.totalTipped(), 0);
        assertEq(alice.balance, 100 ether);
    }

    function test_exactly140ASCIICharactersAccepted() public {
        string memory message = _repeat(bytes("a"), 140);
        vm.expectEmit(true, false, false, true, address(jar));
        emit Tip(alice, 1, message);
        vm.prank(alice);
        jar.tip{value: 1}(message);
        assertEq(jar.totalTipped(), 1);
    }

    function test_141ASCIICharactersRejectedAtomically() public {
        string memory message = _repeat(bytes("a"), 141);
        vm.recordLogs();
        vm.prank(alice);
        vm.expectRevert(TipJar.MessageTooLong.selector);
        jar.tip{value: 1 ether}(message);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(alice.balance, 100 ether);
        assertEq(address(jar).balance, 0);
        assertEq(jar.totalTipped(), 0);
    }

    function test_140FourByteUnicodeCharactersAccepted() public {
        string memory message = _repeat(hex"f09f8e89", 140);
        assertEq(bytes(message).length, 560);
        vm.expectEmit(true, false, false, true, address(jar));
        emit Tip(alice, 1, message);
        vm.prank(alice);
        jar.tip{value: 1}(message);
        assertEq(jar.totalTipped(), 1);
    }

    function test_141UnicodeCharactersRejected() public {
        string memory threeByteMessage = _repeat(hex"e4b8ad", 141);
        string memory fourByteMessage = _repeat(hex"f09f8e89", 141);
        vm.startPrank(alice);
        vm.expectRevert(TipJar.MessageTooLong.selector);
        jar.tip{value: 1}(threeByteMessage);
        vm.expectRevert(TipJar.MessageTooLong.selector);
        jar.tip{value: 1}(fourByteMessage);
        vm.stopPrank();
        assertEq(jar.totalTipped(), 0);
    }

    function test_mixedUnicodeAndEncodingBoundariesAccepted() public {
        // ASCII, min/max 2-byte, min/max non-surrogate 3-byte, and min/max 4-byte scalars.
        string memory message = string(hex"007fc280dfbfe0a080ed9fbfee8080efbfbff0908080f48fbfbf");
        vm.prank(alice);
        jar.tip{value: 1}(message);
        assertEq(jar.totalTipped(), 1);
    }

    function test_malformedUTF8Rejected() public {
        bytes[18] memory invalid = [
            bytes(hex"80"), // Lone continuation byte.
            hex"c080", // Overlong 2-byte sequence.
            hex"c1bf",
            hex"e08080", // Overlong 3-byte sequence.
            hex"eda080", // Surrogate U+D800.
            hex"edbfbf", // Surrogate U+DFFF.
            hex"f0808080", // Overlong 4-byte sequence.
            hex"f4908080", // Above U+10FFFF.
            hex"f5808080",
            hex"ff",
            hex"c2", // Truncated sequences.
            hex"e0a0",
            hex"f09080",
            hex"c241", // Invalid continuation bytes at each position.
            hex"e0a041",
            hex"f0908041",
            hex"c2c2",
            hex"61ff"
        ];
        vm.startPrank(alice);
        for (uint256 i; i < invalid.length; ++i) {
            vm.expectRevert(TipJar.InvalidUTF8.selector);
            jar.tip{value: 1}(string(invalid[i]));
        }
        vm.stopPrank();
        assertEq(jar.totalTipped(), 0);
        assertEq(address(jar).balance, 0);
    }

    function test_onlyOwnerCanWithdraw() public {
        vm.prank(alice);
        jar.tip{value: 2 ether}("gift");
        vm.prank(bob);
        vm.expectRevert(TipJar.NotOwner.selector);
        jar.withdraw();
        // The account that ran the constructor is also unauthorized if it is not the supplied owner.
        vm.expectRevert(TipJar.NotOwner.selector);
        jar.withdraw();
        assertEq(address(jar).balance, 2 ether);
        assertEq(owner.balance, 0);
        assertEq(jar.totalTipped(), 2 ether);
    }

    function test_withdrawsWholeBalanceAndPreservesLifetimeTotal() public {
        vm.prank(alice);
        jar.tip{value: 2 ether}("first");
        vm.prank(bob);
        jar.tip{value: 3 ether}("second");

        vm.expectEmit(true, false, false, true, address(jar));
        emit Withdrawal(owner, 5 ether);
        vm.prank(owner);
        jar.withdraw();
        assertEq(owner.balance, 5 ether);
        assertEq(address(jar).balance, 0);
        assertEq(jar.totalTipped(), 5 ether);

        vm.prank(owner);
        vm.expectRevert(TipJar.NothingToWithdraw.selector);
        jar.withdraw();
        vm.prank(alice);
        jar.tip{value: 1 ether}("after withdrawal");
        vm.prank(owner);
        jar.withdraw();
        assertEq(owner.balance, 6 ether);
        assertEq(jar.totalTipped(), 6 ether);
        assertEq(address(jar).balance, 0);
    }

    function test_emptyWithdrawalRejected() public {
        vm.prank(owner);
        vm.expectRevert(TipJar.NothingToWithdraw.selector);
        jar.withdraw();
    }

    function test_forcedETHIsWithdrawableButNotCountedAsTips() public {
        vm.prank(alice);
        jar.tip{value: 1 ether}("recorded");
        // Simulates balance changes without execution, e.g. forced ETH or predeployment funding.
        vm.deal(address(jar), 3 ether);
        assertEq(jar.totalTipped(), 1 ether);
        vm.prank(owner);
        jar.withdraw();
        assertEq(owner.balance, 3 ether);
        assertEq(jar.totalTipped(), 1 ether);
        assertEq(address(jar).balance, 0);
    }

    function test_contractOwnerCanReceiveWithMoreThan2300Gas() public {
        (TipJar ownedJar, OwnerReceiver receiver) = _fundContractOwnerJar();
        receiver.collect(ownedJar);
        assertEq(receiver.received(), 2 ether);
        assertEq(address(receiver).balance, 2 ether);
        assertEq(address(ownedJar).balance, 0);
    }

    function test_failedPaymentPreservesFundsAndCanBeRetried() public {
        (TipJar ownedJar, OwnerReceiver receiver) = _fundContractOwnerJar();
        receiver.setMode(OwnerReceiver.Mode.Reject);
        vm.expectRevert(TipJar.WithdrawalFailed.selector);
        receiver.collect(ownedJar);
        assertEq(address(ownedJar).balance, 2 ether);
        assertEq(ownedJar.totalTipped(), 2 ether);
        assertEq(address(receiver).balance, 0);
        receiver.setMode(OwnerReceiver.Mode.Accept);
        receiver.collect(ownedJar);
        assertEq(receiver.received(), 2 ether);
        assertEq(address(ownedJar).balance, 0);
    }

    function test_reentryIntoAllValueEntryPointsBlocked() public {
        (TipJar ownedJar, OwnerReceiver receiver) = _fundContractOwnerJar();
        receiver.setMode(OwnerReceiver.Mode.Reenter);
        receiver.collect(ownedJar);
        assertFalse(receiver.withdrawSucceeded());
        assertFalse(receiver.tipSucceeded());
        assertFalse(receiver.receiveSucceeded());
        bytes memory expected = abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(receiver.withdrawError(), expected);
        assertEq(receiver.tipError(), expected);
        assertEq(receiver.receiveError(), expected);
        assertEq(receiver.received(), 2 ether);
        assertEq(address(receiver).balance, 2 ether);
        assertEq(address(ownedJar).balance, 0);
        assertEq(ownedJar.totalTipped(), 2 ether);
    }

    function test_revertingReentrantOwnerCannotLoseFundsOrLockGuard() public {
        (TipJar ownedJar, OwnerReceiver receiver) = _fundContractOwnerJar();
        receiver.setMode(OwnerReceiver.Mode.ReenterAndRevert);
        vm.expectRevert(TipJar.WithdrawalFailed.selector);
        receiver.collect(ownedJar);
        assertEq(address(ownedJar).balance, 2 ether);
        assertEq(receiver.received(), 0);
        assertEq(ownedJar.totalTipped(), 2 ether);
        vm.prank(alice);
        ownedJar.tip{value: 1 ether}("guard recovered");
        receiver.setMode(OwnerReceiver.Mode.Accept);
        receiver.collect(ownedJar);
        assertEq(receiver.received(), 3 ether);
        assertEq(address(ownedJar).balance, 0);
    }

    function testFuzz_conservationAcrossWithdrawal(uint96 firstSeed, uint96 secondSeed) public {
        uint256 first = bound(firstSeed, 1, 100 ether);
        uint256 second = bound(secondSeed, 1, 100 ether);
        vm.prank(alice);
        jar.tip{value: first}("one");
        vm.prank(bob);
        jar.tip{value: second}("two");
        assertEq(alice.balance + bob.balance + address(jar).balance + owner.balance, 200 ether);
        vm.prank(owner);
        jar.withdraw();
        assertEq(owner.balance, first + second);
        assertEq(jar.totalTipped(), first + second);
        assertEq(alice.balance + bob.balance + address(jar).balance + owner.balance, 200 ether);
    }

    function testFuzz_asciiCharacterLimit(uint8 lengthSeed) public {
        uint256 length = bound(lengthSeed, 0, 180);
        string memory message = _repeat(bytes("x"), length);
        vm.prank(alice);
        if (length > 140) vm.expectRevert(TipJar.MessageTooLong.selector);
        jar.tip{value: 1}(message);
        assertEq(jar.totalTipped(), length > 140 ? 0 : 1);
    }

    function testFuzz_unicodeScalarAccepted(uint32 scalarSeed) public {
        uint32 scalar = uint32(bound(scalarSeed, 0, 0x10f7ff));
        if (scalar >= 0xd800) scalar += 0x800;
        bytes memory encoded;
        // Encode a scalar independently of the contract's byte-oriented validation.
        if (scalar < 0x80) {
            encoded = abi.encodePacked(bytes1(uint8(scalar)));
        } else if (scalar < 0x800) {
            encoded = abi.encodePacked(bytes1(uint8(0xc0 | (scalar >> 6))), bytes1(uint8(0x80 | (scalar & 0x3f))));
        } else if (scalar < 0x10000) {
            encoded = abi.encodePacked(
                bytes1(uint8(0xe0 | (scalar >> 12))),
                bytes1(uint8(0x80 | ((scalar >> 6) & 0x3f))),
                bytes1(uint8(0x80 | (scalar & 0x3f)))
            );
        } else {
            encoded = abi.encodePacked(
                bytes1(uint8(0xf0 | (scalar >> 18))),
                bytes1(uint8(0x80 | ((scalar >> 12) & 0x3f))),
                bytes1(uint8(0x80 | ((scalar >> 6) & 0x3f))),
                bytes1(uint8(0x80 | (scalar & 0x3f)))
            );
        }
        vm.prank(alice);
        jar.tip{value: 1}(string(encoded));
        assertEq(jar.totalTipped(), 1);
    }

    function _fundContractOwnerJar() private returns (TipJar ownedJar, OwnerReceiver receiver) {
        receiver = new OwnerReceiver();
        ownedJar = new TipJar(address(receiver));
        vm.prank(alice);
        ownedJar.tip{value: 2 ether}("contract owner");
    }

    function _repeat(bytes memory unit, uint256 count) private pure returns (string memory) {
        bytes memory result = new bytes(unit.length * count);
        for (uint256 i; i < count; ++i) {
            for (uint256 j; j < unit.length; ++j) {
                result[i * unit.length + j] = unit[j];
            }
        }
        return string(result);
    }
}
