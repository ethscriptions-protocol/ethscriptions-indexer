// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/libraries/BytePackLib.sol";

/// @title TestWrapper
/// @notice Wrapper contract to expose internal library functions for testing
contract TestWrapper {
    function packCalldata(bytes calldata data) external pure returns (bytes32) {
        return BytePackLib.packCalldata(data);
    }

    function unpack(bytes32 packed) external pure returns (bytes memory) {
        return BytePackLib.unpack(packed);
    }

    function isPacked(bytes32 value) external pure returns (bool) {
        return BytePackLib.isPacked(value);
    }

    function packedLength(bytes32 packed) external pure returns (uint256) {
        return BytePackLib.packedLength(packed);
    }
}

contract BytePackLibTest is Test {
    TestWrapper wrapper;

    function setUp() public {
        wrapper = new TestWrapper();
    }

    /// @notice Test packing and unpacking for all valid sizes (0-31 bytes)
    function test_AllValidSizes() public {
        for (uint256 i = 0; i <= 31; i++) {
            // Test with incrementing pattern
            bytes memory data = new bytes(i);
            for (uint256 j = 0; j < i; j++) {
                data[j] = bytes1(uint8(j % 256));
            }
            this.helperPackUnpack(data);

            // Also test with all zeros
            bytes memory zeros = new bytes(i);
            this.helperPackUnpack(zeros);

            // Also test with all 0xFF
            bytes memory ones = new bytes(i);
            for (uint256 j = 0; j < i; j++) {
                ones[j] = bytes1(0xFF);
            }
            this.helperPackUnpack(ones);
        }
    }

    function helperPackUnpack(bytes calldata data) external view {
        require(data.length < 32, "Data must be less than 32 bytes");

        bytes32 packed = wrapper.packCalldata(data);

        // Verify it's marked as packed
        assertTrue(wrapper.isPacked(packed), "Should be marked as packed");

        // Verify the length is correct
        assertEq(wrapper.packedLength(packed), data.length, "Length should match");

        // Verify unpacking gives back the original data
        bytes memory unpacked = wrapper.unpack(packed);
        assertEq(unpacked, data, "Unpacked data should match original");

        // Verify the tag byte is correct (length + 1)
        uint8 tag = uint8(uint256(packed >> 248));
        assertEq(tag, data.length + 1, "Tag should be length + 1");
    }

    /// @notice Test that packing 32+ bytes reverts
    function test_PackingTooLarge_Reverts() public {
        for (uint256 size = 32; size <= 40; size++) {
            bytes memory data = new bytes(size);

            vm.expectRevert(abi.encodeWithSelector(BytePackLib.ContentTooLarge.selector, size));
            this.helperPackLarge(data);
        }
    }

    function helperPackLarge(bytes calldata data) external view {
        wrapper.packCalldata(data);
    }

    /// @notice Test that unpacking non-packed data reverts
    function test_UnpackNonPacked_Reverts() public {
        // Test with zero bytes32 (tag = 0)
        bytes32 zero = bytes32(0);
        assertFalse(wrapper.isPacked(zero), "Zero should not be packed");
        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.unpack(zero);

        // Test with an address-like value (no tag byte)
        bytes32 addressLike = bytes32(uint256(uint160(address(0x1234567890123456789012345678901234567890))));
        assertFalse(wrapper.isPacked(addressLike), "Address should not be packed");
        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.unpack(addressLike);

        // Test with tag byte > 32 (e.g., 0x21 = 33)
        bytes32 invalidTag = bytes32(uint256(0x21) << 248);
        assertFalse(wrapper.isPacked(invalidTag), "Tag > 32 should not be packed");
        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.unpack(invalidTag);

        // Test with tag byte = 255 (maximum uint8)
        bytes32 maxTag = bytes32(uint256(0xFF) << 248);
        assertFalse(wrapper.isPacked(maxTag), "Tag = 255 should not be packed");
        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.unpack(maxTag);

        // Test getting length of non-packed data
        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.packedLength(zero);

        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.packedLength(addressLike);

        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.packedLength(invalidTag);

        vm.expectRevert(BytePackLib.NotPackedData.selector);
        wrapper.packedLength(maxTag);
    }

    /// @notice Test isPacked detection
    function test_IsPacked_Detection() public {
        // Pack some data and verify detection
        bytes memory testData = hex"74657374"; // "test"
        bytes32 packed = wrapper.packCalldata(testData);
        assertTrue(wrapper.isPacked(packed), "Packed data should be detected");

        // Regular addresses should not be detected as packed
        address addr = address(0x1234567890123456789012345678901234567890);
        bytes32 addrBytes = bytes32(uint256(uint160(addr)));
        assertFalse(wrapper.isPacked(addrBytes), "Address should not be detected as packed");

        // Zero should not be detected as packed
        assertFalse(wrapper.isPacked(bytes32(0)), "Zero should not be detected as packed");

        // Random data without tag byte (first byte is 0x00) should not be detected as packed
        bytes32 randomData = bytes32(uint256(0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff));
        assertFalse(wrapper.isPacked(randomData), "Random data should not be detected as packed");
    }

    /// @notice Test the exact packed format
    function test_PackedFormat() public {
        // Test empty bytes
        bytes memory empty = "";
        bytes32 packedEmpty = wrapper.packCalldata(empty);
        assertEq(uint256(packedEmpty), uint256(bytes32(bytes1(0x01))), "Empty should pack to 0x01 followed by zeros");

        // Test single byte 'A' (0x41)
        bytes memory single = hex"41";
        bytes32 packedSingle = wrapper.packCalldata(single);
        // Should be: tag=0x02, data=0x41, rest zeros
        assertEq(uint8(uint256(packedSingle >> 248)), 0x02, "Tag for 1 byte should be 2");
        assertEq(uint8(uint256(packedSingle >> 240)), 0x41, "Data should be 0x41");

        // Test "ABC" (0x414243)
        bytes memory abc = hex"414243";
        bytes32 packedAbc = wrapper.packCalldata(abc);
        // Should be: tag=0x04, data=0x414243, rest zeros
        assertEq(uint8(uint256(packedAbc >> 248)), 0x04, "Tag for 3 bytes should be 4");
        assertEq(uint8(uint256(packedAbc >> 240)), 0x41, "First byte should be 0x41");
        assertEq(uint8(uint256(packedAbc >> 232)), 0x42, "Second byte should be 0x42");
        assertEq(uint8(uint256(packedAbc >> 224)), 0x43, "Third byte should be 0x43");
    }

    /// @notice Test edge cases
    function test_EdgeCases() public {
        // Test 31 bytes (maximum packable)
        bytes memory max = new bytes(31);
        for (uint i = 0; i < 31; i++) {
            max[i] = bytes1(uint8(i));
        }

        bytes32 packed = wrapper.packCalldata(max);
        assertTrue(wrapper.isPacked(packed), "31 bytes should be packed");
        assertEq(wrapper.packedLength(packed), 31, "Length should be 31");

        bytes memory unpacked = wrapper.unpack(packed);
        assertEq(unpacked, max, "31 bytes should unpack correctly");

        // Verify tag is 32 (31 + 1) - the maximum valid tag
        assertEq(uint8(uint256(packed >> 248)), 32, "Tag for 31 bytes should be 32");

        // Manually create a bytes32 with tag = 32 (boundary case) and verify it's valid
        bytes32 dataBytes;
        assembly {
            dataBytes := mload(add(max, 0x20))
        }
        bytes32 boundaryTag = bytes32(uint256(32) << 248) | (dataBytes >> 8);
        assertTrue(wrapper.isPacked(boundaryTag), "Tag = 32 should be valid packed data");
        assertEq(wrapper.packedLength(boundaryTag), 31, "Tag = 32 means 31 bytes of data");
    }
}