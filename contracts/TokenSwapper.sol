// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./interfaces/IUniswapV3Router.sol";
import "./interfaces/IUniswapV3Quoter.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITokenSwapper.sol";

contract TokenSwapper is Ownable, ReentrancyGuard, ITokenSwapper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event AddUniswapV3Pool(address from, address to, uint256 fee);
    event RemoveUniswapV3Pool(address from, address to, uint256 fee);
    event AddTokenSupport(address token);
    event TokenSwap(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOut
    );

    IUniswapV3Router constant uniswapV3Router =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Quoter constant uniswapV3Quoter =
        IUniswapV3Quoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IWETH constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    mapping(address => mapping(address => uint24)) public uniswapV3Pools; // from => to => fee
    mapping(address => mapping(address => SwapPath[])) public tokenSwapPath; // from => to => SwapPath array
    EnumerableSet.AddressSet internal addressSet;

    receive() external payable {}

    fallback() external payable {}

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Get token swap path
     * @param  from address of from token
     * @param  to address of to token
     */
    function getTokeSwapPath(
        address from,
        address to
    ) external view override returns (SwapPath[] memory) {
        return tokenSwapPath[from][to];
    }

    /**
     * @dev Add uniswap v3 pool
     * @param  from address of from token
     * @param  to address of to token
     * @param  fee pool fee
     */
    function addUniswapV3Pool(
        address from,
        address to,
        uint24 fee
    ) external override onlyOwner {
        uniswapV3Pools[from][to] = fee;
        uniswapV3Pools[to][from] = fee;
        addressSet.add(from);
        addressSet.add(to);

        emit AddUniswapV3Pool(from, to, fee);
    }

    /**
     * @dev Remove uniswap v3 pool
     * @param  from address of from token
     * @param  to address of to token
     */
    function removeUniswapV3Pool(
        address from,
        address to
    ) external override onlyOwner {
        uniswapV3Pools[from][to] = 0;
        uniswapV3Pools[to][from] = 0;

        emit RemoveUniswapV3Pool(from, to, 0);
    }

    /**
     * @dev Set token swap path
     * @param  from address of from token
     * @param  to address of to token
     * @param  path array of swap path
     */
    function setTokenSwapPath(
        address from,
        address to,
        SwapPath[] memory path
    ) external {
        SwapPath[] storage swapPath = tokenSwapPath[from][to];
        for (uint256 index = 0; index < path.length; index++) {
            swapPath.push(path[index]);
        }
    }

    /**
     * @dev Execute swap
     * @param  swapAmount address of from token
     * @param  path array of swap path
     * @param  minOutAmount min amount of out token
     */
    function executeSwap(
        uint256 swapAmount,
        SwapPath[] memory path,
        uint256 minOutAmount
    ) external payable override returns (uint256 outputAmount) {
        if (path[0].from == address(weth) && msg.value == swapAmount) {
            weth.deposit{value: swapAmount}();
        } else {
            IERC20(path[0].from).safeTransferFrom(
                msg.sender,
                address(this),
                swapAmount
            );
        }

        _executeSwap(path);

        IERC20 output = IERC20(path[path.length - 1].to);
        outputAmount = output.balanceOf(address(this));
        require(minOutAmount <= outputAmount, "slippage!");

        output.safeTransfer(msg.sender, outputAmount);

        emit TokenSwap(path[0].from, address(output), swapAmount, outputAmount);
    }

    /**
     * @dev Calculate best route
     * @notice calculate best route in maximum 2 depth (can be updated if we want)
     * @param  tokenIn address of in token
     * @param  tokenOut address of out token
     * @param  amountIn amount of in token
     */
    function calculateBestRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        external
        override
        returns (uint256 expectedAmountOut, SwapPath[] memory path)
    {
        (expectedAmountOut, path) = _calculateBestRoute0(
            tokenIn,
            tokenOut,
            amountIn
        );

        (
            uint256 expectedAmountOut1,
            SwapPath[] memory path1
        ) = _calculateBestRoute1(tokenIn, tokenOut, amountIn);

        if (expectedAmountOut1 > expectedAmountOut) {
            expectedAmountOut = expectedAmountOut1;
            path = path1;
        }

        require(expectedAmountOut > 0, "invalid swap!");
    }

    function _executeSwap(SwapPath[] memory path) internal {
        for (uint256 i = 0; i < path.length; ++i) {
            uint256 swapAmount = IERC20(path[i].from).balanceOf(address(this));

            IUniswapV3Router.ExactInputSingleParams memory params;
            params.tokenIn = path[i].from;
            params.tokenOut = path[i].to;
            params.fee = uniswapV3Pools[path[i].from][path[i].to];
            params.recipient = address(this);
            params.deadline = block.timestamp;
            params.amountIn = swapAmount;
            params.amountOutMinimum = 0;
            params.sqrtPriceLimitX96 = 0;

            IERC20(path[i].from).approve(address(uniswapV3Router), swapAmount);

            uniswapV3Router.exactInputSingle(params);
        }
    }

    /**
     * @dev Calculate best route
     * @notice calculate best route in 0 depth
     */
    function _calculateBestRoute0(
        address from,
        address to,
        uint256 swapAmount
    ) internal returns (uint256 outAmount, SwapPath[] memory path) {
        path = new SwapPath[](1);
        path[0].from = from;
        path[0].to = to;

        if (uniswapV3Pools[from][to] > 0) {
            outAmount = uniswapV3Quoter.quoteExactInputSingle(
                from,
                to,
                uniswapV3Pools[from][to],
                swapAmount,
                0
            );
        }
    }

    /**
     * @dev Calculate best route
     * @notice calculate best route in 1 depth
     */
    function _calculateBestRoute1(
        address from,
        address to,
        uint256 swapAmount
    ) internal returns (uint256 outAmount, SwapPath[] memory path) {
        path = new SwapPath[](2);

        uint256 length = addressSet.length();
        for (uint256 i = 0; i < length; ++i) {
            address asset = addressSet.at(i);
            if (from == asset || to == asset) {
                continue;
            }

            (
                uint256 outAmount0,
                SwapPath[] memory path0
            ) = _calculateBestRoute0(from, asset, swapAmount);

            (
                uint256 outAmount1,
                SwapPath[] memory path1
            ) = _calculateBestRoute0(asset, to, outAmount0);

            if (outAmount1 > outAmount) {
                outAmount = outAmount1;
                path[0] = path0[0];
                path[1] = path1[0];
            }
        }
    }
}
