// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {PepperRouteProcessor} from "contracts/PepperRouteProcessor.sol";
import {console} from "forge-std/console.sol";

contract DeployPepperRouteProcessor is Script {
    // use
    // forge script script/deployRouter.s.sol --broadcast --account <walletName>

    function run() external {
        vm.createSelectFork("mainnet");

        vm.startBroadcast();

        // Declare the priviledgedUsers array
        address[] memory priviledgedUsers = new address[](2);
        
        // Assign values to the array
        priviledgedUsers[0] = 0xA1D2fc16b435F91295420D40d6a98bB1302080D9;
        priviledgedUsers[1] = 0x475e053c171FF06FE555E536fF85148F6B053d29;
        
        // Deploy the PepperRouteProcessor contract
        PepperRouteProcessor router = new PepperRouteProcessor{salt: "pepper"}(
            0xF5BCE5077908a1b7370B9ae04AdC565EBd643966,
            priviledgedUsers
        );
        console.log("Router address: %s", address(router));

        vm.stopBroadcast();
    }
}
