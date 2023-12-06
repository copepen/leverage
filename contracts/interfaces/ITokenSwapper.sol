//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITokenSwapper {
    struct SwapPath {
        address from;
        address to;
    }

    function getTokeSwapPath(
        address from,
        address to
    ) external view returns (SwapPath[] memory);

    function addUniswapV3Pool(address from, address to, uint24 fee) external;

    function removeUniswapV3Pool(address from, address to) external;

    function setTokenSwapPath(
        address from,
        address to,
        SwapPath[] memory path
    ) external;

    function executeSwap(
        uint256 swapAmount,
        SwapPath[] memory path,
        uint256 minOutAmount
    ) external payable returns (uint256 outputAmount);

    function calculateBestRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 expectedAmountOut, SwapPath[] memory path);
}
