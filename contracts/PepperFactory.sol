// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapV3Factory} from '@uniswap/v3-core/contracts/UniswapV3Factory.sol';

/// @title Canonical Uniswap V3 factory
/// @notice Deploys Uniswap V3 pools and manages ownership and control over pool protocol fees
contract PepperFactory is UniswapV3Factory {}
