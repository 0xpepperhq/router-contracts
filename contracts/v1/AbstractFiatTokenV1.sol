// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

abstract contract AbstractFiatTokenV1 is IERC20 {
    function _approve(address owner, address spender, uint256 value) internal virtual;

    function _transfer(address from, address to, uint256 value) internal virtual;
}