// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import "../base/Storage.sol";

contract TriggerFeeCollector is Script, Storage {
    uint256 internal constant DONATE_AMOUNT = 69_420 ether;

    function run() public virtual {
        feeCollector = FeeCollector(0x9B6F83a371Db1d6eB2eA9B33E84f3b6CB4cDe1bE);
        bgtStaker = BGTStaker(0x791fb53432eED7e2fbE4cf8526ab6feeA604Eb6d);
        address honey = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
        address usdc = 0xd6D83aF58a19Cd14eF3CF6fe848C9A4d21e5727c;

        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        address[] memory feeTokens = new address[](1);
        feeTokens[0] = usdc;

        uint256 amount = DONATE_AMOUNT + feeCollector.payoutAmount();
        IERC20(honey).approve(address(feeCollector), amount);
        console2.log("Approved %d Honey to FeeCollector", amount);

        feeCollector.claimFees(msg.sender, feeTokens);
        console2.log("Claimed fees");

        feeCollector.donate(DONATE_AMOUNT);
        console2.log("Donated %d Honey", DONATE_AMOUNT);

        vm.stopBroadcast();
    }
}
