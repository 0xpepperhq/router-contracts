// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OnlyApproved} from "../OnlyApproved.sol";

contract LiquidityPool is Ownable, Nonces, ReentrancyGuard, OnlyApproved, EIP712 {
    using SafeERC20 for IERC20;

    IERC20 public token1;
    IERC20 public token2;
    IERC20 public rewardToken;
    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public rewardRate1; // rewards per second for token1
    uint256 public rewardRate2; // rewards per second for token2

    struct Deposit {
        uint256 amount;
        uint256 depositTime;
    }

    struct UserInfo {
        Deposit[] depositsToken1;
        Deposit[] depositsToken2;
        uint256 rewardDebtToken1;
        uint256 rewardDebtToken2;
    }

    mapping(address => UserInfo) public userInfo;

    event LiquidityAdded(address indexed provider, uint256 amount1, uint256 amount2);
    event LiquidityRemoved(address indexed provider, uint256 amount1, uint256 amount2);
    event Swap(
        address indexed swapper, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut
    );
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(
        IERC20 _token1,
        IERC20 _token2,
        IERC20 _rewardToken,
        uint256 _rewardRate1,
        uint256 _rewardRate2,
        string memory name,
        string memory version
    ) EIP712(name, version) Ownable(_msgSender()) OnlyApproved(_msgSender()) {
        token1 = _token1;
        token2 = _token2;
        rewardToken = _rewardToken;
        rewardRate1 = _rewardRate1;
        rewardRate2 = _rewardRate2;
    }

    function addLiquidity(uint256 amount1, uint256 amount2) external {
        require(token1.transferFrom(msg.sender, address(this), amount1), "Transfer of token1 failed");
        require(token2.transferFrom(msg.sender, address(this), amount2), "Transfer of token2 failed");

        _updateReward(msg.sender);

        reserve1 += amount1;
        reserve2 += amount2;
        userInfo[msg.sender].depositsToken1.push(Deposit(amount1, block.timestamp));
        userInfo[msg.sender].depositsToken2.push(Deposit(amount2, block.timestamp));

        emit LiquidityAdded(msg.sender, amount1, amount2);
    }

    function removeLiquidity(uint256 amount1, uint256 amount2) external onlyOwner {
        require(reserve1 >= amount1 && reserve2 >= amount2, "Not enough liquidity");

        _updateReward(msg.sender);

        reserve1 -= amount1;
        reserve2 -= amount2;

        require(token1.transfer(msg.sender, amount1), "Transfer of token1 failed");
        require(token2.transfer(msg.sender, amount2), "Transfer of token2 failed");

        emit LiquidityRemoved(msg.sender, amount1, amount2);
    }

    function swap(address fromToken, address toToken, uint256 amountIn) external {
        require(
            (fromToken == address(token1) && toToken == address(token2))
                || (fromToken == address(token2) && toToken == address(token1)),
            "Invalid tokens"
        );

        IERC20 inputToken = IERC20(fromToken);
        IERC20 outputToken = IERC20(toToken);
        uint256 inputReserve = (fromToken == address(token1)) ? reserve1 : reserve2;
        uint256 outputReserve = (toToken == address(token1)) ? reserve1 : reserve2;

        require(inputToken.transferFrom(msg.sender, address(this), amountIn), "Transfer of input token failed");
        uint256 amountOut = getAmountOut(amountIn, inputReserve, outputReserve);

        require(outputToken.transfer(msg.sender, amountOut), "Transfer of output token failed");

        if (fromToken == address(token1)) {
            reserve1 += amountIn;
            reserve2 -= amountOut;
        } else {
            reserve2 += amountIn;
            reserve1 -= amountOut;
        }

        emit Swap(msg.sender, fromToken, toToken, amountIn, amountOut);
    }

    function getAmountOut(uint256 amountIn, uint256 inputReserve, uint256 outputReserve)
        public
        pure
        returns (uint256)
    {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * outputReserve;
        uint256 denominator = (inputReserve * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function claimReward() external {
        _updateReward(msg.sender);
        uint256 reward = userInfo[msg.sender].rewardDebtToken1 + userInfo[msg.sender].rewardDebtToken2;
        require(reward > 0, "No rewards to claim");
        userInfo[msg.sender].rewardDebtToken1 = 0;
        userInfo[msg.sender].rewardDebtToken2 = 0;
        require(rewardToken.transfer(msg.sender, reward), "Reward transfer failed");
        emit RewardClaimed(msg.sender, reward);
    }

    function _updateReward(address user) internal {
        UserInfo storage userInformation = userInfo[user];
        uint256 pendingRewardToken1 = 0;
        uint256 pendingRewardToken2 = 0;

        for (uint256 i = 0; i < userInformation.depositsToken1.length; i++) {
            uint256 timeHeld = block.timestamp - userInformation.depositsToken1[i].depositTime;
            pendingRewardToken1 += (userInformation.depositsToken1[i].amount * rewardRate1 * timeHeld) / 1e18;
            userInformation.depositsToken1[i].depositTime = block.timestamp; // reset the deposit time to now
        }

        for (uint256 i = 0; i < userInformation.depositsToken2.length; i++) {
            uint256 timeHeld = block.timestamp - userInformation.depositsToken2[i].depositTime;
            pendingRewardToken2 += (userInformation.depositsToken2[i].amount * rewardRate2 * timeHeld) / 1e18;
            userInformation.depositsToken2[i].depositTime = block.timestamp; // reset the deposit time to now
        }

        userInformation.rewardDebtToken1 += pendingRewardToken1;
        userInformation.rewardDebtToken2 += pendingRewardToken2;
    }

    function setRewardRates(uint256 _rewardRate1, uint256 _rewardRate2) external onlyOwner {
        rewardRate1 = _rewardRate1;
        rewardRate2 = _rewardRate2;
    }

    function fundRewards(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Funding of rewards failed");
    }

    function addApprovedAddress(address _address) external onlyOwner {
        _addApprovedAddress(_address);
    }

    function removeApprovedAddress(address _address) external onlyOwner {
        _removeApprovedAddress(_address);
    }
}
