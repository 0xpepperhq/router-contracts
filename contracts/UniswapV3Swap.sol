// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract UniswapV3Swap {
    ISwapRouter public immutable swapRouter;
    uint24 public constant poolFee = 3000;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
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
