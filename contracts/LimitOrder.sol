// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PepperRouteProcessor} from "./PepperRouteProcessor.sol";

interface IERC20Extended is IERC20 {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}

contract LimitOrder is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20Extended;
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
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minimumAmountOut
    );
    event OrderExecuted(uint256 indexed orderId);
    event OrderCancelled(uint256 indexed orderId);
    event TakeOrderExecuted(
        uint256 indexed makerOrderId,
        address indexed taker,
        uint256 amountFilled,
        uint256 remainingAmount
    );

    struct OrderSimple {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minimumAmountOut;
    }

    struct Order {
        address user;
        address tokenIn;
        address tokenOut;
        uint8 tokenInDecimals;
        uint8 tokenOutDecimals;
        string tokenInSymbol;
        string tokenOutSymbol;
        uint256 amountIn;
        uint256 remainingAmountIn;
        uint256 minimumAmountOut;
        uint256 orderId;
        OrderType orderType;
        OrderStatus status;
    }

    mapping(uint256 => Order) public orders; // Mapping from order ID to Order
    uint256[] public openOrderIds; // List of open order IDs
    mapping(uint256 => uint256) private orderIdToIndex; // Mapping from order ID to its index in openOrderIds
    uint256 public nextOrderId; // Counter for generating unique order IDs

    modifier onlyOrderOwner(uint256 orderId) {
        require(
            orders[orderId].user == msg.sender,
            "LimitOrder: Only order owner can call"
        );
        _;
    }

    /// @notice Initializes the contract with the given owner and route processor address.
    /// @param initialOwner The address of the initial owner of the contract.
    /// @param routeProcessorAddress The address of the PepperRouteProcessor contract.
    constructor(
        address initialOwner,
        address payable routeProcessorAddress
    ) Ownable(initialOwner) {
        transferOwnership(initialOwner);
        routeProcessor = PepperRouteProcessor(routeProcessorAddress);
    }

    /// @notice Create a new limit order.
    /// @param order The order to be created.
    /// @return orderId The ID of the newly created order.
    function createOrder(
        OrderSimple memory order
    ) external nonReentrant returns (uint256) {
        return createOrderInternal(order, OrderType.Maker);
    }

    function createOrderInternal(
        OrderSimple memory simpleOrder,
        OrderType orderType
    ) internal returns (uint256 orderId) {
        require(
            simpleOrder.amountIn > 0,
            "Order amount must be greater than zero"
        );
        require(
            simpleOrder.minimumAmountOut > 0,
            "Minimum amount out must be greater than zero"
        );

        IERC20Extended tokenIn = IERC20Extended(simpleOrder.tokenIn);
        IERC20Extended tokenOut = IERC20Extended(simpleOrder.tokenOut);

        tokenIn.safeTransferFrom(
            msg.sender,
            address(this),
            simpleOrder.amountIn
        );

        uint8 tokenInDecimals = tokenIn.decimals();
        uint8 tokenOutDecimals = tokenOut.decimals();

        orderId = nextOrderId;
        orders[orderId] = Order({
            user: msg.sender,
            tokenIn: simpleOrder.tokenIn,
            tokenOut: simpleOrder.tokenOut,
            tokenInDecimals: tokenInDecimals,
            tokenOutDecimals: tokenOutDecimals,
            tokenInSymbol: tokenIn.symbol(),
            tokenOutSymbol: tokenOut.symbol(),
            amountIn: simpleOrder.amountIn,
            remainingAmountIn: orderType == OrderType.Maker
                ? simpleOrder.amountIn
                : 0,
            minimumAmountOut: simpleOrder.minimumAmountOut,
            orderId: orderId,
            orderType: orderType,
            status: orderType == OrderType.Maker
                ? OrderStatus.Open
                : OrderStatus.Completed
        });

        if (orderType == OrderType.Maker) {
            openOrderIds.push(orderId);
            orderIdToIndex[orderId] = openOrderIds.length - 1;
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

    /// @notice Executes an order.
    /// @param orderId The ID of the order to be executed.
    /// @param routeData The data required by the route processor to execute the swap.
    function executeOrder(
        uint256 orderId,
        bytes memory routeData
    ) external nonReentrant {
        require(orderId < nextOrderId, "Invalid order ID");
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order is not in open state");

        // Optional: Prevent self-execution if desired
        // require(order.user != msg.sender, "Cannot execute your own order");

        IERC20Extended tokenOut = IERC20Extended(order.tokenOut);

        uint256 initialBalance = tokenOut.balanceOf(address(this));

        // Update state before external calls to prevent reentrancy
        order.status = OrderStatus.Completed;
        removeOpenOrderId(orderId);

        // Process the swap
        uint256 amountOut = routeProcessor.processRoute(
            order.tokenIn,
            order.amountIn,
            order.tokenOut,
            order.minimumAmountOut,
            address(this),
            routeData
        );

        uint256 finalBalance = tokenOut.balanceOf(address(this));
        uint256 receivedAmount = finalBalance - initialBalance;

        require(
            receivedAmount >= order.minimumAmountOut,
            "Insufficient output amount"
        );

        uint256 fee = calculateFee(receivedAmount);
        if (fee == 0 && receivedAmount > 0) {
            fee = 1; // Set minimum fee to 1 unit
        }

        uint256 netAmountOut = receivedAmount - fee;

        // Transfer net amount to order.user
        tokenOut.safeTransfer(order.user, netAmountOut);

        // Distribute fee equally between executor and owner
        uint256 feeForExecutor = fee / 2;
        uint256 feeForOwner = fee - feeForExecutor; // Avoid rounding issues

        tokenOut.safeTransfer(msg.sender, feeForExecutor);
        tokenOut.safeTransfer(owner(), feeForOwner);

        emit OrderExecuted(orderId);
    }

    /// @notice Cancels a limit order.
    /// @param orderId The unique identifier for the limit order to be canceled.
    function cancelOrder(
        uint256 orderId
    ) external onlyOrderOwner(orderId) nonReentrant {
        require(orderId < nextOrderId, "Invalid order ID");
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order is not in open state");

        // Update state before external calls
        order.status = OrderStatus.Cancelled;
        removeOpenOrderId(orderId);

        IERC20Extended tokenIn = IERC20Extended(order.tokenIn);
        tokenIn.safeTransfer(order.user, order.remainingAmountIn);

        emit OrderCancelled(orderId);
    }

    /// @notice Allows a user to take an order.
    /// @param orderId The unique identifier for the limit order to be processed.
    /// @param amount The amount of the order to take.
    function takeOrder(uint256 orderId, uint256 amount) external nonReentrant {
        require(orderId < nextOrderId, "Invalid order ID");
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Open, "Order is not in open state");
        require(
            order.orderType == OrderType.Maker,
            "Cannot take a taker order"
        );
        require(amount > 0, "Amount must be greater than zero");
        require(
            amount <= order.remainingAmountIn,
            "Amount exceeds available order amount"
        );

        IERC20Extended tokenIn = IERC20Extended(order.tokenIn);
        IERC20Extended tokenOut = IERC20Extended(order.tokenOut);

        uint256 proportionalMinimumAmountOut = calculateProportionalAmountOut(
            amount,
            order.amountIn,
            order.minimumAmountOut,
            order.tokenInDecimals,
            order.tokenOutDecimals
        );

        // Ensure taker has enough balance and allowance
        require(
            tokenOut.balanceOf(msg.sender) >= proportionalMinimumAmountOut,
            "Insufficient tokenOut balance"
        );
        require(
            tokenOut.allowance(msg.sender, address(this)) >=
                proportionalMinimumAmountOut,
            "Insufficient tokenOut allowance"
        );

        uint256 fee = calculateFee(amount);
        if (fee == 0 && amount > 0) {
            fee = 1; // Set minimum fee to 1 unit
        }
        uint256 netAmountIn = amount - fee;

        // Update order state before external calls to prevent reentrancy
        order.remainingAmountIn -= amount;
        if (order.remainingAmountIn == 0) {
            order.status = OrderStatus.Completed;
            removeOpenOrderId(orderId);
        }

        // Transfer tokenOut from taker to contract
        tokenOut.safeTransferFrom(
            msg.sender,
            address(this),
            proportionalMinimumAmountOut
        );

        // Transfer net tokenIn to taker
        tokenIn.safeTransfer(msg.sender, netAmountIn);

        // Transfer fee to owner
        tokenIn.safeTransfer(owner(), fee);

        // Transfer tokenOut to maker
        tokenOut.safeTransfer(order.user, proportionalMinimumAmountOut);

        emit TakeOrderExecuted(
            orderId,
            msg.sender,
            amount,
            order.remainingAmountIn
        );
    }

    /// @notice Calculates the proportional minimum amount out, adjusting for token decimals.
    /// @param amountIn The amount of tokenIn the taker wants to take.
    /// @param orderAmountIn The total amountIn of the order.
    /// @param orderMinimumAmountOut The minimum amountOut of the order.
    /// @param tokenInDecimals The decimals of tokenIn.
    /// @param tokenOutDecimals The decimals of tokenOut.
    /// @return The proportional minimum amount out, adjusted for decimals.
    function calculateProportionalAmountOut(
        uint256 amountIn,
        uint256 orderAmountIn,
        uint256 orderMinimumAmountOut,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals
    ) internal pure returns (uint256) {
        // Adjust amounts to a common base (18 decimals)
        uint256 amountInAdjusted = adjustDecimals(
            amountIn,
            tokenInDecimals,
            18
        );
        uint256 orderAmountInAdjusted = adjustDecimals(
            orderAmountIn,
            tokenInDecimals,
            18
        );
        uint256 orderMinimumAmountOutAdjusted = adjustDecimals(
            orderMinimumAmountOut,
            tokenOutDecimals,
            18
        );

        // Calculate proportional amount
        uint256 proportionalAmountOutAdjusted = (orderMinimumAmountOutAdjusted *
            amountInAdjusted) / orderAmountInAdjusted;

        // Adjust back to tokenOut decimals
        uint256 proportionalAmountOut = adjustDecimals(
            proportionalAmountOutAdjusted,
            18,
            tokenOutDecimals
        );

        return proportionalAmountOut;
    }

    /// @notice Adjusts the amount between tokens with different decimals.
    /// @param amount The amount to adjust.
    /// @param fromDecimals The decimals of the token the amount is in.
    /// @param toDecimals The decimals of the token to adjust to.
    /// @return The adjusted amount.
    function adjustDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            uint256 factor = 10 ** (fromDecimals - toDecimals);
            return amount / factor;
        } else {
            uint256 factor = 10 ** (toDecimals - fromDecimals);
            return amount * factor;
        }
    }

    /// @notice Returns all open orders.
    /// @return openOrders An array of open orders.
    function getOpenOrders() external view returns (Order[] memory) {
        Order[] memory openOrders = new Order[](openOrderIds.length);
        for (uint256 i = 0; i < openOrderIds.length; i++) {
            openOrders[i] = orders[openOrderIds[i]];
        }

        return openOrders;
    }

    /// @notice Removes an order ID from the list of open orders.
    /// @param orderId The order ID to remove from the open order list.
    function removeOpenOrderId(uint256 orderId) internal {
        uint256 index = orderIdToIndex[orderId];
        uint256 lastOrderId = openOrderIds[openOrderIds.length - 1];
        openOrderIds[index] = lastOrderId;
        orderIdToIndex[lastOrderId] = index;
        openOrderIds.pop();
        delete orderIdToIndex[orderId];
    }

    /// @notice Calculates the fee based on the provided amount.
    /// @param amount The amount to calculate the fee from.
    /// @return The calculated fee.
    function calculateFee(uint256 amount) internal pure returns (uint256) {
        return (amount * FEE_BASIS_POINTS) / 10_000;
    }
}
