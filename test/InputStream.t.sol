// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {InputStream} from "../contracts/InputStream.sol";
import {RouteSegment} from "../contracts/PepperRouteProcessor.sol";

contract InputStreamTest is Test {
    using InputStream for uint256;

    function createData() public pure returns (RouteSegment[] memory segments) {
        RouteSegment[] memory localSegments = new RouteSegment[](2);
        localSegments[0] = RouteSegment({
            providerCode: 1,
            direction: true,
            poolAddress: 0x2F62f2B4c5fcd7570a709DeC05D68EA19c82A9ec,
            tokenIn: 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE,
            tokenOut: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            fee: 3000
        });

        localSegments[1] = RouteSegment({
            providerCode: 4,
            direction: false,
            poolAddress: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            tokenIn: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            tokenOut: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            fee: 0
        });

        return localSegments;
    }

    function testReadStringFromApp() public pure {
        bytes
            memory data = hex"0201012f62f2b4c5fcd7570a709dec05d68ea19c82a9ec95ad61b0a150d79219dcf64e1e6cc01f0b64c4cec02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000bb80400c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeec02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000";
        uint256 stream = InputStream.createStream(data);

        RouteSegment[] memory route = createData();

        assertEq(
            stream.readUint8(),
            route.length,
            "segmentCount should return the correct uint8"
        );

        for (uint256 index = 0; index < route.length; index++) {
            assertEq(
                stream.readUint8(),
                route[index].providerCode,
                "providerCode should return the correct uint8"
            );
            assertEq(
                stream.readUint8() > 0,
                route[index].direction,
                "direction should return the correct uint8"
            );
            assertEq(
                stream.readAddress(),
                route[index].poolAddress,
                "poolAddress should return the correct address"
            );
            assertEq(
                stream.readAddress(),
                route[index].tokenIn,
                "tokenIn should return the correct address"
            );
            assertEq(
                stream.readAddress(),
                route[index].tokenOut,
                "tokenOut should return the correct address"
            );
            assertEq(
                stream.readUint24(),
                route[index].fee,
                "tokenOut should return the correct address"
            );
        }
    }
}
