// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

library Commands {
    // The command to create new vault.
    bytes1 internal constant CREATE_VAULT = 0x00;

    // The command to bribe coinbase.
    bytes1 internal constant BRIBE_MEV = 0x01;

    // The command to transfer funds from vault.
    bytes1 internal constant TRANSFER_FROM_VAULT = 0x02;

    // The command to buy with V2 pairs.
    bytes1 internal constant BUY_V2 = 0x03;

    // The command to sell with V2 pairs.
    bytes1 internal constant SELL_V2 = 0x04;

    // The command to buy with V3 pairs.
    bytes1 internal constant BUY_V3 = 0x05;

    // The command to sell with V3 pairs.
    bytes1 internal constant SELL_V3 = 0x06;
}

library ViewCommands {
    // The command to compute vault address.
    bytes1 internal constant COMPUTE_VAULT_ADDRESS = 0x00;

    // The command to calculate V2 pair price.
    bytes1 internal constant ASSET_V2_PRICE = 0x01;

    // The command to calculate V3 pair price.
    bytes1 internal constant ASSET_V3_PRICE = 0x02;
}