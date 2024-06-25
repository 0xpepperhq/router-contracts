// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract PepperSwapV1 is Ownable, ReentrancyGuard, Pausable {
    ISwapRouter public immutable swapRouter;
    uint24 public constant poolFee = 3000;
    address public feeTo;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @notice Update the update fee to address
    function updateFeeTo(address _feeTo) public onlyOwner {
        feeTo = _feeTo;
    }

    function approve(address token, address to, uint256 amount) public onlyOwner {
        IERC20(token).approve(to, amount);
    }

    /// @notice Pause the router execution
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the router execution
    function unpause() external onlyOwner {
        _unpause();
    }

    function swapExactInputSingle(uint256 amountIn, address tokenIn, address tokenOut)
        external
        returns (uint256 amountOut)
    {
        // msg.sender must approve this contract

        // Transfer the specified amount of tokenIn to this contract.
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);

        // Approve the router to spend tokenIn.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            // TODO - get the amountOutMinimum from an function argument
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapExactOutputSingle(uint256 amountOut, uint256 amountInMaximum, address tokenIn, address tokenOut)
        external
        returns (uint256 amountIn)
    {
        // Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountInMaximum);

        // Approve the router to spend the specifed `amountInMaximum` of tokenIn.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to acheive a better swap.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum,
            sqrtPriceLimitX96: 0
        });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), 0);
            TransferHelper.safeTransfer(tokenIn, msg.sender, amountInMaximum - amountIn);
        }
    }

    function swapExactInputMultihop(uint256 amountIn, address[] calldata path) external returns (uint256 amountOut) {
        require(path.length >= 2, "Path must have at least two tokens");

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(path[0], address(swapRouter), amountIn);

        bytes memory pathBytes = encodePath(path);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: pathBytes,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        amountOut = swapRouter.exactInput(params);
    }

    function swapExactOutputMultihop(uint256 amountOut, uint256 amountInMaximum, address[] calldata path)
        external
        returns (uint256 amountIn)
    {
        require(path.length >= 2, "Path must have at least two tokens");

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(this), amountInMaximum);
        TransferHelper.safeApprove(path[0], address(swapRouter), amountInMaximum);

        bytes memory pathBytes = encodePath(reversePath(path));

        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: pathBytes,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMaximum
        });

        amountIn = swapRouter.exactOutput(params);

        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(path[0], address(swapRouter), 0);
            TransferHelper.safeTransfer(path[0], msg.sender, amountInMaximum - amountIn);
        }
    }

    function encodePath(address[] memory path) internal pure returns (bytes memory) {
        bytes memory pathBytes;
        for (uint256 i = 0; i < path.length - 1; i++) {
            pathBytes = abi.encodePacked(pathBytes, path[i], uint24(poolFee));
        }
        pathBytes = abi.encodePacked(pathBytes, path[path.length - 1]);
        return pathBytes;
    }

    function reversePath(address[] memory path) internal pure returns (address[] memory) {
        address[] memory reversed = new address[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            reversed[i] = path[path.length - 1 - i];
        }
        return reversed;
    }
}
