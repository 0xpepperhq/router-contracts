// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IWETH} from "./interfaces/IWETH.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {InputStream} from "./InputStream.sol";

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

contract PepperRouter is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;
    using InputStream for uint256;

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

    address public feeTo;

    constructor(address _feeTo) Ownable(msg.sender) {
        updateFeeTo(_feeTo);
    }

    /// @notice For native unwrapping
    receive() external payable {}

    /// @notice Update the update fee to address
    function updateFeeTo(address _feeTo) public onlyOwner {
        feeTo = _feeTo;
    }

    /// @notice Pause the router execution
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the router execution
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Processes the route generated off-chain. Has a lock
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @return amountOut Actual amount of the output token
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes memory route
    ) external payable nonReentrant whenNotPaused returns (uint256 amountOut) {
        RouteSegment[] memory routeSegments = streamToRouteSegment(route);
        transferAssetFromCaller(msg.sender, tokenIn, amountIn);
        amountOut = processRouteInternal(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            to,
            routeSegments
        );
        transferAssetToCaller(to, tokenOut, amountOut);
    }

    /// @notice Applies ERC-2612 permit
    /// @param tokenIn permitted token
    /// @param stream Streamed program
    function applyPermit(address tokenIn, uint256 stream) private {
        uint256 value = stream.readUint();
        uint256 deadline = stream.readUint();
        uint8 v = stream.readUint8();
        bytes32 r = stream.readBytes32();
        bytes32 s = stream.readBytes32();
        IERC20Permit(tokenIn).permit(
            msg.sender,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );
    }

    /// @notice Processes the route generated off-chain
    /// @param tokenIn Address of the input token
    /// @param amountIn Amount of the input token
    /// @param tokenOut Address of the output token
    /// @param amountOutMin Minimum amount of the output token
    /// @return amountOut Actual amount of the output token
    function processRouteInternal(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        RouteSegment[] memory route
    ) private returns (uint256 amountOut) {
        uint256 balanceInInitial = tokenIn == NATIVE_ADDRESS
            ? address(this).balance
            : IERC20(tokenIn).balanceOf(address(this));

        uint256 balanceOutInitial = tokenOut == NATIVE_ADDRESS
            ? address(to).balance
            : IERC20(tokenOut).balanceOf(to);

        uint256 realAmountIn = amountIn;
        {
            uint256 amount = amountIn;
            for (uint256 index = 0; index < route.length; index++) {
                RouteSegment memory segment = route[index];
                if (segment.providerCode == 1) {
                    amount = swapUniswapV3(
                        segment.poolAddress,
                        segment.direction,
                        to,
                        segment.tokenIn,
                        amount
                    );
                } else if (
                    segment.providerCode == 2 || segment.providerCode == 3
                ) {
                    amount = swapUniswapV2(
                        segment.poolAddress,
                        segment.direction,
                        to,
                        segment.fee,
                        segment.tokenIn,
                        amount
                    );
                } else if (segment.providerCode == 4) {
                    amount = wrapNative(
                        segment.poolAddress,
                        segment.direction,
                        to,
                        amount
                    );
                } else {
                    revert UnknownPoolCode(segment.providerCode);
                }
            }
        }

        uint256 balanceInFinal = tokenIn == NATIVE_ADDRESS
            ? address(this).balance
            : IERC20(tokenIn).balanceOf(address(this));
        if (balanceInInitial < balanceInFinal + amountIn) {
            revert MinimalInputBalanceViolation(
                balanceInFinal - balanceInInitial
            );
        }

        uint256 balanceOutFinal = tokenOut == NATIVE_ADDRESS
            ? address(to).balance
            : IERC20(tokenOut).balanceOf(to);
        if (balanceOutFinal < balanceOutInitial + amountOutMin) {
            revert MinimalOutputBalanceViolation(
                balanceOutFinal - balanceOutInitial
            );
        }

        amountOut = balanceOutFinal - balanceOutInitial;

        emit Route(
            msg.sender,
            to,
            tokenIn,
            tokenOut,
            realAmountIn,
            amountOutMin,
            amountOut
        );
    }

    function streamToRouteSegment(
        bytes memory data
    ) private pure returns (RouteSegment[] memory segments) {
        uint256 stream = InputStream.createStream(data);

        uint8 segmentsCount = stream.readUint8();
        segments = new RouteSegment[](segmentsCount);

        for (uint8 index = 0; index < segmentsCount; index++) {
            segments[index] = RouteSegment({
                providerCode: stream.readUint8(),
                direction: stream.readUint8() > 0,
                poolAddress: stream.readAddress(),
                tokenIn: stream.readAddress(),
                tokenOut: stream.readAddress(),
                fee: stream.readUint24()
            });
        }

        return segments;
    }

    function transferAssetFromCaller(
        address from,
        address tokenIn,
        uint256 amountIn
    ) private {
        if (tokenIn == NATIVE_ADDRESS) {
            require(msg.value == amountIn, "Incorrect ETH amount sent");
            // ETH is automatically transferred to the contract
        } else {
            IERC20(tokenIn).safeTransferFrom(from, address(this), amountIn);
        }
    }

    function transferAssetToCaller(
        address to,
        address tokenOut,
        uint256 amountOut
    ) private {
        if (tokenOut == NATIVE_ADDRESS) {
            (bool success, ) = payable(to).call{value: amountOut}("");
            if (!success) {
                revert NativeTokenTransferFailed(to, amountOut);
            }
        } else {
            IERC20(tokenOut).safeTransfer(to, amountOut);
        }
    }

    /// @notice UniswapV2 pool swap
    /// @param pool Address of the UniswapV2 pool
    /// @param direction Direction of the swap
    /// @param to Address to receive the output tokens
    /// @param fee Fee for the swap
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function swapUniswapV2(
        address pool,
        bool direction,
        address to,
        uint24 fee,
        address tokenIn,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransfer(pool, amountIn);

        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pool).getReserves();
        if (r0 == 0 || r1 == 0) revert InvalidPoolReserves(r0, r1);
        (uint256 reserveIn, uint256 reserveOut) = direction
            ? (r0, r1)
            : (r1, r0);
        amountIn = IERC20(tokenIn).balanceOf(pool) - reserveIn; // tokens already were transferred

        uint256 amountInWithFee = amountIn * (1_000_000 - fee);
        amountOut =
            (amountInWithFee * reserveOut) /
            (reserveIn * 1_000_000 + amountInWithFee);
        (uint256 amount0Out, uint256 amount1Out) = direction
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        IUniswapV2Pair(pool).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    /// @notice UniswapV3 pool swap
    /// @param pool Address of the UniswapV3 pool
    /// @param direction Direction of the swap
    /// @param recipient Address to receive the output tokens
    /// @param tokenIn Input token
    /// @param amountIn Amount of tokenIn to take for swap
    function swapUniswapV3(
        address pool,
        bool direction,
        address recipient,
        address tokenIn,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        // approve the pool to spend the tokenIn
        IERC20(tokenIn).approve(pool, amountIn);
        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            recipient,
            direction,
            int256(amountIn),
            direction ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );

        amountOut = direction ? uint256(amount1) : uint256(amount0);
    }

    /// @notice Wraps/unwraps native token
    /// @param wrapToken Address of the wrapped token (e.g., WETH)
    /// @param direction Direction of wrapping (true for wrap, false for unwrap)
    /// @param to Address to receive the output tokens
    /// @param amountIn Amount of tokenIn to take for wrap/unwrap
    function wrapNative(
        address wrapToken,
        bool direction,
        address to,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        if (direction) {
            // wrap native
            IWETH(wrapToken).deposit{value: amountIn}();
            amountOut = amountIn;
        } else {
            // unwrap native
            IWETH(wrapToken).withdraw(amountIn);
            (bool success, ) = payable(to).call{value: amountIn}("");
            if (!success) {
                revert NativeTokenTransferFailed(to, amountIn);
            }
            amountOut = amountIn;
        }
    }
}
