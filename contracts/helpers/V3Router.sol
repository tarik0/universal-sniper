// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IQuoter } from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import { V3Path } from "../libraries/V3Path.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "hardhat/console.sol";

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
        address tokenA;
        address tokenB;
        uint24 fee;
    }

    /// @dev Generates Uniswap V3 path from pools.
    function generateBuyPath(V3Pool[] memory pools) internal pure returns (bytes memory path) {
        path = abi.encodePacked(bytes20(pools[0].tokenA));
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
                bytes20(pools[i-1].tokenA)
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

    /// @dev Limits the output amount of tokens.
    function limitOutput(
        uint256 amountIn,
        uint256 maxAmountOut,
        address quoter,
        V3Pool[] memory pools
    ) internal returns (uint256 normalizedIn) {
        if (maxAmountOut == 0) return amountIn;

        // get amounts in for max amounts.
        uint256 maxInput = IQuoter(quoter).quoteExactOutput(generateSellPath(pools), maxAmountOut);
        normalizedIn = maxInput > amountIn ? amountIn : maxInput - 1;
    }

    /// @dev Finds the V3 pool with most liquidity.
    function findPools(
        address factory,
        address tokenA,
        address tokenB,
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
            address currentPool = computePoolAddress(factory, tokenA, tokenB, fees[i], initCode);
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
            revert PoolNotFound(tokenA, tokenB);
        }

        return V3Pool(pool, tokenA, tokenB, fee);
    }

    // @dev Finds the V3 pools from path.
    function findPoolsBulk(
        address factory,
        address[] calldata path,
        bytes calldata initCode
    ) internal view returns (V3Pool[] memory pairs)  {
        pairs = new V3Pool[](path.length-1);
        for (uint i = 0; i < pairs.length; i++) {
            address tokenA = path[i];
            address tokenB = path[i+1];
            pairs[i] = findPools(factory, tokenA, tokenB, initCode);
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
        bool zeroForOne = tokenIn < (pool.tokenA == tokenIn ? pool.tokenB : pool.tokenA);

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