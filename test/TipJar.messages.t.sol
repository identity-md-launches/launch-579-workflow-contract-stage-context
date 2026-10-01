// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TipJar} from "src/TipJar.sol";

/// @dev Generate Unicode scalars and encode them; do not copy the contract's byte-validation algorithm.
/// forge-config: default.fuzz.runs = 1000
contract TipJarMessagePropertiesTest is Test {
    TipJar private jar;
    address private donor = makeAddr("message donor");
    address private owner = makeAddr("message owner");

    function setUp() public {
        jar = new TipJar(owner);
        vm.deal(donor, 1_000 ether);
        vm.prank(donor);
        jar.tip{value: 7}("earlier donation");
    }

    function testFuzz_mixedUnicodeMessagesRoundTripThroughEvents(uint8 lengthSeed, bytes32 seed, uint96 amountSeed)
        public
    {
        uint256 length = bound(lengthSeed, 0, 140);
        uint256 amount = bound(amountSeed, 1, 100 ether);
        _assertAccepted(_message(length, seed), amount);
    }

    function testFuzz_tooManyMixedUnicodeScalarsRevertAtomically(uint8 lengthSeed, bytes32 seed) public {
        uint256 length = bound(lengthSeed, 141, 180);
        _assertRejected(_message(length, seed), TipJar.MessageTooLong.selector);
    }

    function testFuzz_overlongEncodingsInsideValidTextRevert(uint8 widthSeed, uint32 scalarSeed, uint8 prefixSeed)
        public
    {
        uint256 width = bound(widthSeed, 2, 4);
        uint256 maximum = width == 2 ? 0x7f : (width == 3 ? 0x7ff : 0xffff);
        uint256 scalar = bound(scalarSeed, 0, maximum);
        _assertRejected(_surround(_encode(scalar, width), prefixSeed), TipJar.InvalidUTF8.selector);
    }

    function testFuzz_nonScalarEncodingsRevert(uint32 scalarSeed, bool aboveUnicodeMaximum, uint8 prefixSeed) public {
        uint256 scalar = aboveUnicodeMaximum ? bound(scalarSeed, 0x110000, 0x1fffff) : bound(scalarSeed, 0xd800, 0xdfff);
        _assertRejected(
            _surround(_encode(scalar, aboveUnicodeMaximum ? 4 : 3), prefixSeed), TipJar.InvalidUTF8.selector
        );
    }

    function testFuzz_eachContinuationPositionRejectsNonContinuationBytes(
        uint8 widthSeed,
        uint8 positionSeed,
        uint8 byteSeed,
        uint8 prefixSeed
    ) public {
        uint256 width = bound(widthSeed, 2, 4);
        uint256 position = bound(positionSeed, 1, width - 1);
        uint256 invalidByte = bound(byteSeed, 0, 191);
        if (invalidByte >= 128) invalidByte += 64; // Map directly onto [00,7f] union [c0,ff].
        bytes memory encoded = _encode(width == 2 ? 0x7ff : (width == 3 ? 0xffff : 0x10ffff), width);
        encoded[position] = bytes1(uint8(invalidByte));
        _assertRejected(_surround(encoded, prefixSeed), TipJar.InvalidUTF8.selector);
    }

    function testFuzz_truncationAtEveryMultibytePositionReverts(uint8 widthSeed, uint8 cutSeed, uint8 prefixSeed)
        public
    {
        uint256 width = bound(widthSeed, 2, 4);
        uint256 retained = bound(cutSeed, 1, width - 1);
        bytes memory encoded = _encode(width == 2 ? 0x7ff : (width == 3 ? 0xffff : 0x10ffff), width);
        bytes memory truncated = new bytes(retained);
        for (uint256 i; i < retained; ++i) {
            truncated[i] = encoded[i];
        }
        bytes memory prefix = _message(bound(prefixSeed, 0, 139), bytes32(uint256(123)));
        _assertRejected(bytes.concat(prefix, truncated), TipJar.InvalidUTF8.selector);
    }

    function test_mixed140ScalarBoundaryAndOneMoreScalar() public {
        bytes memory message = _message(140, bytes32(uint256(42)));
        assertGt(message.length, 140, "exercise characters rather than bytes");
        _assertAccepted(message, 1);
        _assertRejected(bytes.concat(message, bytes("!")), TipJar.MessageTooLong.selector);
    }

    function test_embeddedNulCombiningMarksAndMarkupRemainUnchanged() public {
        // A public message is event data, with no truncation at NUL, normalization, or HTML interpretation.
        bytes memory message = bytes.concat(bytes(unicode"é <b>tip</b>"), hex"00", bytes(unicode"🎉"));
        _assertAccepted(message, 1);
    }

    function test_rejectedMessageDoesNotPreventLaterTipAndFullWithdrawal() public {
        _assertRejected(bytes.concat(bytes("valid prefix"), hex"f4908080"), TipJar.InvalidUTF8.selector);
        _assertAccepted(bytes("next donation"), 1);
        vm.prank(owner);
        jar.withdraw();
        assertEq(address(jar).balance, 0);
        assertEq(owner.balance, 8);
        assertEq(jar.totalTipped(), 8);
    }

    function _assertAccepted(bytes memory message, uint256 amount) private {
        uint256 beforeBalance = address(jar).balance;
        uint256 beforeDonor = donor.balance;
        uint256 beforeTotal = jar.totalTipped();
        vm.recordLogs();
        vm.prank(donor);
        jar.tip{value: amount}(string(message));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event per tip");
        assertEq(logs[0].emitter, address(jar));
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("Tip(address,uint256,string)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(donor))));
        (uint256 eventAmount, string memory eventMessage) = abi.decode(logs[0].data, (uint256, string));
        assertEq(eventAmount, amount);
        assertEq(bytes(eventMessage), message);
        assertEq(address(jar).balance, beforeBalance + amount);
        assertEq(donor.balance, beforeDonor - amount);
        assertEq(jar.totalTipped(), beforeTotal + amount);
        assertEq(owner.balance, 0);
    }

    function _assertRejected(bytes memory message, bytes4 errorSelector) private {
        uint256 beforeBalance = address(jar).balance;
        uint256 beforeDonor = donor.balance;
        uint256 beforeTotal = jar.totalTipped();
        vm.recordLogs();
        vm.prank(donor);
        vm.expectRevert(errorSelector);
        jar.tip{value: 1}(string(message));
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(address(jar).balance, beforeBalance);
        assertEq(donor.balance, beforeDonor);
        assertEq(jar.totalTipped(), beforeTotal);
    }

    function _surround(bytes memory invalid, uint8 prefixSeed) private pure returns (bytes memory) {
        // At most 140 scalar positions, so character length cannot hide an invalid-encoding failure.
        bytes memory prefix = _message(uint256(prefixSeed) % 139, bytes32(uint256(321)));
        return bytes.concat(prefix, invalid, bytes("z"));
    }

    function _message(uint256 length, bytes32 seed) private pure returns (bytes memory message) {
        for (uint256 i; i < length; ++i) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            uint256 width = (i + uint256(seed) % 4) % 4 + 1;
            uint256 scalar;
            if (width == 1) {
                scalar = entropy % 0x80;
            } else if (width == 2) {
                scalar = 0x80 + entropy % (0x800 - 0x80);
            } else if (width == 3) {
                scalar = 0x800 + entropy % (0x10000 - 0x800 - 0x800);
                if (scalar >= 0xd800) scalar += 0x800; // Exclude surrogates without discarding a fuzz input.
            } else {
                scalar = 0x10000 + entropy % (0x110000 - 0x10000);
            }
            message = bytes.concat(message, _encode(scalar, width));
        }
    }

    /// @dev Explicit width also permits generating invalid non-shortest encodings for rejection tests.
    function _encode(uint256 scalar, uint256 width) private pure returns (bytes memory encoded) {
        encoded = new bytes(width);
        if (width == 1) {
            encoded[0] = bytes1(uint8(scalar));
            return encoded;
        }
        for (uint256 i = width - 1; i > 0; --i) {
            encoded[i] = bytes1(uint8(0x80 + scalar % 64));
            scalar /= 64;
        }
        uint256 prefix = width == 2 ? 0xc0 : (width == 3 ? 0xe0 : 0xf0);
        encoded[0] = bytes1(uint8(prefix + scalar));
    }
}
