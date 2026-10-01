// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice ETH donations with public messages and full-balance withdrawal to an immutable owner.
/// @dev Messages are valid UTF-8 with at most 140 Unicode scalar values, not grapheme clusters.
contract TipJar is ReentrancyGuard {
    uint256 public constant MAX_MESSAGE_CHARACTERS = 140;

    /// @notice The requester who receives withdrawals; pass $owner when deploying through ProjectFactory.
    address public immutable owner;

    /// @notice Lifetime ETH tipped through tip() and receive(), in wei; withdrawals do not reset it.
    /// @dev Forced ETH transfers bypass execution and are not counted here or in Tip events.
    uint256 public totalTipped;

    event Tip(address indexed sender, uint256 amount, string message);
    event Withdrawal(address indexed owner, uint256 amount);

    error InvalidOwner();
    error NotOwner();
    error ZeroTip();
    error MessageTooLong();
    error InvalidUTF8();
    error NothingToWithdraw();
    error WithdrawalFailed();

    /// @param initialOwner Nonzero requester address, explicitly supplied because the factory is msg.sender.
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert InvalidOwner();
        owner = initialOwner;
    }

    /// @notice Donate a positive amount of ETH with an optional public message.
    function tip(string calldata message) external payable nonReentrant {
        _validateMessage(bytes(message));
        _recordTip(message);
    }

    /// @notice A plain ETH transfer is a tip with an empty message.
    receive() external payable nonReentrant {
        _recordTip("");
    }

    /// @notice Transfer the entire ETH balance to the owner. A failed payment reverts atomically.
    function withdraw() external nonReentrant {
        if (msg.sender != owner) revert NotOwner();
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();

        emit Withdrawal(owner, amount);
        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) revert WithdrawalFailed();
    }

    function _recordTip(string memory message) private {
        if (msg.value == 0) revert ZeroTip();
        totalTipped += msg.value;
        emit Tip(msg.sender, msg.value, message);
    }

    /// @dev Rejects truncated, overlong, surrogate, and out-of-range UTF-8 encodings.
    function _validateMessage(bytes calldata message) private pure {
        // A Unicode scalar value takes at most four UTF-8 bytes. Bound work before iterating.
        if (message.length > MAX_MESSAGE_CHARACTERS * 4) revert MessageTooLong();
        uint256 characters = 0;
        uint256 i = 0;
        while (i < message.length) {
            if (++characters > MAX_MESSAGE_CHARACTERS) revert MessageTooLong();
            uint8 first = uint8(message[i]);
            uint256 width;
            if (first <= 0x7f) {
                width = 1;
            } else if (first >= 0xc2 && first <= 0xdf) {
                width = 2;
            } else if (first >= 0xe0 && first <= 0xef) {
                width = 3;
            } else if (first >= 0xf0 && first <= 0xf4) {
                width = 4;
            } else {
                revert InvalidUTF8();
            }

            if (i + width > message.length) revert InvalidUTF8();
            for (uint256 j = 1; j < width; ++j) {
                uint8 continuation = uint8(message[i + j]);
                if (continuation < 0x80 || continuation > 0xbf) revert InvalidUTF8();
            }

            if (width == 3) {
                uint8 second = uint8(message[i + 1]);
                if ((first == 0xe0 && second < 0xa0) || (first == 0xed && second >= 0xa0)) revert InvalidUTF8();
            } else if (width == 4) {
                uint8 second = uint8(message[i + 1]);
                if ((first == 0xf0 && second < 0x90) || (first == 0xf4 && second > 0x8f)) revert InvalidUTF8();
            }
            i += width;
        }
    }
}
