// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import "../base/Storage.sol";

contract TransferBeraToBgt is Storage, Script {
    function run() public virtual {
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        forceSafeTransferBERA(address(bgt), 1e3 ether);
        console2.log("Sent 1000 BERA to BGT");

        vm.stopBroadcast();
    }

    function forceSafeTransferBERA(address to, uint256 amount) public {
        require(msg.sender.balance >= amount, "Sender balance is less than the amount to transfer");
        // The BGT contract doesn't have `fallback` or `receive` functions, so we need to use `forceSafeTransferETH` to
        // send BERA to it.
        // SafeTransferLib.forceSafeTransferETH(address(bgt), amount);
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, to) // Store the address in scratch space.
            mstore8(0x0b, 0x73) // Opcode `PUSH20`.
            mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
            if iszero(create(amount, 0x0b, 0x16)) { revert(0, 0) }
        }
        console2.log("Sent %d BERA to %s", amount, to);
    }
}
