// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title BytePackLib
/// @notice Library for packing small byte arrays (0-31 bytes) into a single bytes32 slot
/// @dev Uses a tag byte (length + 1) to distinguish packed data from regular addresses/data
library BytePackLib {
    error ContentTooLarge(uint256 size);
    error NotPackedData();

    /// @notice Pack bytes calldata up to 31 bytes into a bytes32
    /// @dev Calldata version for gas optimization when called with external data
    /// @param data The data to pack (must be <= 31 bytes)
    /// @return packed The packed bytes32 value
    function packCalldata(bytes calldata data) internal pure returns (bytes32 packed) {
        uint256 len = data.length;
        if (len >= 32) revert ContentTooLarge(len);

        assembly {
            // Pack: tag byte (len+1) | first 31 bytes of data
            packed := or(
                shl(248, add(len, 1)),      // Tag in first byte
                shr(8, calldataload(data.offset))  // Data in remaining 31 bytes
            )
        }
    }

    /// @notice Pack bytes memory up to 31 bytes into a bytes32
    /// @dev Memory version for when data is in memory
    /// @param data The data to pack (must be <= 31 bytes)
    /// @return packed The packed bytes32 value
    function pack(bytes memory data) internal pure returns (bytes32 packed) {
        uint256 len = data.length;
        if (len >= 32) revert ContentTooLarge(len);

        assembly {
            // Pack: tag byte (len+1) | first 31 bytes of data
            packed := or(
                shl(248, add(len, 1)),      // Tag in first byte
                shr(8, mload(add(data, 0x20)))  // Data in remaining 31 bytes (skip length prefix)
            )
        }
    }

    /// @notice Unpack a bytes32 value into bytes
    /// @dev Extracts the data based on the tag byte (length + 1)
    /// @param packed The packed bytes32 value
    /// @return data The unpacked bytes data
    function unpack(bytes32 packed) internal pure returns (bytes memory data) {
        uint256 tag = uint8(uint256(packed >> 248));
        if (tag == 0 || tag > 32) revert NotPackedData();

        uint256 len = tag - 1;
        data = new bytes(len);

        if (len > 0) {
            assembly {
                // Store the data (shift left by 8 to remove tag byte)
                mstore(add(data, 0x20), shl(8, packed))
                // Note: No need to zero memory after the data since new bytes() already zeroes it
                // and we're only writing up to 31 bytes into a 32-byte word
            }
        }
    }

    /// @notice Check if a bytes32 value is packed data
    /// @dev Returns true if the first byte indicates packed data (tag between 1-32)
    /// @param value The bytes32 value to check
    /// @return True if the value is packed data, false otherwise
    function isPacked(bytes32 value) internal pure returns (bool) {
        // Packed data has a tag byte between 1-32 in the first byte
        uint256 tag = uint8(uint256(value >> 248));
        return tag > 0 && tag <= 32;
    }

    /// @notice Get the length of packed data without unpacking
    /// @dev Returns the length stored in the tag byte
    /// @param packed The packed bytes32 value
    /// @return The length of the packed data (0-31)
    function packedLength(bytes32 packed) internal pure returns (uint256) {
        uint256 tag = uint8(uint256(packed >> 248));
        if (tag == 0 || tag > 32) revert NotPackedData();
        return tag - 1;
    }
}