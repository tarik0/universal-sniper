// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IQuoter } from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { V3Path } from "../libraries/V3Path.sol";
import { TickMath } from "../libraries/TickMath.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../libraries/FullMath.sol";

library V3Router {
    /// @dev No pair found.
    error PoolNotFound(address tokenA, address tokenB);

    using V3Path for bytes;
    using SafeCast for uint256;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    /// @dev Struct to represent V3 pool.
    struct V3Pool {
        address addr;
        address tokenIn;
        address tokenB;
        uint24 fee;
    }

    /// @dev Generates Uniswap V3 path from pools.
    function generateBuyPath(V3Pool[] memory pools) internal pure returns (bytes memory path) {
        path = abi.encodePacked(bytes20(pools[0].tokenIn));
        for (uint i = 0; i < pools.length; i++) {
            path = bytes.concat(
                path,
                bytes3(pools[i].fee),
                bytes20(pools[i].tokenB)
            );
        }
    }

    /// @dev Generates reverse Uniswap V3 path from pools.
    function generateSellPath(V3Pool[] memory pools) internal pure returns (bytes memory path) {
        // Starting from the last pool's tokenB.
        path = abi.encodePacked(bytes20(pools[pools.length - 1].tokenB));
        for (uint i = pools.length; i > 0; i--) {
            // Append fee and then tokenA (because we're reversing).
            path = bytes.concat(
                path,
                bytes3(pools[i-1].fee),
                bytes20(pools[i-1].tokenIn)
            );
        }
    }

    /// @dev Checks if address is a contract.
    function isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /// @dev Calculates amount in with pool.
    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        V3Pool memory pool
    ) internal view returns (uint256 amountIn) {
        require(tokenIn != tokenOut, "Input and output tokens cannot be the same");

        // Get the latest tick from the pool.
        (, int24 tick, , , , , ) = IUniswapV3Pool(pool.addr).slot0();

        // Calculate the square root price ratio from the tick.
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate the required input amount based on the square root price ratio.
        // This logic is adapted from Uniswap's OracleLibrary.
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            amountIn = tokenIn > tokenOut
                ? FullMath.mulDiv(ratioX192, amountOut, 1 << 192)
                : FullMath.mulDiv(1 << 192, amountOut, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            amountIn = tokenIn > tokenOut
                ? FullMath.mulDiv(ratioX128, amountOut, 1 << 128)
                : FullMath.mulDiv(1 << 128, amountOut, ratioX128);
        }

        return amountIn;
    }

    /// @dev Calculates amount in with multihop.
    function getAmountInMultihop(
        uint256 amountOut,
        address[] calldata path,
        V3Pool[] memory pools
    ) internal view returns (uint256 amountIn) {
        require(path.length == pools.length + 1, "Path and pools lengths mismatch");

        amountIn = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            V3Pool memory pool = pools[i - 1];

            // Calculate the required input amount for the current swap.
            amountIn = getAmountIn(path[i-1], path[i], amountIn, pool);
        }

        return amountIn;
    }

    /// @dev Limits the output amount of tokens.
    function limitOutput(
        uint256 amountIn,
        uint256 maxAmountOut,
        address[] calldata path,
        V3Pool[] memory pools
    ) internal view returns (uint256 normalizedIn) {
        if (maxAmountOut == 0) return amountIn;

        // get amounts in for max amounts.
        uint256 maxInput = getAmountInMultihop(maxAmountOut, path, pools);
        normalizedIn = maxInput > amountIn ? amountIn : maxInput - 1;
    }

    /// @dev Finds the V3 pool with most liquidity.
    function findPools(
        address factory,
        address tokenIn,
        address tokenOut,
        bytes calldata initCode
    ) internal view returns (V3Pool memory pair){
        // Cached variables.
        uint256 maxLiquidity = 0;
        uint24 fee = 0;
        address pool;

        // Define an array for fees
        uint24[3] memory fees = [uint24(500), uint24(3000), uint24(10000)];

        // Loop through the fees
        for (uint i = 0; i < fees.length; i++) {
            address currentPool = computePoolAddress(factory, tokenIn, tokenOut, fees[i], initCode);
            uint currentLiquidity = isContract(currentPool) ? IUniswapV3Pool(currentPool).liquidity() : 0;

            // If the current liquidity is higher than maxLiquidity, update maxLiquidity, fee, and pool
            if (currentLiquidity > maxLiquidity) {
                maxLiquidity = currentLiquidity;
                fee = fees[i];
                pool = currentPool;
            }
        }

        // If maxLiquidity is still 0, no pool found
        if (maxLiquidity == 0) {
            revert PoolNotFound(tokenIn, tokenOut);
        }

        return V3Pool(pool, tokenIn, tokenOut, fee);
    }

    // @dev Finds the V3 pools from path.
    function findPoolsBulk(
        address factory,
        address[] calldata path,
        bytes calldata initCode
    ) internal view returns (V3Pool[] memory pairs)  {
        // cached variables
        address tokenIn;
        address tokenOut;

        pairs = new V3Pool[](path.length-1);
        for (uint i = 0; i < pairs.length; i++) {
            tokenIn = path[i];
            tokenOut = path[i+1];
            pairs[i] = findPools(factory, tokenIn, tokenOut, initCode);
        }
    }

    // @dev Executes an exact input swap.
    function v3ExactInput(
        address tokenIn,
        uint256 amountIn,
        V3Pool memory pool,
        address recipient,
        address payer
    ) internal returns (uint256) {
        // Exact input mode.
        bool zeroForOne = tokenIn < (pool.tokenIn == tokenIn ? pool.tokenB : pool.tokenIn);

        // Execute swap.
        (
            int256 amount0,
            int256 amount1
        ) = IUniswapV3Pool(pool.addr).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1,
            abi.encode(
                payer,
                tokenIn,
                pool
            )
        );

        // Calculate amount out.
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    // @dev Executes a V3 swap.
    function v3Swap(
        uint256 amountIn,
        address recipient,
        address firstPayer,
        V3Pool[] memory pools,
        address[] memory path
    ) internal {
        uint amount = amountIn;
        uint size = path.length - 1;

        // Iterate over path.
        for (uint i = 0; i < size; i++) {
            amount = v3ExactInput(
                path[i],
                amount,
                pools[i],
                i < size - 1 ?  address(this) : recipient,
                i == 0 ? firstPayer : address(this)
            );
        }
    }
    
    /// @dev Computes the V3 pool address.
    function computePoolAddress(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee,
        bytes calldata initCode
    ) internal pure returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex'ff',
                            factory,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            bytes32(initCode)
                        )
                    )
                )
            )
        );
    }
}