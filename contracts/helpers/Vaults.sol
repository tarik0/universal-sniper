// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Vault } from "../base/Vault.sol";

library Vaults {
    bytes internal constant BYTECODE = type(Vault).creationCode;
    bytes internal constant BYTECODE_HASH = abi.encodePacked(keccak256(BYTECODE));

    /// @dev Calculates the vault address.
    function getVaultAddress(address token, uint256 id) internal view returns (address) {
        // Generate salt and bytecode hash.
        bytes32 salt = keccak256(abi.encodePacked(token, id));

        // Compute address.
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, BYTECODE_HASH));
        return address(uint160(uint256(_data)));
    }

    /// @dev Deploys a new token vault and approves the token.
    function deployVault(address token, uint256 id) internal {
        // Check duplicate.
        address vaultAddr = getVaultAddress(token, id);
        if (vaultAddr.code.length != 0) return;

        // Deploy new vault.
        bytes32 salt = keccak256(abi.encodePacked(token, id));
        vaultAddr = Create2.deploy(0, salt, BYTECODE);

        // Execute approve max.
        Vault(vaultAddr).approveMax(token);
    }
}