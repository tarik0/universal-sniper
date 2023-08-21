// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { Commands, ViewCommands } from "../libraries/Commands.sol";
import { Vaults } from "../helpers/Vaults.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { UniswapV2Library } from "../libraries/UniswapV2Library.sol";
import { BytesLib } from "../libraries/BytesLib.sol";
import { V2Router } from "../helpers/V2Router.sol";
import { V3Router } from "../helpers/V3Router.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { V3Path } from "../libraries/V3Path.sol";

import "hardhat/console.sol";

/// @dev Decodes and executes commands.
abstract contract Dispatcher {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    using V3Path for bytes;
    using SafeCast for uint256;

    /// @dev Unsupported command.
    error InvalidCommand(bytes1 command);
    /// @dev Insufficient ether.
    error InsufficientIn(uint256 amountIn);
    /// @dev Invalid swap.
    error InvalidSwap();

    /// @dev Decodes and executes the given command with given inputs.
    function dispatch(bytes1 command, bytes calldata inputs) internal  {
        if (command == Commands.CREATE_VAULT) {
            _createVault(inputs);
        } else if (command == Commands.BRIBE_MEV) {
            _bribeCoinbase(inputs);
        } else if (command == Commands.TRANSFER_FROM_VAULT) {
            _transferFromVault(inputs);
        } else if (command == Commands.BUY_V2) {
            _buyV2(inputs);
        } else if (command == Commands.SELL_V2) {
            _sellV2(inputs);
        } else if (command == Commands.BUY_V3) {
            _buyV3(inputs);
        } else {
            // Invalid command.
            revert InvalidCommand(command);
        }
    }

    /// @dev Decodes and returns the given command's result.
    function dispatchView(bytes1 command, bytes calldata inputs) internal view returns (bytes memory)  {
        // Compute vault address.
        if (command == ViewCommands.COMPUTE_VAULT_ADDRESS) {
            return _getVaultAddr(inputs);
        } else if (command == ViewCommands.ASSET_V2_PRICE) {
            return _getAssetPriceV2(inputs);
        }

        // Unknown command.
        return abi.encodePacked(address(0));
    }

    ///
    /// @dev Internal Functions
    ///

    /// @dev Creates a new vault.
    function _createVault(bytes calldata inputs) internal  {
        address token;
        uint256 id;
        assembly {
            token := calldataload(inputs.offset)
            id := calldataload(add(inputs.offset, 0x20))
        }
        Vaults.deployVault(token, id);
    }

    /// @dev Bribes the coinbase.
    function _bribeCoinbase(bytes calldata inputs) internal {
        uint256 amount;
        assembly {
            amount := calldataload(inputs.offset)
        }
        block.coinbase.transfer(amount);
    }

    /// @dev Transfers funds from vault to recipient.
    function _transferFromVault(bytes calldata inputs) internal {
        address vault;
        address token;
        address recipient;
        assembly {
            vault := calldataload(inputs.offset)
            token := calldataload(add(inputs.offset, 0x20))
            recipient := calldataload(add(inputs.offset, 0x40))
        }
        IERC20(token).transferFrom(vault, recipient, IERC20(token).balanceOf(vault));
    }

    /// @dev Buys tokens with V2 pairs.
    function _buyV2(bytes calldata inputs) internal  {
        uint256 amountIn;
        uint256 maxAmountsOut;
        assembly {
            amountIn := calldataload(inputs.offset)
            maxAmountsOut := calldataload(add(inputs.offset, 0x20))
        }
        address[] calldata vaults = inputs.toAddressArray(2);
        address[] calldata path = inputs.toAddressArray(3);
        address[] calldata factories = inputs.toAddressArray(4);
        bytes[] calldata initCodes = inputs.toBytesArray(5);

        // Check amount.
        if (amountIn > msg.value)
            revert InsufficientIn(amountIn);

        // Amount in each.
        uint256 limitedIn;
        uint256 amountInEach = amountIn / vaults.length;
        uint256 dust = amountIn;

        // Wrap ethers.
        IWETH9(path[0]).deposit{value: amountIn}();

        // Iterate over vaults.
        V2Router.V2Pair[] memory pairs;
        for (uint256 i = 0; i < vaults.length; i++) {
            // Get the best pairs.
            pairs = V2Router.findBestPairs(path, factories, initCodes);

            // Limit the output.
            limitedIn = V2Router.limitOutput(amountInEach, maxAmountsOut, path, pairs);

            // Transfer funds to first pair.
            IERC20(path[0]).transfer(pairs[0].addr, limitedIn);

            // Swap.
            V2Router.v2Swap(vaults[i], path, pairs);
            dust -= limitedIn;
        }

        // 1 Gwei threshold.
        // Unwrap & refund dust.
        if (dust > 1e9) {
            IWETH9(path[0]).withdraw(dust);
            payable(msg.sender).transfer(dust);
        }
    }

    /// @dev Sells tokens with V2 pairs.
    function _sellV2(bytes calldata inputs) internal  {
        uint256 sellPercentage;
        assembly {
            sellPercentage := calldataload(inputs.offset)
        }
        address[] calldata vaults = inputs.toAddressArray(1);
        address[] calldata path = inputs.toAddressArray(2);
        address[] calldata factories = inputs.toAddressArray(3);
        bytes[] calldata initCodes = inputs.toBytesArray(4);

        // Iterate over vaults.
        uint256 limitedIn;
        V2Router.V2Pair[] memory pairs;
        for (uint256 i = 0; i < vaults.length; i++) {
            // Get the best pairs.
            pairs = V2Router.findBestPairs(path, factories, initCodes);

            // Calculate balances.
            limitedIn = IERC20(path[0]).balanceOf(vaults[i]) * sellPercentage / 100;

            // Transfer funds to first pair.
            IERC20(path[0]).transferFrom(vaults[i], pairs[0].addr, limitedIn);

            // Swap.
            V2Router.v2Swap(address(this), path, pairs);
        }

        // Return amounts out.
        address weth = path[path.length-1];
        uint256 dust = IERC20(weth).balanceOf(address(this));
        IWETH9(weth).withdraw(dust);
        payable(msg.sender).transfer(dust);
    }

    /// @dev Pays tokens to the recipient.
    function _pay(address payer, address recipient, IERC20 tokenIn, uint256 amount) internal  {
        if (payer == address(this)) {
            SafeERC20.safeTransfer(tokenIn, recipient, amount);
        } else {
            SafeERC20.safeTransferFrom(tokenIn, payer, recipient, amount);
        }
    }

    /// @dev Buys tokens with V3 pairs.
    function _buyV3(bytes calldata inputs) internal {
        uint256 amountIn;
        uint256 maxAmountsOut;
        address quoter;
        address factory;
        assembly {
            amountIn := calldataload(inputs.offset)
            maxAmountsOut := calldataload(add(inputs.offset, 0x20))
            quoter := calldataload(add(inputs.offset, 0x40))
            factory := calldataload(add(inputs.offset, 0x60))
        }
        address[] calldata vaults = inputs.toAddressArray(4);
        address[] calldata path = inputs.toAddressArray(5);
        bytes calldata initCode = inputs.toBytes(6);

        // Check amount.
        if (amountIn > msg.value)
            revert InsufficientIn(amountIn);

        // Wrap ethers.
        IWETH9(path[0]).deposit{value: amountIn}();

        // Amount in each.
        uint256 limitedIn;
        uint256 amountInEach = amountIn / vaults.length;
        uint256 dust = amountIn;

        // Iterate over vaults.
        V3Router.V3Pool[] memory pools = V3Router.findPoolsBulk(factory, path, initCode);
        for (uint256 i = 0; i < vaults.length; i++) {
            // Limit the output.
            limitedIn = V3Router.limitOutput(amountInEach, maxAmountsOut, quoter, pools);

            // Swap with the pools
            V3Router.v3Swap(limitedIn, vaults[i], pools, path);
            dust -= limitedIn;
        }

        // 1 Gwei threshold.
        // Unwrap & refund dust.
        if (dust > 1e9) {
            IWETH9(path[0]).withdraw(dust);
            payable(msg.sender).transfer(dust);
        }
    }

    ///
    /// @dev View Functions
    ///

    /// @dev Computes vault address.
    function _getVaultAddr(bytes calldata inputs) internal view returns (bytes memory) {
        address token;
        uint256 id;
        assembly {
            token := calldataload(inputs.offset)
            id := calldataload(add(inputs.offset, 0x20))
        }
        return abi.encode(Vaults.getVaultAddress(token, id));
    }

    /// @dev Calculates asset price with V2 pairs. (A/path/B) (A per B)
    function _getAssetPriceV2(bytes calldata inputs) internal view returns (bytes memory) {
        address[] calldata path = inputs.toAddressArray(0);
        address[] calldata factories = inputs.toAddressArray(1);
        bytes[] calldata initCodes = inputs.toBytesArray(2);

        // Find best pairs.
        V2Router.V2Pair[] memory pairs = V2Router.findBestPairs(path, factories, initCodes);

        // Calculate amount in.
        uint256 amountB = 10 ** ERC20(path[path.length-1]).decimals();
        uint256 amountA = V2Router.getAmountInMultihop(
            amountB,
            path,
            pairs
        );

        return abi.encode(amountA, amountB);
    }


    ///
    /// @dev Uniswap Callbacks
    ///

    /// @dev Uniswap v3 Callback.
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external {
        // Swaps entirely within 0-liquidity regions are not supported
        if (amount0Delta <= 0 && amount1Delta <= 0)
            revert InvalidSwap();

        // Decode the data.
        (
            address payer,
            address tokenIn,
            V3Router.V3Pool memory pool
        ) = abi.decode(_data, (address, address, V3Router.V3Pool));

        // Verify the callback.
        if (
            address(0) == tokenIn ||
            pool.addr != msg.sender
        ) revert InvalidSwap();

        // Calculate amounts to pay.
        address tokenOut = pool.tokenA == tokenIn ? pool.tokenB : pool.tokenA;
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            // Pay the pool (msg.sender)
            _pay(payer, msg.sender, IERC20(tokenIn), amountToPay);
        } else {
            // exact output not supported.
            revert InvalidSwap();
        }
    }
}