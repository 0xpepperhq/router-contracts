// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {PepperRouteProcessor} from "./PepperRouteProcessor.sol";

contract LimitOrder is Ownable {
    using SafeERC20 for IERC20;
    PepperRouteProcessor public routeProcessor;

    event OrderCreated(
        uint256 indexed orderId,
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minimumAmountOut
    );
    event OrderExecuted(uint256 indexed orderId);

    struct Order {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minimumAmountOut;
        bool isExecuted;
    }

    mapping(uint256 => Order) public orders; // Mapping from order ID to Order
    uint256 public nextOrderId; // Counter for generating unique order IDs

    constructor(
        address initialOwner,
        address payable routeProcessorAddress
    ) Ownable(initialOwner) {
        routeProcessor = PepperRouteProcessor(routeProcessorAddress);
    }

    /**
     * @notice Create a new limit order
     * @param order The order to be created
     * @return orderId The ID of the newly created order
     */
    function createOrder(
        Order memory order
    ) external returns (uint256 orderId) {
        IERC20(order.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            order.amountIn
        );

        orderId = nextOrderId;
        orders[orderId] = Order({
            user: msg.sender,
            tokenIn: order.tokenIn,
            tokenOut: order.tokenOut,
            amountIn: order.amountIn,
            minimumAmountOut: order.minimumAmountOut,
            isExecuted: false
        });

        emit OrderCreated(
            orderId,
            msg.sender,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minimumAmountOut
        );
        nextOrderId++;
    }

    /**
     * @notice Executes an order
     * @param orderId The ID of the order to be marked as executed
     */
    function executeOrder(
        uint256 orderId,
        bytes memory routeData
    ) external onlyOwner {
        require(orderId < nextOrderId, "Invalid order ID");
        require(!orders[orderId].isExecuted, "Order already executed");

        uint256 amountOut = routeProcessor.processRoute(
            orders[orderId].tokenIn,
            orders[orderId].amountIn,
            orders[orderId].tokenOut,
            orders[orderId].minimumAmountOut,
            address(this),
            routeData
        );

        require(
            amountOut >= orders[orderId].minimumAmountOut,
            "Insufficient output amount"
        );

        IERC20(orders[orderId].tokenIn).safeTransfer(
            orders[orderId].user,
            orders[orderId].minimumAmountOut
        );

        if (amountOut > orders[orderId].minimumAmountOut) {
            IERC20(orders[orderId].tokenOut).safeTransfer(
                orders[orderId].user,
                amountOut - orders[orderId].minimumAmountOut
            );
        }

        orders[orderId].isExecuted = true;
        emit OrderExecuted(orderId);
    }

    /**
     * @notice Get details of an order
     * @param orderId The ID of the order to retrieve
     * @return order The details of the specified order
     */
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory order) {
        require(orderId < nextOrderId, "Invalid order ID");
        return orders[orderId];
    }
}
