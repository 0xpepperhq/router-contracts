// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// import {Router} from "./Router.sol";
// import {OnlyApproved} from "./OnlyApproved.sol";

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
// import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
// import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// import {IGaslessForwarder} from "./interfaces/IGaslessForwarder.sol";

// contract GaslessForwarder is IGaslessForwarder, EIP712, Nonces, ReentrancyGuard, OnlyApproved, Ownable {
//     using ECDSA for bytes32;
//     using SafeERC20 for IERC20;

//     address payable public router;
//     address payable private treasuryManager;
//     uint256 private protocolFeeRate;

//     constructor(address _router, address _treasuryManager, uint256 _initialFeeRate)
//         EIP712("GaslessForwarder", "1")
//         Ownable(_msgSender())
//     {
//         protocolFeeRate = _initialFeeRate;
//         router = payable(_router);
//         treasuryManager = payable(_treasuryManager);
//     }

//     bytes32 public immutable FORWARD_REQUEST_TYPEHASH = keccak256(
//         "GaslessRequest(address from,uint48 deadline,address recipient,uint256 nonce,address tokenIn,uint256 amountIn,address tokenOut,uint256 amountOutMin,bytes route)"
//     );

//     function calculateFees(uint256 amount) private view returns (uint256) {
//         return (amount * protocolFeeRate) / 10000;
//     }

//     function setFeeRate(uint256 newprotocolFeeRate) external onlyOwner {
//         if (newprotocolFeeRate >= 10000) {
//             revert FeeRateTooHigh(protocolFeeRate, newprotocolFeeRate);
//         }

//         uint256 oldRate = protocolFeeRate;
//         protocolFeeRate = newprotocolFeeRate;
//         emit FeeRateChanged(oldRate, newprotocolFeeRate);
//     }

//     function getFeeRate() external view returns (uint256) {
//         return protocolFeeRate;
//     }

//     function addApprovedAddress(address _address) external onlyOwner {
//         _addApprovedAddress(_address);
//     }

//     function removeApprovedAddress(address _address) external onlyOwner {
//         _removeApprovedAddress(_address);
//     }

//     function executeWithPermit(GaslessRequestData calldata args, PermitData calldata permit)
//         external
//         nonReentrant
//         onlyApproved
//         returns (uint256)
//     {
//         IERC20Permit(args.tokenIn).permit(
//             args.from, address(this), permit.value, permit.deadline, permit.v, permit.r, permit.s
//         );
//         return _execute(args);
//     }

//     function execute(GaslessRequestData calldata args) external nonReentrant onlyApproved returns (uint256) {
//         return _execute(args);
//     }

//     function _execute(GaslessRequestData calldata args) private returns (uint256) {
//         if (args.tokenIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
//             revert GaslessRequestNativeTokenIn();
//         }

//         // Validate the request
//         (bool active, bool signerMatch, address signer) = _validate(args);

//         if (!active) {
//             revert GaslessRequestExpired(args.deadline);
//         }

//         if (!signerMatch) {
//             revert GaslessRequestInvalidSigner(signer, args.from);
//         }

//         // Calculate protocol fee
//         uint256 protocolFee = calculateFees(args.amountOutMin);

//         // Calculate total fee
//         uint256 totalFee = protocolFee + args.networkFee;

//         // Verify the user has provided enough amount to cover the fees
//         if (args.amountOutMin <= totalFee) {
//             revert NotEnoughAmoutOutToCoverFees();
//         }

//         uint256 currNonce = _useNonce(args.from);

//         // Transfer in necessary tokens from sender to this contract
//         IERC20(args.tokenIn).safeTransferFrom(args.from, address(this), args.amountIn);

//         // Ensure sufficient allowance to router
//         if (IERC20(args.tokenIn).allowance(address(this), router) < args.amountIn) {
//             IERC20(args.tokenIn).approve(router, type(uint256).max);
//         }

//         // Perform the swap with the remaining amount
//         try Router(router).processRoute(
//             args.tokenIn, args.amountIn, args.tokenOut, args.amountOutMin, address(this), args.route
//         ) returns (uint256 amountOut) {
//             // Deduct the total fees from amountIn
//             amountOut -= totalFee;

//             // Transfer the amount after fees to the recipient
//             IERC20(args.tokenOut).safeTransfer(args.recipient, amountOut);

//             // Transfer the total fee to the fee manager
//             IERC20(args.tokenOut).safeTransfer(treasuryManager, totalFee);

//             emit GaslessRequestExecuted(
//                 args.from, args.recipient, args.tokenIn, args.amountIn, args.tokenOut, amountOut, currNonce
//             );
//             return amountOut;
//         } catch (bytes memory reason) {
//             // Calculate the conversion rate
//             uint256 conversionRate = args.amountIn / args.amountOutMin;

//             // Convert networkFee cost from tokenOut to tokenIn
//             uint256 networkFeeInTokenIn = args.networkFee * conversionRate;

//             // On failure, transfer the remaining tokens back to the user minus networkFee cost
//             IERC20(args.tokenIn).safeTransfer(args.from, args.amountIn - networkFeeInTokenIn);

//             // Transfer the total fee to the fee manager
//             IERC20(args.tokenIn).safeTransfer(treasuryManager, networkFeeInTokenIn);

//             emit GaslessRequestFailed(
//                 args.from, args.recipient, args.tokenIn, args.amountIn, args.tokenOut, currNonce, reason
//             );
//             return 0;
//         }
//     }

//     function _validate(GaslessRequestData calldata args)
//         internal
//         view
//         returns (bool active, bool signerMatch, address signer)
//     {
//         (bool isValid, address recovered) = _recoverGaslessRequestSigner(args);

//         return (args.deadline >= block.timestamp, isValid && recovered == args.from, recovered);
//     }

//     function verify(GaslessRequestData calldata args) external view returns (bool) {
//         (bool active, bool signerMatch,) = _validate(args);
//         return active && signerMatch;
//     }

//     function domainSeparatorV4() external view returns (bytes32) {
//         return _domainSeparatorV4();
//     }

//     function _recoverGaslessRequestSigner(GaslessRequestData calldata args) internal view returns (bool, address) {
//         // Validate the signature
//         (address recovered, ECDSA.RecoverError err,) = _hashTypedDataV4(
//             keccak256(
//                 abi.encode(
//                     FORWARD_REQUEST_TYPEHASH,
//                     args.from,
//                     args.deadline,
//                     args.recipient,
//                     nonces(args.from),
//                     args.tokenIn,
//                     args.amountIn,
//                     args.tokenOut,
//                     args.amountOutMin,
//                     keccak256(args.route)
//                 )
//             )
//         ).tryRecover(args.v, args.r, args.s);

//         return (err == ECDSA.RecoverError.NoError, recovered);
//     }
// }
