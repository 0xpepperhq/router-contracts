// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PepperSwapV1} from "../contracts/PepperSwapV1.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Deploy is Script {
    function run() external {
        vm.createSelectFork("sepolia");

        // To change if new registry is deployed
        ISwapRouter uniSwapRouterV2 = ISwapRouter(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
        vm.startBroadcast();

        PepperSwapV1 pepperSwap = new PepperSwapV1(uniSwapRouterV2);
        console.log("PepperSwapV1 address: %s", address(pepperSwap));

        vm.stopBroadcast();
    }
}
