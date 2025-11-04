// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../src/Ethscriptions.sol";
import "../src/libraries/SSTORE2Unlimited.sol";
import "../src/libraries/BytePackLib.sol";

/// @title EthscriptionsWithTestFunctions
/// @notice Test contract that extends Ethscriptions with additional functions for testing
/// @dev These functions expose internal storage details useful for tests but not needed in production
/// @dev Usage: Deploy this contract instead of regular Ethscriptions in test setup, then cast to this type
contract EthscriptionsWithTestFunctions is Ethscriptions {

    /// @notice Check if content is stored for an ethscription
    /// @dev Test-only function to check if content exists
    function hasContent(bytes32 ethscriptionId) external view returns (bool) {
        Ethscription storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        return contentStorageBySha[ethscription.contentSha] != bytes32(0);
    }

    /// @notice Get the content storage value for an ethscription
    /// @dev Test-only function to inspect storage (either packed bytes or SSTORE2 address)
    function getContentStorage(bytes32 ethscriptionId) external view returns (bytes32) {
        Ethscription storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        return contentStorageBySha[ethscription.contentSha];
    }

    /// @notice Get the content pointer for an ethscription (only for SSTORE2 stored content)
    /// @dev Test-only function to inspect SSTORE2 address
    function getContentPointer(bytes32 ethscriptionId) external view returns (address) {
        Ethscription storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        bytes32 stored = contentStorageBySha[ethscription.contentSha];

        // Check if it's inline content using BytePackLib
        if (BytePackLib.isPacked(stored)) {
            // It's packed inline content, not a pointer
            return address(0);
        }

        // It's a pointer to SSTORE2 contract
        return address(uint160(uint256(stored)));
    }

    /// @notice Read content directly
    /// @dev Test-only function to read content
    /// @param ethscriptionId The ethscription ID (L1 tx hash)
    /// @return The content data
    function readContent(bytes32 ethscriptionId) external view returns (bytes memory) {
        return getEthscriptionContent(ethscriptionId);
    }
}
