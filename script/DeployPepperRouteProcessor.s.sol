// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {PepperRouteProcessor} from "contracts/PepperRouteProcessor.sol";
import {console} from "forge-std/console.sol";

contract DeployPepperRouteProcessor is Script {
    // forge script script/DeployPepperRouteProcessor.s.sol:DeployPepperRouteProcessor --broadcast --account pepper-deployer --sender 0xa90EA397380DA7f790E4062f5BF4aF470b9099AC

    function run() external {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();

        // Declare the priviledgedUsers array
        address[] memory priviledgedUsers = new address[](2);
        address pepperOwner = 0xa90EA397380DA7f790E4062f5BF4aF470b9099AC;

        // Assign values to the array
        priviledgedUsers[0] = 0xA1D2fc16b435F91295420D40d6a98bB1302080D9;
        priviledgedUsers[1] = 0x6F6623B00B0b2eAEFA47A4fDE06d6931F7121722;

        // Deploy the PepperRouteProcessor contract
        PepperRouteProcessor router = new PepperRouteProcessor{salt: "pepper"}(
            pepperOwner,
            priviledgedUsers
        );
        console.log("Router address: %s", address(router));

        vm.stopBroadcast();
    }
}
