// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

struct RouteSegment {
    uint8 providerCode;
    bool direction;
    address poolAddress;
    address tokenIn;
    address tokenOut;
    uint24 fee;
}

address constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
/// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
uint160 constant MIN_SQRT_RATIO = 4295128739;
/// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
uint160 constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

interface IPepperRouteProcessor {
    event Route(
        address indexed from,
        address to,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 amountOut
    );

    error MinimalOutputBalanceViolation(uint256 amountOut);
    error MinimalInputBalanceViolation(uint256 amountIn);
    error UnknownPoolCode(uint8 poolCode);
    error NativeTokenTransferFailed(address to, uint256 amount);
    error InvalidPoolReserves(uint256 amountZero, uint256 amountOne);

    /// @notice Processes the route generated off-chain. Has a lock
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @param to Address to receive the output tokens
    /// @param route Route segments
    /// @return amountOut Actual amount of the output token
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) external payable returns (uint256 amountOut);
}
