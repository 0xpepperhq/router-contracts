// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LiquidityPool} from "./LiquidityPool.sol";

contract NGNCUSDCPool is LiquidityPool {
    constructor(IERC20 _token1, IERC20 _token2, IERC20 _rewardToken, uint256 _rewardRate1, uint256 _rewardRate2)
        LiquidityPool(_token1, _token2, _rewardToken, _rewardRate1, _rewardRate2, "NGNCUSDCPool", "1")
    {}
}

contract NGNCUSDTPool is LiquidityPool {
    constructor(IERC20 _token1, IERC20 _token2, IERC20 _rewardToken, uint256 _rewardRate1, uint256 _rewardRate2)
        LiquidityPool(_token1, _token2, _rewardToken, _rewardRate1, _rewardRate2, "NGNCUSDTPool", "1")
    {}
}

contract NGNCPEPRPool is LiquidityPool {
    constructor(IERC20 _token1, IERC20 _token2, IERC20 _rewardToken, uint256 _rewardRate1, uint256 _rewardRate2)
        LiquidityPool(_token1, _token2, _rewardToken, _rewardRate1, _rewardRate2, "NGNCPEPRPool", "1")
    {}
}

contract USDCPEPRPool is LiquidityPool {
    constructor(IERC20 _token1, IERC20 _token2, IERC20 _rewardToken, uint256 _rewardRate1, uint256 _rewardRate2)
        LiquidityPool(_token1, _token2, _rewardToken, _rewardRate1, _rewardRate2, "USDCPEPRPool", "1")
    {}
}

contract USDTPEPRPool is LiquidityPool {
    constructor(IERC20 _token1, IERC20 _token2, IERC20 _rewardToken, uint256 _rewardRate1, uint256 _rewardRate2)
        LiquidityPool(_token1, _token2, _rewardToken, _rewardRate1, _rewardRate2, "USDTPEPRPool", "1")
    {}
}
