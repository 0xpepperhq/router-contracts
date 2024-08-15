// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/PepperRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable tokenDecimals;
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        tokenDecimals = _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
}

contract MockPepperRouteProcessor {
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address,
        uint256,
        address,
        bytes memory
    ) external payable returns (uint256 amountOut) {
        return amountIn; // Return the same amount for testing purposes
    }
}

contract PepperRouterTest is Test {
    PepperRouter public pepperRouter;
    MockPepperRouteProcessor public mockPepperRouteProcessor;
    MockERC20 public mockERC20;

    address owner = address(0x1);
    address addr1 = address(0x2);
    address addr2 = address(0x3);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock ERC20 token
        mockERC20 = new MockERC20("Mock Token", "MKT", 18);
        mockERC20.mint(addr1, 1000 ether);

        // Deploy mock PepperRouteProcessor
        mockPepperRouteProcessor = new MockPepperRouteProcessor();

        // Deploy the PepperRouter
        pepperRouter = new PepperRouter(address(mockPepperRouteProcessor));

        vm.stopPrank();
    }

    function testSetPepperRouteProcessor() public {
        vm.prank(owner);
        pepperRouter.updatePepperRouteProcessor(addr2);
        assertEq(pepperRouter.pepperRouteProcessor(), addr2);
    }

    function testFailSetPepperRouteProcessorNotOwner() public {
        vm.prank(addr1);
        pepperRouter.updatePepperRouteProcessor(addr2);
    }

    function testForwardERC20Transfer() public {
        uint256 amountIn = 10 ether;

        vm.startPrank(addr1);
        mockERC20.approve(address(pepperRouter), amountIn);

        uint256 amountOut = pepperRouter.forward(
            address(mockERC20),
            amountIn,
            address(mockERC20),
            0,
            addr2,
            ""
        );

        assertEq(amountOut, amountIn);
        vm.stopPrank();
    }

    function testForwardETHTransfer() public {
        uint256 amountIn = 5 ether;

        vm.deal(addr1, 10 ether);

        vm.startPrank(addr1);

        uint256 amountOut = pepperRouter.forward{value: amountIn}(
            address(0),
            amountIn,
            address(0),
            0,
            addr2,
            ""
        );

        assertEq(amountOut, amountIn);
        vm.stopPrank();
    }

    function testFailForwardIncorrectETHAmount() public {
        uint256 amountIn = 5 ether;

        vm.deal(addr1, 10 ether);

        vm.startPrank(addr1);
        pepperRouter.forward{value: 3 ether}(
            address(0),
            amountIn,
            address(0),
            0,
            addr2,
            ""
        );
        vm.stopPrank();
    }

    function testWithdrawERC20Tokens() public {
        uint256 amountIn = 10 ether;

        vm.startPrank(addr1);
        mockERC20.transfer(address(pepperRouter), amountIn);
        vm.stopPrank();

        vm.prank(owner);
        pepperRouter.withdrawTokens(address(mockERC20), addr2, amountIn);

        assertEq(mockERC20.balanceOf(addr2), amountIn);
    }

    function testFailWithdrawERC20TokensNotOwner() public {
        uint256 amountIn = 10 ether;

        vm.startPrank(addr1);
        mockERC20.transfer(address(pepperRouter), amountIn);
        vm.stopPrank();

        vm.prank(addr1);
        pepperRouter.withdrawTokens(address(mockERC20), addr2, amountIn);
    }

    function testWithdrawETH() public {
        uint256 amountIn = 2 ether;

        vm.deal(address(pepperRouter), amountIn);

        vm.prank(owner);
        pepperRouter.withdrawETH(payable(addr2), amountIn);

        assertEq(addr2.balance, amountIn);
    }

    function testFailWithdrawETHNotOwner() public {
        uint256 amountIn = 2 ether;

        vm.deal(address(pepperRouter), amountIn);

        vm.prank(addr1);
        pepperRouter.withdrawETH(payable(addr2), amountIn);
    }
}
