// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct RouteSegment {
    uint8 providerCode;
    bool direction;
    address poolAddress;
    address tokenIn;
    address tokenOut;
    uint24 fee;
}
