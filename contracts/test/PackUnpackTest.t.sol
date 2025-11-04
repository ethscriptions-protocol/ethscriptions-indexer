// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

contract PackUnpackTest is Test {

    function packContent(bytes memory data) internal pure returns (bytes32 out) {
        assembly {
            let len := mload(data)
            // Allow 0..31 bytes
            if lt(len, 32) {
                // out = (len+1)<<248 | (first 31 bytes of data)
                // mload returns 32 bytes; shr(8, ...) drops the last byte to get first 31 bytes
                out := or(shl(248, add(len, 1)), shr(8, mload(add(data, 0x20))))
            }
        }
    }

    function unpackContent(bytes32 packed) internal pure returns (bytes memory out) {
        uint256 tag = uint8(uint256(packed >> 248)); // Top byte
        if (tag == 0) return out; // Not inline
        uint256 len = tag - 1;
        out = new bytes(len);
        if (len == 0) return out;
        assembly {
            // Write the 31 data bytes (tag removed) to out[0:]
            mstore(add(out, 0x20), shl(8, packed))
            // Optional hygiene: zero the word immediately after the data
            mstore(add(add(out, 0x20), len), 0)
        }
    }

    function test_PackUnpack_HelloWorld() public {
        bytes memory original = bytes("Hello, World!");
        console2.log("Original length:", original.length);
        console2.logBytes(original);

        bytes32 packed = packContent(original);
        console2.log("Packed:");
        console2.logBytes32(packed);

        bytes memory unpacked = unpackContent(packed);
        console2.log("Unpacked length:", unpacked.length);
        console2.logBytes(unpacked);

        assertEq(unpacked, original, "Unpacked data should match original");
    }

    function test_PackUnpack_Empty() public {
        bytes memory original = bytes("");
        console2.log("Original length:", original.length);

        bytes32 packed = packContent(original);
        console2.log("Packed:");
        console2.logBytes32(packed);

        bytes memory unpacked = unpackContent(packed);
        console2.log("Unpacked length:", unpacked.length);

        assertEq(unpacked, original, "Unpacked data should match original");
    }

    function test_PackUnpack_SingleByte() public {
        bytes memory original = bytes("A");
        console2.log("Original length:", original.length);
        console2.logBytes(original);

        bytes32 packed = packContent(original);
        console2.log("Packed:");
        console2.logBytes32(packed);

        bytes memory unpacked = unpackContent(packed);
        console2.log("Unpacked length:", unpacked.length);
        console2.logBytes(unpacked);

        assertEq(unpacked, original, "Unpacked data should match original");
    }

    function test_PackUnpack_31Bytes() public {
        bytes memory original = bytes("1234567890123456789012345678901"); // 31 bytes
        console2.log("Original length:", original.length);

        bytes32 packed = packContent(original);
        console2.log("Packed:");
        console2.logBytes32(packed);

        bytes memory unpacked = unpackContent(packed);
        console2.log("Unpacked length:", unpacked.length);

        assertEq(unpacked, original, "Unpacked data should match original");
    }
}