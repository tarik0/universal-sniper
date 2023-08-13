// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { Dispatcher } from "./base/Dispatcher.sol";

contract UniversalSniper is Dispatcher {
    /// @dev Sender needs to be owner.
    error InvalidSender();
    /// @dev Invalid `execute` call inputs.
    error LengthMismatch();

    /// @dev The sniper contract version.
    uint8 public constant version = 6;

    /// @dev Immutable owner.
    address public immutable owner;
    constructor() {
        owner = msg.sender;
    }

    /// @dev Parses the commands and executes them.
    function execute(bytes1[] calldata commands, bytes[] calldata inputs) external payable {
        // Check sender.
        if (msg.sender != owner) revert InvalidSender();

        // Check input lengths.
        uint256 commandCount = commands.length;
        if (commandCount != inputs.length)
            revert LengthMismatch();

        // Dispatch the commands.
        for (uint256 i = 0; i < commandCount; i++)
            dispatch(commands[i], inputs[i]);
    }

    /// @dev Parses the readonly commands and returns the response.
    function readView(bytes1[] calldata readonlyCommands, bytes[] calldata inputs) external view returns (bytes[] memory results) {
        // Check input lengths.
        uint256 commandCount = readonlyCommands.length;
        if (commandCount != inputs.length)
            revert LengthMismatch();

        // Dispatch the commands.
        results = new bytes[](commandCount);
        for (uint256 i = 0; i < commandCount; i++)
            results[i] = dispatchView(readonlyCommands[i], inputs[i]);

        return results;
    }

    /// @dev Fallback function to receive ether.
    receive() external payable {}
}