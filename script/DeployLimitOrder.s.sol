// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LimitOrder} from "contracts/LimitOrder.sol";
import {console} from "forge-std/console.sol";

contract DeployLimitOrder is Script {
    // forge script script/DeployLimitOrder.s.sol:DeployLimitOrder --broadcast --account pepper-deployer

    function run() external {
        vm.createSelectFork("base");

        vm.startBroadcast();

        address pepperOwner = 0xa90EA397380DA7f790E4062f5BF4aF470b9099AC;
        address payable routeProcessorAddress = payable(
            0xA24d75601C9b69a604A4669509CFaeeF68a1dd5B
        );

        // Deploy the PepperRouteProcessor contract
        LimitOrder limitOrder = new LimitOrder(
            pepperOwner,
            routeProcessorAddress
        );
        console.log("Router address: %s", address(limitOrder));

        vm.stopBroadcast();
    }
}
