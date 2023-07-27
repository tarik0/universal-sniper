// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { Commands } from "../libraries/Commands.sol";
import { Vaults } from "../libraries/Vaults.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @dev Decodes and executes commands.
abstract contract Dispatcher {
    using SafeERC20 for IERC20;

    /// @dev Unsupported command.
    error InvalidCommand(bytes1 command);

    /// @dev Decodes and executes the given command with given inputs.
    function dispatch(bytes1 command, bytes calldata inputs) internal  {
        if (command == Commands.CREATE_VAULT) {
            _createVault(inputs);
        } else if (command == Commands.BRIBE_MEV) {
            _bribeCoinbase(inputs);
        } else if (command == Commands.TRANSFER_FROM_VAULT) {
            _transferFromVault(inputs);
        } else {
            // Invalid command.
            revert InvalidCommand(command);
        }
    }

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
}