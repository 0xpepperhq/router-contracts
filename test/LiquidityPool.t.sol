// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {LiquidityPool} from "../contracts/Pools/LiquidityPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract LiquidityPoolTest is Test {
    TestToken private token1;
    TestToken private token2;
    TestToken private rewardToken;
    LiquidityPool private liquidityPool;

    function setUp() public {
        token1 = new TestToken("Token1", "TK1");
        token2 = new TestToken("Token2", "TK2");
        rewardToken = new TestToken("RewardToken", "PEPR");
        liquidityPool = new LiquidityPool(token1, token2, rewardToken, 1e10, 1e10, "TK1TK2", "1"); // 1 reward token per second per token

        token1.approve(address(liquidityPool), 1000000 * 10 ** token1.decimals());
        token2.approve(address(liquidityPool), 1000000 * 10 ** token2.decimals());
        rewardToken.approve(address(liquidityPool), 1000000 * 10 ** rewardToken.decimals());

        // Fund the reward pool with reward tokens
        rewardToken.transfer(address(liquidityPool), 10000 * 10 ** rewardToken.decimals());
    }

    function testAddLiquidity() public {
        uint256 initialBalance1 = token1.balanceOf(address(liquidityPool));
        uint256 initialBalance2 = token2.balanceOf(address(liquidityPool));

        liquidityPool.addLiquidity(1000 * 10 ** token1.decimals(), 1000 * 10 ** token2.decimals());

        assertEq(token1.balanceOf(address(liquidityPool)), initialBalance1 + 1000 * 10 ** token1.decimals());
        assertEq(token2.balanceOf(address(liquidityPool)), initialBalance2 + 1000 * 10 ** token2.decimals());
    }

    function testRemoveLiquidity() public {
        liquidityPool.addLiquidity(1000 * 10 ** token1.decimals(), 1000 * 10 ** token2.decimals());

        uint256 initialBalance1 = token1.balanceOf(address(this));
        uint256 initialBalance2 = token2.balanceOf(address(this));

        liquidityPool.removeLiquidity(500 * 10 ** token1.decimals(), 500 * 10 ** token2.decimals());

        assertEq(token1.balanceOf(address(this)), initialBalance1 + 500 * 10 ** token1.decimals());
        assertEq(token2.balanceOf(address(this)), initialBalance2 + 500 * 10 ** token2.decimals());
    }

    function testSwap() public {
        liquidityPool.addLiquidity(1000 * 10 ** token1.decimals(), 1000 * 10 ** token2.decimals());

        uint256 amountIn = 100 * 10 ** token1.decimals();
        uint256 initialBalance2 = token2.balanceOf(address(this));

        token1.transfer(address(this), amountIn);
        token1.approve(address(liquidityPool), amountIn);
        liquidityPool.swap(address(token1), address(token2), amountIn);

        assert(token2.balanceOf(address(this)) > initialBalance2);
    }

    function testClaimReward() public {
        liquidityPool.addLiquidity(1000 * 10 ** token1.decimals(), 1000 * 10 ** token2.decimals());
        // Simulate time passing
        vm.warp(block.timestamp + 1000); // Fast forward 1000 seconds

        // deal(address(rewardToken), address(liquidityPool), 2000 * 1e18);
        uint256 initialRewardBalance = rewardToken.balanceOf(address(this));
        console.log("Initial reward balance: ", initialRewardBalance);
        liquidityPool.claimReward();
        uint256 finalRewardBalance = rewardToken.balanceOf(address(this));
        console.log("Reward balance after claim: ", finalRewardBalance);

        assert(finalRewardBalance > initialRewardBalance);
    }

    function testMultipleDepositsAndClaimRewards() public {
        // Add multiple deposits
        liquidityPool.addLiquidity(500 * 10 ** token1.decimals(), 500 * 10 ** token2.decimals());
        vm.warp(block.timestamp + 500); // Fast forward 500 seconds
        liquidityPool.addLiquidity(500 * 10 ** token1.decimals(), 500 * 10 ** token2.decimals());

        // Simulate more time passing
        vm.warp(block.timestamp + 500); // Fast forward another 500 seconds

        uint256 initialRewardBalance = rewardToken.balanceOf(address(this));
        liquidityPool.claimReward();
        uint256 finalRewardBalance = rewardToken.balanceOf(address(this));

        assert(finalRewardBalance > initialRewardBalance);
    }

    function testSetRewardRates() public {
        uint256 newRewardRate1 = 2e18; // 2 reward tokens per second for token1
        uint256 newRewardRate2 = 3e18; // 3 reward tokens per second for token2

        liquidityPool.setRewardRates(newRewardRate1, newRewardRate2);

        assertEq(liquidityPool.rewardRate1(), newRewardRate1);
        assertEq(liquidityPool.rewardRate2(), newRewardRate2);
    }
}
