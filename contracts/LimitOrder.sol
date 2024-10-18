// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PepperRouteProcessor} from "./PepperRouteProcessor.sol";

contract LimitOrder is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    PepperRouteProcessor public routeProcessor;

    uint256 constant FEE_BASIS_POINTS = 25; // For 0.25% fee

    enum OrderStatus {
        Open,
        Completed,
        Cancelled
    }

    enum OrderType {
        Maker,
        Taker
    }

    event OrderCreated(
        uint256 indexed orderId,
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minimumAmountOut
    );
    event OrderExecuted(uint256 indexed orderId);
    event OrderCancelled(uint256 indexed orderId);
    event OrderExpired(uint256 indexed orderId);
    event TakeOrderFullExecuted(
        uint256 indexed makerOrderId,
        uint256 indexed takerOrderId
    );
    event TakeOrderPartialExecuted(
        uint256 indexed makerOrderId,
        uint256 indexed takerOrderId
    );

    struct OrderSimple {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minimumAmountOut;
    }

    struct Order {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 remainingAmountIn;
        uint256 minimumAmountOut;
        OrderType orderType;
        OrderStatus status;
    }

    mapping(uint256 => Order) public orders; // Mapping from order ID to Order
    uint256[] public openOrderIds; // List of open order IDs
    // Counter for generating unique order IDs
    uint256 public nextOrderId;

    modifier onlyOrderOwner(uint256 orderId) {
        require(
            orders[orderId].user == msg.sender,
            "LimitOrder: Only order owner can call"
        );
        _;
    }

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
        OrderSimple memory order
    ) external nonReentrant returns (uint256) {
        return createOrderInternal(order, OrderType.Maker);
    }

    function createOrderInternal(
        OrderSimple memory simpleOrder,
        OrderType orderType
    ) internal returns (uint256 orderId) {
        IERC20(simpleOrder.tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            simpleOrder.amountIn
        );

        orderId = nextOrderId;
        orders[orderId] = Order({
            user: msg.sender,
            tokenIn: simpleOrder.tokenIn,
            tokenOut: simpleOrder.tokenOut,
            amountIn: simpleOrder.amountIn,
            remainingAmountIn: orderType == OrderType.Maker
                ? simpleOrder.minimumAmountOut
                : 0,
            minimumAmountOut: simpleOrder.minimumAmountOut,
            orderType: orderType,
            status: orderType == OrderType.Maker
                ? OrderStatus.Open
                : OrderStatus.Completed
        });

        if (orderType == OrderType.Maker) {
            openOrderIds.push(orderId);
        }

        emit OrderCreated(
            orderId,
            msg.sender,
            simpleOrder.tokenIn,
            simpleOrder.tokenOut,
            simpleOrder.amountIn,
            simpleOrder.minimumAmountOut
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
    ) external nonReentrant {
        require(orderId < nextOrderId, "Invalid order ID");
        require(
            orders[orderId].user != msg.sender,
            "Taker cannot be the maker"
        );
        require(
            orders[orderId].status == OrderStatus.Open,
            "Order is not in open state"
        );

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

        uint fee = (amountOut * FEE_BASIS_POINTS) / 10_000;

        IERC20(orders[orderId].tokenOut).safeTransfer(
            orders[orderId].user,
            amountOut - fee
        );

        IERC20(orders[orderId].tokenOut).safeTransfer(msg.sender, fee / 2);
        IERC20(orders[orderId].tokenOut).safeTransfer(owner(), fee / 2);

        orders[orderId].status = OrderStatus.Completed;
        emit OrderExecuted(orderId);
    }

    /**
     * @notice This function handles the logic for cancelling a limit order.
     * @param orderId The unique identifier for the limit order to be processed.
     */
    function cancelOrder(
        uint256 orderId
    ) external onlyOrderOwner(orderId) nonReentrant {
        require(orderId < nextOrderId, "Invalid order ID");
        require(
            orders[orderId].status != OrderStatus.Completed &&
                orders[orderId].status != OrderStatus.Cancelled,
            "Order is already completed or cancelled"
        );

        IERC20(orders[orderId].tokenIn).safeTransfer(
            orders[orderId].user,
            orders[orderId].amountIn
        );

        orders[orderId].status = OrderStatus.Cancelled;
        removeOpenOrderId(orderId);
        emit OrderCancelled(orderId);
    }

    /**
     * @notice This function handles the logic for matching a limit order.
     * @param makeOrder The Order to match against.
     */
    function takeOrderFull(
        Order storage makeOrder
    ) internal returns (uint256 takerOrderId) {
        require(
            makeOrder.status == OrderStatus.Open,
            "Order is not in open state"
        );
        require(
            IERC20(makeOrder.tokenOut).balanceOf(msg.sender) >=
                makeOrder.minimumAmountOut,
            "Taker does not have enough out token to complete trade"
        );

        OrderSimple memory takerOrder = OrderSimple({
            user: msg.sender,
            tokenIn: makeOrder.tokenOut,
            tokenOut: makeOrder.tokenIn,
            amountIn: makeOrder.minimumAmountOut,
            minimumAmountOut: makeOrder.amountIn
        });

        takerOrderId = createOrderInternal(takerOrder, OrderType.Taker);
        uint256 takerFee = (makeOrder.amountIn * FEE_BASIS_POINTS) / 10_000;
        IERC20(makeOrder.tokenIn).safeTransfer(
            msg.sender,
            makeOrder.amountIn - takerFee
        );

        IERC20(makeOrder.tokenOut).safeTransfer(
            makeOrder.user,
            makeOrder.minimumAmountOut
        );

        IERC20(makeOrder.tokenIn).safeTransfer(owner(), takerFee);
        makeOrder.remainingAmountIn = 0;
    }

    /**
     * @notice This function handles the logic for partially matching a limit order.
     * @param amountToTake The amount of the order to take.
     * @param makeOrder The Order to match against.
     */
    function takeOrderPartial(
        uint256 amountToTake,
        Order storage makeOrder
    ) internal returns (uint256 takerOrderId) {
        require(makeOrder.status == OrderStatus.Open, "Order is not open");
        require(makeOrder.user != msg.sender, "Cannot take your own order");
        require(amountToTake > 0, "Amount must be greater than zero");
        require(
            amountToTake <= makeOrder.remainingAmountIn,
            "Amount exceeds available order amount"
        );

        // Calculate proportional minimum amount out
        uint256 proportionalMinimumAmountOut = (makeOrder.minimumAmountOut *
            amountToTake) / makeOrder.amountIn;

        require(
            IERC20(makeOrder.tokenOut).balanceOf(msg.sender) >=
                proportionalMinimumAmountOut,
            "Taker does not have enough out token to complete trade"
        );

        OrderSimple memory takerOrder = OrderSimple({
            user: msg.sender,
            tokenIn: makeOrder.tokenOut,
            tokenOut: makeOrder.tokenIn,
            amountIn: proportionalMinimumAmountOut,
            minimumAmountOut: amountToTake
        });

        takerOrderId = createOrderInternal(takerOrder, OrderType.Taker);

        uint256 takerFee = (amountToTake * FEE_BASIS_POINTS) / 10_000;

        IERC20(makeOrder.tokenIn).safeTransfer(
            msg.sender,
            amountToTake - takerFee
        );

        IERC20(makeOrder.tokenOut).safeTransfer(
            makeOrder.user,
            proportionalMinimumAmountOut
        );

        IERC20(makeOrder.tokenIn).safeTransfer(owner(), takerFee);

        makeOrder.remainingAmountIn -= amountToTake;
    }

    /**
     * @notice This function allows a user to take an order.
     * @param orderId The unique identifier for the limit order to be processed.
     * @param amount The amount of the order to take.
     */
    function takeOrder(uint256 orderId, uint256 amount) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order is not in open state");
        require(orderId < nextOrderId, "Invalid order ID");
        require(
            order.orderType == OrderType.Maker,
            "Cannot take a taker order"
        );

        uint256 takerOrderId;
        if (amount >= order.remainingAmountIn) {
            takerOrderId = takeOrderFull(order);
        } else {
            takerOrderId = takeOrderPartial(amount, order);
        }

        if (order.remainingAmountIn == 0) {
            removeOpenOrderId(orderId);
            order.status = OrderStatus.Completed;
            emit TakeOrderFullExecuted(orderId, takerOrderId);
        } else {
            emit TakeOrderPartialExecuted(orderId, takerOrderId);
        }
    }

    /**
     * @notice This function allows a user to get all open orders.
     * @return openOrders An array of open orders.
     */
    function getOpenOrders() external view returns (Order[] memory) {
        Order[] memory openOrders = new Order[](openOrderIds.length);
        for (uint256 i = 0; i < openOrderIds.length; i++) {
            openOrders[i] = orders[openOrderIds[i]];
        }

        return openOrders;
    }

    /**
     * @notice Removes an order ID from the list of open orders.
     * @param orderId The order ID to remove from the open order list.
     */
    function removeOpenOrderId(uint256 orderId) internal {
        for (uint256 i = 0; i < openOrderIds.length; i++) {
            if (openOrderIds[i] == orderId) {
                openOrderIds[i] = openOrderIds[openOrderIds.length - 1];
                openOrderIds.pop();
                break;
            }
        }
    }
}
