// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PepperRouter is Ownable {
    using SafeERC20 for IERC20;

    address public pepperRouteProcessor;

    event PepperRouteProcessorUpdated(address indexed newProcessor);

    constructor(address _pepperRouteProcessor) Ownable(msg.sender) {
        require(_pepperRouteProcessor != address(0), "Invalid PepperRouteProcessor address");
        pepperRouteProcessor = _pepperRouteProcessor;
    }

    /// @notice Allows the owner to update the address of the PepperRouteProcessor contract
    /// @param _newProcessor The address of the new PepperRouteProcessor contract
    function updatePepperRouteProcessor(address _newProcessor) external onlyOwner {
        require(_newProcessor != address(0), "Invalid PepperRouteProcessor address");
        pepperRouteProcessor = _newProcessor;
        emit PepperRouteProcessorUpdated(_newProcessor);
    }

    /// @notice Forwards the call and tokens to the PepperRouteProcessor contract
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @param to Address to receive the output tokens
    /// @param route Encoded route segments
    function forward(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes calldata route
    ) external payable returns (uint256 amountOut) {
        if (tokenIn == address(0)) {
            // Handling native token (e.g., ETH)
            require(msg.value == amountIn, "Incorrect ETH amount sent");
            // Forward the call with the ETH amount
            (bool success, bytes memory returnData) = pepperRouteProcessor.call{value: msg.value}(
                abi.encodeWithSignature(
                    "processRoute(address,uint256,address,uint256,address,bytes)",
                    address(0),
                    amountIn,
                    tokenOut,
                    amountOutMin,
                    to,
                    route
                )
            );
            require(success, "PepperRouteProcessor call failed");
            amountOut = abi.decode(returnData, (uint256));
        } else {
            // Handling ERC20 token
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenIn).approve(pepperRouteProcessor, amountIn);

            // Forward the call without ETH amount
            (bool success, bytes memory returnData) = pepperRouteProcessor.call(
                abi.encodeWithSignature(
                    "processRoute(address,uint256,address,uint256,address,bytes)",
                    tokenIn,
                    amountIn,
                    tokenOut,
                    amountOutMin,
                    to,
                    route
                )
            );
            require(success, "PepperRouteProcessor call failed");
            amountOut = abi.decode(returnData, (uint256));
        }
    }

    /// @notice Allows the owner to withdraw any stuck tokens
    /// @param token Address of the token to withdraw
    /// @param to Address to receive the withdrawn tokens
    /// @param amount Amount of the token to withdraw
    function withdrawTokens(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /// @notice Allows the owner to withdraw any stuck ETH
    /// @param to Address to receive the withdrawn ETH
    /// @param amount Amount of ETH to withdraw
    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient ETH balance");
        (bool success, ) = to.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}
