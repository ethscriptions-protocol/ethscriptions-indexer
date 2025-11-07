// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {LibBytes} from "solady/utils/LibBytes.sol";
import "./DedupedBlobStore.sol";

/// @title MetaStoreLib
/// @notice Library for deduplicated storage of ethscription metadata (mimetype, protocol, operation)
/// @dev Encodes metadata as: mimetype\x00protocol\x00operation, stores once per unique combination
library MetaStoreLib {
    using LibBytes for bytes;

    /// @dev Null byte (0x00) used to separate metadata components
    /// @dev Safe to use as Ruby indexer strips all null bytes from input strings
    bytes1 constant SEPARATOR = 0x00;

    /// @dev Sentinel value for "text/plain" with no protocol (most common case)
    bytes32 constant EMPTY_REF = bytes32(0);

    // Custom errors
    error InvalidSeparatorInInput();
    error InvalidMetadataRef();
    error MetadataNotStored();
    error InvalidFormat();

    /// @notice Store metadata components (encode + deduplicate)
    /// @dev High-level API for callers - combines encode() and intern()
    /// @param mimetype MIME type string (preserve case for standards compliance)
    /// @param protocolName Protocol identifier (should already be normalized by Ruby)
    /// @param operation Operation to perform (should already be normalized by Ruby)
    /// @param metaStore Storage mapping for metadata blobs
    /// @return metaRef The metadata reference (bytes32(0), packed, or SSTORE2 pointer)
    function store(
        string memory mimetype,
        string memory protocolName,
        string memory operation,
        mapping(bytes32 => bytes32) storage metaStore
    ) internal returns (bytes32 metaRef) {
        bytes memory blob = encode(mimetype, protocolName, operation);
        return intern(blob, metaStore);
    }

    /// @notice Encode metadata components into a blob
    /// @dev Lower-level API - most callers should use store() instead
    /// @param mimetype MIME type string (not normalized - preserve case for standards compliance)
    /// @param protocolName Protocol identifier (should already be normalized by Ruby)
    /// @param operation Operation name (should already be normalized by Ruby)
    /// @return blob The encoded metadata blob (empty if all components empty/default)
    function encode(
        string memory mimetype,
        string memory protocolName,
        string memory operation
    ) internal pure returns (bytes memory blob) {
        // Validate inputs don't contain separator
        if (_containsByte(bytes(mimetype), SEPARATOR)) revert InvalidSeparatorInInput();
        if (_containsByte(bytes(protocolName), SEPARATOR)) revert InvalidSeparatorInInput();
        if (_containsByte(bytes(operation), SEPARATOR)) revert InvalidSeparatorInInput();

        // Note: normalization (lowercase, trim) is handled by Ruby indexer before submission

        // Normalize "text/plain" to empty string (convention: empty = text/plain)
        if (keccak256(bytes(mimetype)) == keccak256(bytes("text/plain"))) {
            mimetype = "";
        }

        // Special case: empty mimetype + no protocol → empty blob (most common case!)
        if (bytes(mimetype).length == 0 && bytes(protocolName).length == 0 && bytes(operation).length == 0) {
            return bytes("");  // Will map to EMPTY_REF (bytes32(0))
        }

        // Always encode in same format: mimetype\x1Fprotocol\x1Foperation
        // Any component can be empty string
        return abi.encodePacked(mimetype, SEPARATOR, protocolName, SEPARATOR, operation);
    }

    /// @notice Decode a metadata reference into components
    /// @param metaRef The metadata reference (bytes32(0), packed, or SSTORE2 pointer)
    /// @return mimetype The MIME type
    /// @return protocolName The protocol identifier (normalized)
    /// @return operation The operation name (normalized)
    function decode(bytes32 metaRef) internal view returns (
        string memory mimetype,
        string memory protocolName,
        string memory operation
    ) {
        bytes[] memory parts = _getParts(metaRef);
        return _partsToStrings(parts);
    }

    /// @notice Get only the mimetype from a metadata reference (gas-optimized)
    /// @param metaRef The metadata reference
    /// @return mimetype The MIME type
    function getMimetype(bytes32 metaRef) internal view returns (string memory mimetype) {
        bytes[] memory parts = _getParts(metaRef);

        // First part is always mimetype (empty = text/plain)
        string memory mime = string(parts[0]);
        return bytes(mime).length == 0 ? "text/plain" : mime;
    }

    /// @notice Get protocol information from a metadata reference
    /// @param metaRef The metadata reference
    /// @return protocolName The protocol identifier (normalized, empty if none)
    /// @return operation The operation name (normalized, empty if none)
    function getProtocol(bytes32 metaRef) internal view returns (
        string memory protocolName,
        string memory operation
    ) {
        bytes[] memory parts = _getParts(metaRef);

        // parts[0] = mimetype, parts[1] = protocol, parts[2] = operation
        protocolName = string(parts[1]);
        operation = string(parts[2]);
        return (protocolName, operation);
    }


    /// @notice Intern a metadata blob (deduplicate and store)
    /// @dev Lower-level API - most callers should use store() instead
    /// @param blob The encoded metadata blob
    /// @param metaStore Storage mapping for metadata blobs
    /// @return metaRef The metadata reference (bytes32(0), packed, or SSTORE2 pointer)
    function intern(
        bytes memory blob,
        mapping(bytes32 => bytes32) storage metaStore
    ) internal returns (bytes32 metaRef) {
        // Special case: empty blob = EMPTY_REF sentinel
        if (blob.length == 0) {
            return EMPTY_REF;
        }

        // Use shared deduplication logic with keccak256
        (, metaRef) = DedupedBlobStore.storeMemory(blob, metaStore);
        return metaRef;
    }


    // =============================================================
    //                     INTERNAL HELPERS
    // =============================================================

    /// @notice Retrieve a blob from storage
    /// @param metaRef The metadata reference
    /// @return blob The retrieved blob
    function _retrieve(bytes32 metaRef) private view returns (bytes memory blob) {
        if (metaRef == EMPTY_REF) {
            return bytes("");
        }

        // Use shared read logic
        return DedupedBlobStore.read(metaRef);
    }

    /// @notice Get parts array from metadata reference (single point for blob.length check)
    /// @param metaRef The metadata reference
    /// @return parts Array of 3 byte parts [mimetype, protocol, operation]
    function _getParts(bytes32 metaRef) private view returns (bytes[] memory parts) {
        bytes memory blob = _retrieve(metaRef);

        // Single check for empty blob (text/plain + no protocol case)
        if (blob.length == 0) {
            parts = new bytes[](3);
            parts[0] = bytes("");  // Empty = text/plain
            parts[1] = bytes("");  // No protocol
            parts[2] = bytes("");  // No operation
            return parts;
        }

        // Split keeping empty parts - always get 3 parts
        return _splitKeepEmpty(blob, SEPARATOR);
    }

    /// @notice Convert parts array to strings with text/plain default
    /// @param parts Array of 3 byte parts [mimetype, protocol, operation]
    /// @return mimetype The MIME type
    /// @return protocolName The protocol identifier
    /// @return operation The operation name
    function _partsToStrings(bytes[] memory parts) private pure returns (
        string memory mimetype,
        string memory protocolName,
        string memory operation
    ) {
        // Extract mimetype (empty = text/plain)
        mimetype = string(parts[0]);
        if (bytes(mimetype).length == 0) {
            mimetype = "text/plain";
        }

        // Extract protocol and operation (may be empty)
        protocolName = string(parts[1]);
        operation = string(parts[2]);

        return (mimetype, protocolName, operation);
    }

    /// @notice Split a blob by single-byte delimiter, keeping empty parts
    /// @dev Enforces exactly 2 separators (3 parts): [mimetype, protocol, operation]
    /// @param subject The blob to split
    /// @param delim The single-byte delimiter
    /// @return out Array with exactly 3 parts (some may be empty)
    function _splitKeepEmpty(bytes memory subject, bytes1 delim)
        private
        pure
        returns (bytes[] memory out)
    {
        // Find first separator
        uint256 a = subject.indexOfByte(delim, 0);
        if (a == LibBytes.NOT_FOUND) revert InvalidFormat();

        // Find second separator
        uint256 b = subject.indexOfByte(delim, a + 1);
        if (b == LibBytes.NOT_FOUND) revert InvalidFormat();

        // Ensure no third separator (enforce format)
        if (subject.indexOfByte(delim, b + 1) != LibBytes.NOT_FOUND) revert InvalidFormat();

        out = new bytes[](3);
        out[0] = subject.slice(0, a);           // mimetype (may be empty)
        out[1] = subject.slice(a + 1, b);       // protocol (may be empty)
        out[2] = subject.slice(b + 1, subject.length);  // operation (may be empty)
    }

    /// @notice Check if bytes contains a specific byte
    /// @dev Custom helper since LibBytes.contains requires bytes memory, not bytes1
    /// @param data The data to search
    /// @param target The byte to find
    /// @return True if found
    function _containsByte(bytes memory data, bytes1 target) private pure returns (bool) {
        return data.indexOfByte(target) != LibBytes.NOT_FOUND;
    }
}
