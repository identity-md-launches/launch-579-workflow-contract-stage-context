// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TipJar} from "src/TipJar.sol";
import {OwnerReceiver} from "./helpers/OwnerReceiver.sol";

/// @dev Test-only forced ETH, including under Cancun: creation and destruction happen in one transaction.
contract ForcedTipJarETH {
    constructor(address payable recipient) payable {
        selfdestruct(recipient);
    }
}

contract AdversarialTipJarHandler is Test {
    uint256 public constant INITIAL_BALANCE = 100_000 ether;
    TipJar public immutable jar;
    OwnerReceiver public immutable receiver;
    address[4] public donors;
    mapping(address => uint256) public given;
    uint256 public tipped;
    uint256 public forced;
    uint256 public withdrawn;

    event Tip(address indexed sender, uint256 amount, string message);
    event Withdrawal(address indexed owner, uint256 amount);

    constructor() {
        receiver = new OwnerReceiver();
        jar = new TipJar(address(receiver));
        for (uint256 i; i < donors.length; ++i) {
            donors[i] = address(uint160(0x2000 + i));
            vm.deal(donors[i], INITIAL_BALANCE);
        }
        vm.deal(address(this), INITIAL_BALANCE);
    }

    function donate(uint8 donorSeed, uint96 amountSeed, bool plain) public {
        address donor = donors[uint256(donorSeed) % donors.length];
        uint256 amount = bound(amountSeed, 1, 1 ether);
        string memory message = plain ? "" : unicode"A tip: é中🎉";
        vm.expectEmit(true, false, false, true, address(jar));
        emit Tip(donor, amount, message);
        vm.prank(donor);
        if (plain) {
            (bool ok,) = address(jar).call{value: amount}("");
            assertTrue(ok);
        } else {
            jar.tip{value: amount}(message);
        }
        tipped += amount;
        given[donor] += amount;
    }

    function forceETH(uint96 amountSeed) public {
        uint256 amount = bound(amountSeed, 1, 1 ether);
        vm.recordLogs();
        new ForcedTipJarETH{value: amount}(payable(address(jar)));
        assertEq(vm.getRecordedLogs().length, 0, "forced ETH must not create a tip event");
        forced += amount;
    }

    function setReceiverMode(uint8 modeSeed) public {
        receiver.setMode(OwnerReceiver.Mode(uint256(modeSeed) % 4));
    }

    function withdraw() public {
        uint256 amount = tipped + forced - withdrawn;
        OwnerReceiver.Mode mode = receiver.mode();
        if (amount == 0) {
            vm.expectRevert(TipJar.NothingToWithdraw.selector);
            receiver.collect(jar);
        } else if (mode == OwnerReceiver.Mode.Reject || mode == OwnerReceiver.Mode.ReenterAndRevert) {
            vm.expectRevert(TipJar.WithdrawalFailed.selector);
            receiver.collect(jar);
        } else {
            vm.expectEmit(true, false, false, true, address(jar));
            emit Withdrawal(address(receiver), amount);
            receiver.collect(jar);
            withdrawn += amount;
            if (mode == OwnerReceiver.Mode.Reenter) {
                bytes memory expected = abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
                assertFalse(receiver.withdrawSucceeded());
                assertFalse(receiver.tipSucceeded());
                assertFalse(receiver.receiveSucceeded());
                assertEq(receiver.withdrawError(), expected);
                assertEq(receiver.tipError(), expected);
                assertEq(receiver.receiveError(), expected);
            }
        }
    }

    function unauthorizedWithdraw(uint8 donorSeed) public {
        address donor = donors[uint256(donorSeed) % donors.length];
        // Even a transaction originating at the owner cannot authorize a different msg.sender.
        vm.prank(donor, address(receiver));
        vm.expectRevert(TipJar.NotOwner.selector);
        jar.withdraw();
    }

    function invalidDonation(uint8 donorSeed, uint8 kindSeed, uint96 amountSeed) public {
        address donor = donors[uint256(donorSeed) % donors.length];
        uint256 kind = uint256(kindSeed) % 5;
        uint256 amount = bound(amountSeed, 1, 1 ether);
        bytes memory data;
        bytes memory expected;
        if (kind == 0) {
            data = abi.encodeCall(TipJar.tip, (string(new bytes(141))));
            expected = abi.encodeWithSelector(TipJar.MessageTooLong.selector);
        } else if (kind == 1) {
            bytes memory invalid = hex"eda080";
            data = abi.encodeCall(TipJar.tip, (string(invalid)));
            expected = abi.encodeWithSelector(TipJar.InvalidUTF8.selector);
        } else if (kind == 2 || kind == 3) {
            amount = 0;
            data = kind == 2 ? abi.encodeCall(TipJar.tip, ("")) : bytes("");
            expected = abi.encodeWithSelector(TipJar.ZeroTip.selector);
        } else {
            data = hex"deadbeef";
        }
        vm.prank(donor);
        (bool ok, bytes memory result) = address(jar).call{value: amount}(data);
        assertFalse(ok);
        if (kind != 4) assertEq(result, expected);
        // No ghost update: every donor's balance and all jar accounting must remain unchanged.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract TipJarAdversarialInvariantTest is Test {
    AdversarialTipJarHandler private handler;
    TipJar private jar;
    OwnerReceiver private receiver;

    function setUp() public {
        handler = new AdversarialTipJarHandler();
        jar = handler.jar();
        receiver = handler.receiver();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = AdversarialTipJarHandler.donate.selector;
        selectors[1] = AdversarialTipJarHandler.forceETH.selector;
        selectors[2] = AdversarialTipJarHandler.setReceiverMode.selector;
        selectors[3] = AdversarialTipJarHandler.withdraw.selector;
        selectors[4] = AdversarialTipJarHandler.unauthorizedWithdraw.selector;
        selectors[5] = AdversarialTipJarHandler.invalidDonation.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_allETHIsHeldOrPaidToTheOwnerExactlyOnce() public view {
        assertEq(address(jar).balance + handler.withdrawn(), handler.tipped() + handler.forced());
        assertEq(address(receiver).balance, handler.withdrawn(), "wrong payout or callback lost ETH");
        assertEq(receiver.received(), handler.withdrawn(), "failed payment was counted");
        assertEq(jar.owner(), address(receiver));
        assertEq(address(handler).balance + handler.forced(), handler.INITIAL_BALANCE());
    }

    function invariant_lifetimeTotalCountsOnlySuccessfulDonations() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address donor = handler.donors(i);
            uint256 given = handler.given(donor);
            sum += given;
            assertEq(donor.balance + given, handler.INITIAL_BALANCE(), "donor was charged incorrectly");
        }
        assertEq(sum, handler.tipped());
        assertEq(jar.totalTipped(), sum, "forced ETH, withdrawals, or reverts changed lifetime total");
    }

    /// @dev Rejected payments and reentrant callbacks must not permanently lock the withdrawal guard.
    function afterInvariant() public {
        handler.setReceiverMode(uint8(OwnerReceiver.Mode.Accept));
        handler.withdraw();
        assertEq(address(jar).balance, 0);
        invariant_allETHIsHeldOrPaidToTheOwnerExactlyOnce();
        invariant_lifetimeTotalCountsOnlySuccessfulDonations();
    }

    function test_handlerExercisesEveryRejectionAndRecoversFromOwnerFailure() public {
        handler.withdraw();
        handler.donate(0, 1, false);
        handler.donate(1, 1 ether, true);
        handler.forceETH(1);
        for (uint8 i; i < 5; ++i) {
            handler.invalidDonation(i, i, 1);
        }
        handler.unauthorizedWithdraw(2);
        handler.setReceiverMode(uint8(OwnerReceiver.Mode.Reject));
        handler.withdraw();
        handler.setReceiverMode(uint8(OwnerReceiver.Mode.ReenterAndRevert));
        handler.withdraw();
        invariant_allETHIsHeldOrPaidToTheOwnerExactlyOnce();
        invariant_lifetimeTotalCountsOnlySuccessfulDonations();
        handler.setReceiverMode(uint8(OwnerReceiver.Mode.Reenter));
        handler.withdraw();
        invariant_allETHIsHeldOrPaidToTheOwnerExactlyOnce();
        handler.donate(3, 1, true);
        afterInvariant();
    }
}
