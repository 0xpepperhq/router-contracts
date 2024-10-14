// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../contracts/PepperRouteProcessor.sol";
import "../contracts/interfaces/IWETH.sol";

contract PepperRouteProcessorTest is Test {
    PepperRouteProcessor private processor;
    IERC20 private token;
    IWETH private weth;

    address private owner = address(this);
    address private user = address(0x1234);
    address private tokenIn = address(0x12345);
    address private tokenOut = address(0x54321);
    address private bentoBoxAddress = address(0x18945);
    address private wethAddress =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    function setUp() public {
        token = IERC20(tokenIn);
        weth = IWETH(wethAddress);

        address[] memory privilegedUsers = new address[](1);
        privilegedUsers[0] = user;

        processor = new PepperRouteProcessor(owner, privilegedUsers);

        // Setting up initial balances for tests
        vm.deal(user, 10 ether);
        deal(tokenIn, user, 1000 ether);
        deal(tokenOut, address(processor), 1000 ether);
    }

    function testInitialSetup() public {
        assertTrue(
            processor.priviledgedUsers(user),
            "User should be privileged"
        );
    }

    // function testPauseAndResume() public {
    //     processor.pause();
    //     // bool isPaused = processor.paused() == 2;
    //     // assertTrue(isPaused, "Processor should be paused");

    //     processor.resume();
    //     uint8 isPaused = processor.paused() == 1;
    //     assertTrue(!isPaused, "Processor should not be paused");
    // }

    function testSetPrivilege() public {
        address newPrivilegedUser = address(0x4567);
        processor.setPriviledge(newPrivilegedUser, true);
        assertTrue(
            processor.priviledgedUsers(newPrivilegedUser),
            "New user should be privileged"
        );

        processor.setPriviledge(newPrivilegedUser, false);
        assertTrue(
            !processor.priviledgedUsers(newPrivilegedUser),
            "New user should not be privileged anymore"
        );
    }

    function testProcessRoute() public {
        // Mock route data
        bytes memory route = abi.encodePacked(uint8(1), tokenIn);

        // Approve token transfer to the processor
        vm.startPrank(user);
        token.approve(address(processor), 1000 ether);

        // Process route
        uint256 amountOut = processor.processRoute(
            tokenIn,
            1000 ether,
            tokenOut,
            900 ether,
            user,
            route
        );

        // Add assertions for amountOut based on your expectations
        assertEq(amountOut, 900 ether, "Incorrect amount out");

        uint256 userBalance = IERC20(tokenOut).balanceOf(user);
        assertEq(userBalance, 900 ether, "Incorrect tokenOut balance for user");

        vm.stopPrank();
    }

    function testProcessRouteWithTransferValueOutput() public {
        // Mock route data
        bytes memory route = abi.encodePacked(uint8(1), tokenIn);

        // Approve token transfer to the processor
        vm.startPrank(user);
        token.approve(address(processor), 1000 ether);

        // Process route and transfer value to another address
        address payable recipient = payable(address(0x5678));
        uint256 amountOut = processor.processRouteWithTransferValueOutput(
            recipient,
            100 ether,
            tokenIn,
            1000 ether,
            tokenOut,
            900 ether,
            user,
            route
        );

        // Check recipient's balance
        uint256 recipientBalance = IERC20(tokenOut).balanceOf(recipient);
        assertEq(
            recipientBalance,
            100 ether,
            "Incorrect transfer amount to recipient"
        );

        uint256 userBalance = IERC20(tokenOut).balanceOf(user);
        assertEq(
            userBalance,
            800 ether,
            "Incorrect tokenOut balance for user after transfer"
        );

        vm.stopPrank();
    }

    function testProcessRouteWithTransferValueInput() public {
        // Mock route data
        bytes memory route = abi.encodePacked(uint8(1), tokenIn);

        // Approve token transfer to the processor
        vm.startPrank(user);
        token.approve(address(processor), 1000 ether);

        // Process route with transfer of input value
        address payable recipient = payable(address(0x5678));
        uint256 amountOut = processor.processRouteWithTransferValueInput(
            recipient,
            100 ether,
            tokenIn,
            1000 ether,
            tokenOut,
            900 ether,
            user,
            route
        );

        // Check recipient's balance of input token
        uint256 recipientBalance = IERC20(tokenIn).balanceOf(recipient);
        assertEq(
            recipientBalance,
            100 ether,
            "Incorrect input transfer amount to recipient"
        );

        uint256 userBalance = IERC20(tokenOut).balanceOf(user);
        assertEq(userBalance, 900 ether, "Incorrect tokenOut balance for user");

        vm.stopPrank();
    }

    function testTransferValueAndProcessRoute() public {
        // Mock route data
        bytes memory route = abi.encodePacked(uint8(1), tokenIn);

        // Approve token transfer to the processor
        vm.startPrank(user);
        token.approve(address(processor), 1000 ether);

        // Process route and transfer native value
        address recipient = address(0x5678);
        uint256 amountOut = processor.transferValueAndprocessRoute(
            recipient,
            1 ether,
            tokenIn,
            1000 ether,
            tokenOut,
            900 ether,
            user,
            route
        );

        // Check recipient's native balance
        uint256 recipientBalance = recipient.balance;
        assertEq(
            recipientBalance,
            1 ether,
            "Incorrect native value transfer to recipient"
        );

        uint256 userBalance = IERC20(tokenOut).balanceOf(user);
        assertEq(
            userBalance,
            900 ether,
            "Incorrect tokenOut balance for user after route processing"
        );

        vm.stopPrank();
    }

    function testProcessNativeRoute() public {
        // Mock route data for native token processing
        bytes memory route = abi.encodePacked(uint8(3));

        // Transfer some ETH to processor contract
        vm.prank(user);
        uint256 amountOut = processor.processRoute{value: 1 ether}(
            address(0),
            1 ether,
            wethAddress,
            0.9 ether,
            user,
            route
        );

        // Check if WETH was correctly received
        uint256 userWETHBalance = IERC20(wethAddress).balanceOf(user);
        assertEq(
            userWETHBalance,
            0.9 ether,
            "Incorrect WETH balance after processing native route"
        );
    }
}
