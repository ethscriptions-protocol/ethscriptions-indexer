// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./BytePackLib.sol";
import "./SSTORE2Unlimited.sol";

/// @title DedupedBlobStore
/// @notice Shared library for deduplicated blob storage using inline packing or SSTORE2
/// @dev Used by both content storage and metadata storage to eliminate code duplication
library DedupedBlobStore {

    /// @notice Store calldata blob with deduplication using keccak256
    /// @dev Uses keccak256 for dedup key, stores either packed (≤31 bytes) or SSTORE2 pointer
    /// @param data The calldata to store
    /// @param store The storage mapping (hash => ref)
    /// @return hash The keccak256 hash of the data (dedup key)
    /// @return ref The storage reference (packed or SSTORE2 pointer)
    function storeCalldata(
        bytes calldata data,
        mapping(bytes32 => bytes32) storage store
    ) internal returns (bytes32 hash, bytes32 ref) {
        hash = keccak256(data);

        // Check if already stored
        bytes32 existing = store[hash];
        if (existing != bytes32(0)) {
            return (hash, existing);
        }

        // Store based on size - use calldata packing for efficiency
        ref = data.length <= 31 ? BytePackLib.packCalldata(data) : _deploySST0RE2Calldata(data);

        // Store the mapping: hash -> reference
        store[hash] = ref;
        return (hash, ref);
    }

    /// @notice Store memory blob with deduplication using keccak256
    /// @dev Uses keccak256 for dedup key, stores either packed (≤31 bytes) or SSTORE2 pointer
    /// @param data The memory data to store
    /// @param store The storage mapping (hash => ref)
    /// @return hash The keccak256 hash of the data (dedup key)
    /// @return ref The storage reference (packed or SSTORE2 pointer)
    function storeMemory(
        bytes memory data,
        mapping(bytes32 => bytes32) storage store
    ) internal returns (bytes32 hash, bytes32 ref) {
        hash = keccak256(data);

        // Check if already stored
        bytes32 existing = store[hash];
        if (existing != bytes32(0)) {
            return (hash, existing);
        }

        // Store based on size - use memory packing
        ref = data.length <= 31 ? BytePackLib.pack(data) : _deploySST0RE2Memory(data);

        // Store the mapping: hash -> reference
        store[hash] = ref;
        return (hash, ref);
    }

    /// @notice Deploy SSTORE2 contract and return reference
    /// @param data The data to deploy (calldata or memory)
    /// @return ref The SSTORE2 pointer as bytes32
    function _deploySST0RE2Calldata(bytes calldata data) private returns (bytes32 ref) {
        address pointer = SSTORE2Unlimited.write(data);
        return bytes32(uint256(uint160(pointer)));
    }

    /// @notice Deploy SSTORE2 contract and return reference
    /// @param data The data to deploy (calldata or memory)
    /// @return ref The SSTORE2 pointer as bytes32
    function _deploySST0RE2Memory(bytes memory data) private returns (bytes32 ref) {
        address pointer = SSTORE2Unlimited.write(data);
        return bytes32(uint256(uint160(pointer)));
    }

    /// @notice Read blob from storage reference
    /// @dev Automatically detects packed vs SSTORE2 and retrieves accordingly
    /// @param ref The storage reference (packed or SSTORE2 pointer)
    /// @return data The retrieved blob
    function read(bytes32 ref) internal view returns (bytes memory) {
        // Check if it's inline packed content
        if (BytePackLib.isPacked(ref)) {
            return BytePackLib.unpack(ref);
        }

        // It's a pointer to SSTORE2 contract
        address pointer = address(uint160(uint256(ref)));
        return SSTORE2Unlimited.read(pointer);
    }

    /// @notice Read blob from storage reference and convert to string
    /// @dev Convenience wrapper to avoid repetitive string() casting
    /// @param ref The storage reference (packed or SSTORE2 pointer)
    /// @return str The retrieved data as string
    function readString(bytes32 ref) internal view returns (string memory) {
        return string(read(ref));
    }

    /// @notice Read blob from storage mapping by hash
    /// @dev Looks up reference in mapping, then reads
    /// @param hash The hash key
    /// @param store The storage mapping
    /// @return data The retrieved blob
    function readByHash(
        bytes32 hash,
        mapping(bytes32 => bytes32) storage store
    ) internal view returns (bytes memory) {
        bytes32 ref = store[hash];
        return read(ref);
    }
}
