// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

/**
 * @title FiatTokenV1_1
 * @dev ERC20 Token backed by fiat reserves
 */
contract FiatTokenV1_1 is FiatTokenV1, Rescuable {}