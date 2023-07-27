// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

/// @title Vault
/// @dev Basic vault to hold tokens.
contract Vault {
    address private immutable owner;
    constructor() {
        owner = msg.sender;
    }

    /// @dev Approves the token for the sniper contract.
    function approveMax(address token) external {
        (bool success,) = token.call(abi.encodeWithSelector(0x095ea7b3, owner, type(uint256).max));
        require(success);
    }
}