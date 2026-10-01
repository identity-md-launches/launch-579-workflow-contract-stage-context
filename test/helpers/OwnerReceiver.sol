// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TipJar} from "../../src/TipJar.sol";

/// @dev Test-only owner that exercises contract-wallet payment and callback failures.
contract OwnerReceiver {
    enum Mode {
        Accept,
        Reject,
        Reenter,
        ReenterAndRevert
    }

    Mode public mode;
    uint256 public received;
    bool public withdrawSucceeded;
    bool public tipSucceeded;
    bool public receiveSucceeded;
    bytes public withdrawError;
    bytes public tipError;
    bytes public receiveError;

    function setMode(Mode next) external {
        mode = next;
    }

    function collect(TipJar jar) external {
        jar.withdraw();
    }

    receive() external payable {
        require(mode != Mode.Reject, "owner refuses ETH");
        received += msg.value; // A storage write requires more than transfer()'s 2,300 gas stipend.
        if (mode == Mode.Reenter || mode == Mode.ReenterAndRevert) {
            (withdrawSucceeded, withdrawError) = msg.sender.call(abi.encodeCall(TipJar.withdraw, ()));
            (tipSucceeded, tipError) = msg.sender.call{value: 1}(abi.encodeCall(TipJar.tip, ("callback")));
            (receiveSucceeded, receiveError) = msg.sender.call{value: 1}("");
            require(mode != Mode.ReenterAndRevert, "owner propagates callback failure");
        }
    }
}
