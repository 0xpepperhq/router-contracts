// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LimitOrder} from "../contracts/LimitOrder.sol";
import {console} from "forge-std/console.sol";

contract DeployLimitOrder is Script {
    // forge script script/DeployLimitOrder.s.sol:DeployLimitOrder --broadcast --account pepper-deployer
    // forge verify-contract --chain-id 8453 0x7a1C2CC1D683455D7B65E9f405abcd3Cc60c7983 ./contracts/LimitOrder.sol:LimitOrder --constructor-args $(cast abi-encode "constructor(address,address)" 0xa90EA397380DA7f790E4062f5BF4aF470b9099AC 0xA24d75601C9b69a604A4669509CFaeeF68a1dd5B) --watch

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
