// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

library Commands {
    // The command to create new vault.
    bytes1 internal constant CREATE_VAULT = 0x00;

    // The command to bribe coinbase.
    bytes1 internal constant BRIBE_MEV = 0x01;

    // The command to transfer funds from vault.
    bytes1 internal constant TRANSFER_FROM_VAULT = 0x02;
}