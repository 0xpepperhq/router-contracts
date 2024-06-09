// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IGaslessForwarderEvents {
    event GaslessRequestExecuted(
        address indexed from,
        address recipient,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut,
        uint256 nonce
    );
    event GaslessRequestFailed(
        address indexed from,
        address recipient,
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 nonce,
        bytes reason
    );

    event FeeRateChanged(uint256 oldRate, uint256 newRate);
}

interface IGaslessForwarder is IGaslessForwarderEvents {
    struct GaslessRequestData {
        address from;
        uint48 deadline;
        address recipient;
        // Route arguments
        uint256 networkFee;
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 amountOutMin;
        bytes route;
        // Signature data
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct PermitData {
        uint256 value;
        uint256 deadline;
        // Signature data
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error GaslessRequestExpired(uint48 deadline);
    error GaslessRequestInvalidSigner(address signer, address from);
    error GaslessRequestNativeTokenIn();
    // error NotApprovedAddress(address caller);
    error NotEnoughAmoutOutToCoverFees();
    error FeeRateTooHigh(uint256 oldProtocolFee, uint256 newProtocolFee);

    function router() external view returns (address payable);

    function FORWARD_REQUEST_TYPEHASH() external view returns (bytes32);

    function domainSeparatorV4() external view returns (bytes32);

    function verify(GaslessRequestData calldata args) external view returns (bool);

    function execute(GaslessRequestData calldata args) external returns (uint256);

    function executeWithPermit(GaslessRequestData calldata args, PermitData calldata permit)
        external
        returns (uint256);

    function setFeeRate(uint256 newRate) external;

    function getFeeRate() external view returns (uint256);
}
