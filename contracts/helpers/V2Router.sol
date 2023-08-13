// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { IUniswapV2Pair } from '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import { UniswapV2Library } from "../libraries/UniswapV2Library.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

library V2Router {
    /// @dev No pair found.
    error PairNotFound(address tokenA, address tokenB);

    /// @dev Struct to represent V2 pair.
    struct V2Pair {
        address addr;
        address token0;
        uint256 res0;
        uint256 res1;
    }

    /// @dev Finds the pairs with the most liquidity.
    function findBestPairs(
        address[] calldata path,
        address[] calldata factories,
        bytes[] calldata initCodes
    ) internal view returns (
        V2Pair[] memory pairs
    ) {
        // initialize pairs.
        pairs = new V2Pair[](path.length-1);

        // cached variables.
        address pair;
        uint256 res0;
        uint256 res1;
        uint256 pathLen = path.length - 1;

        // iterate over path.
        for (uint i = 0; i < pathLen; i++) {
            // reset K.
            uint256 bestK = 0;

            // iterate over factories.
            for (uint factoryIndex = 0; factoryIndex < factories.length; factoryIndex++) {
                // find pair details.
                (pair, res0, res1) = _findFactoryPair(
                    path[i],
                    path[i+1],
                    factories[factoryIndex],
                    initCodes[factoryIndex]
                );

                // select the pair with most liquidity.
                uint256 currentK = res0 * res1;
                if (currentK > bestK) {
                    pairs[i] = V2Pair(
                        pair,
                        IUniswapV2Pair(pair).token0(),
                        res0,
                        res1
                    );
                    bestK = currentK;
                }
            }

            // check if pair found.
            if (bestK == 0)
                revert PairNotFound(path[i], path[i + 1]);
        }
    }

    /// @dev Limits the output amount of tokens.
    function limitOutput(
        uint256 amountIn,
        uint256 maxAmountOut,
        address[] calldata path,
        V2Pair[] memory pairs
    ) internal pure returns (uint256 normalizedIn) {
        if (maxAmountOut == 0) return amountIn;

        // get amounts in for max amounts.
        uint256 maxInput = getAmountInMultihop(maxAmountOut, path, pairs);
        normalizedIn = maxInput > amountIn ? amountIn : maxInput - 1;
    }

    /// @dev Swaps tokens with V2 pairs.
    function v2Swap(
        address recipient,
        address[] calldata path,
        V2Pair[] memory pairs
    ) internal {
        unchecked {
            address to;
            address input;
            address output;
            V2Pair memory pair;

            for (uint256 i; i < pairs.length; i++) {
                // select pair.
                pair = pairs[i];

                // sort tokens.
                (input, output) = (path[i], path[i + 1]);
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == pair.token0 ? (pair.res0, pair.res1) : (pair.res1, pair.res0);

                // calculate amounts.
                uint256 amountInput = IERC20(input).balanceOf(pair.addr) - reserveInput;
                uint256 amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);

                // sort amounts.
                (uint256 amount0Out, uint256 amount1Out) =
                    input == pair.token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));

                // swap.
                to = i < pairs.length - 1 ? pairs[i+1].addr : recipient;
                IUniswapV2Pair(pair.addr).swap(amount0Out, amount1Out, to, new bytes(0));
            }
        }
    }

    /// Internal

    /// @dev Finds the pair from factory.
    function _findFactoryPair(
        address tokenA,
        address tokenB,
        address factory,
        bytes calldata initCode
    ) private view returns (address pair, uint256 res0, uint256 res1){
        // get pair.
        pair = UniswapV2Library.pairFor(
            factory,
            bytes32(initCode),
            tokenA,
            tokenB
        );

        // skip if pair contract doesn't exist.
        if (pair.code.length == 0) return (pair, 0, 0);

        // get reserves.
        (res0, res1,) = IUniswapV2Pair(pair).getReserves();
    }

    /// @dev Calculates amount in with multihop.
    function getAmountInMultihop(
        uint256 amountOut,
        address[] calldata path,
        V2Pair[] memory pairs
    ) internal pure returns (uint256 amountIn) {
        // cached variables
        uint256 reserveIn;
        uint256 reserveOut;
        V2Pair memory pair;

        amountIn = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            // sort reserves.
            pair = pairs[i - 1];
            (reserveIn, reserveOut) = path[i] == pair.token0 ?
                (pair.res1, pair.res0) : (pair.res0, pair.res1);

            // get amount in.
            amountIn = UniswapV2Library.getAmountIn(amountIn, reserveIn, reserveOut);
        }
    }
}