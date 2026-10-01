// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {TipJar} from "../src/TipJar.sol";

/// @dev Constructor-only CREATE2 deployment, without any initialization calls.
contract ConstructorFactory {
    function deploy(address owner) external returns (LaunchToken token, TipJar jar) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        jar = new TipJar{salt: bytes32(uint256(2))}(owner);
    }
}

contract FactoryDeploymentTest is Test {
    function test_factoryHoldsSupplyAndExplicitRequesterControlsJar() public {
        address requester = makeAddr("requester");
        ConstructorFactory factory = new ConstructorFactory();
        (LaunchToken token, TipJar jar) = factory.deploy(requester);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(jar.owner(), requester);

        vm.deal(address(this), 1 ether);
        jar.tip{value: 1 ether}("factory deployment");
        vm.prank(address(factory));
        vm.expectRevert(TipJar.NotOwner.selector);
        jar.withdraw();
        vm.prank(requester);
        jar.withdraw();
        assertEq(requester.balance, 1 ether);
        assertEq(token.balanceOf(address(factory)), 1e27);
        _assertAllowedRuntime(address(jar));
        _assertAllowedRuntime(address(token));
    }

    function test_bothConstructorsAreNonpayable() public {
        vm.deal(address(this), 2);
        bytes memory tokenCode = type(LaunchToken).creationCode;
        bytes memory jarCode = abi.encodePacked(type(TipJar).creationCode, abi.encode(address(this)));
        address token;
        address jar;
        assembly ("memory-safe") {
            token := create(1, add(tokenCode, 32), mload(tokenCode))
            jar := create(1, add(jarCode, 32), mload(jarCode))
        }
        assertEq(token, address(0));
        assertEq(jar, address(0));
        assertEq(address(this).balance, 2);
    }

    function _assertAllowedRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
            } else {
                assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
            }
        }
    }
}
