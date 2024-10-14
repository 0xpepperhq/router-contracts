// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/LimitOrder.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }
}

contract PepperRouteProcessorMock {
    function processRoute(
        address,
        uint256,
        address,
        uint256,
        address,
        bytes memory
    ) external pure returns (uint256) {
        // For testing purposes, always return the minimum output amount
        return 1000;
    }
}

contract LimitOrderTest is Test {
    LimitOrder public limitOrder;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    PepperRouteProcessorMock public routeProcessor;

    address public owner = address(0x123);
    address public user = address(0x456);

    function setUp() public {
        // Deploy mock tokens
        tokenIn = new MockERC20("TokenIn", "TIN", 1_000_000 ether);
        tokenOut = new MockERC20("TokenOut", "TOUT", 1_000_000 ether);

        // Deploy mock route processor
        routeProcessor = new PepperRouteProcessorMock();

        // Deploy the LimitOrder contract with the mock route processor
        limitOrder = new LimitOrder(owner, payable(address(routeProcessor)));

        // Allocate some tokens to the user
        tokenIn.transfer(user, 10_000 ether);

        // Label addresses for easier debugging
        vm.label(owner, "Owner");
        vm.label(user, "User");
    }

    function testCreateOrder() public {
        vm.startPrank(user);

        // Approve the limitOrder contract to spend tokens
        tokenIn.approve(address(limitOrder), 1_000 ether);

        // Create an order
        LimitOrder.Order memory order = LimitOrder.Order({
            user: user,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            amountIn: 1_000 ether,
            minimumAmountOut: 500 ether,
            isExecuted: false
        });

        uint256 orderId = limitOrder.createOrder(order);

        // Verify the order details
        LimitOrder.Order memory createdOrder = limitOrder.getOrder(orderId);
        assertEq(createdOrder.user, user);
        assertEq(createdOrder.tokenIn, address(tokenIn));
        assertEq(createdOrder.tokenOut, address(tokenOut));
        assertEq(createdOrder.amountIn, 1_000 ether);
        assertEq(createdOrder.minimumAmountOut, 500 ether);
        assertFalse(createdOrder.isExecuted);

        vm.stopPrank();
    }

    function testExecuteOrder() public {
        vm.startPrank(user);

        // Approve the limitOrder contract to spend tokens
        tokenIn.approve(address(limitOrder), 1_000 ether);

        // Create an order
        LimitOrder.Order memory order = LimitOrder.Order({
            user: user,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            amountIn: 1_000 ether,
            minimumAmountOut: 500 ether,
            isExecuted: false
        });

        uint256 orderId = limitOrder.createOrder(order);

        vm.stopPrank();

        // Execute the order
        vm.startPrank(owner);
        bytes memory routeData = ""; // Mock route data
        limitOrder.executeOrder(orderId, routeData);

        // Verify that the order is marked as executed
        LimitOrder.Order memory executedOrder = limitOrder.getOrder(orderId);
        assertTrue(executedOrder.isExecuted);

        vm.stopPrank();
    }

    function testFailExecuteNonExistentOrder() public {
        vm.startPrank(owner);
        bytes memory routeData = "";
        limitOrder.executeOrder(9999, routeData); // This should fail as the order doesn't exist
        vm.stopPrank();
    }

    function testFailExecuteOrderTwice() public {
        vm.startPrank(user);

        // Approve the limitOrder contract to spend tokens
        tokenIn.approve(address(limitOrder), 1_000 ether);

        // Create an order
        LimitOrder.Order memory order = LimitOrder.Order({
            user: user,
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            amountIn: 1_000 ether,
            minimumAmountOut: 500 ether,
            isExecuted: false
        });

        uint256 orderId = limitOrder.createOrder(order);

        vm.stopPrank();

        // Execute the order
        vm.startPrank(owner);
        bytes memory routeData = "";
        limitOrder.executeOrder(orderId, routeData);

        // Attempt to execute the same order again
        limitOrder.executeOrder(orderId, routeData); // This should fail as the order is already executed

        vm.stopPrank();
    }
}
