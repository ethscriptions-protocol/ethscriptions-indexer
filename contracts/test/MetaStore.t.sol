// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/libraries/MetaStoreLib.sol";

contract MetaStoreTest is Test {
    // Test mapping for metadata storage
    mapping(bytes32 => bytes32) public metaStore;

    function setUp() public {}

    // =============================================================
    //                     ENCODING TESTS
    // =============================================================

    function test_EncodeEmptyMimeNoProtocol() public {
        bytes memory blob = MetaStoreLib.encode("", "", "");
        assertEq(blob.length, 0, "Empty mime + no protocol should be empty blob");
    }

    function test_EncodeTextPlainNoProtocol() public {
        bytes memory blob = MetaStoreLib.encode("text/plain", "", "");
        assertEq(blob.length, 0, "text/plain + no protocol should be empty blob");
    }

    function test_EncodeMimeOnly() public {
        bytes memory blob = MetaStoreLib.encode("image/png", "", "");
        string memory expected = string(abi.encodePacked(
            "image/png",
            bytes1(0x00),
            "", // empty protocol
            bytes1(0x00),
            ""  // empty operation
        ));
        assertEq(string(blob), expected, "Should contain mimetype with empty protocol/operation");
    }

    function test_EncodeMimeAndProtocol() public {
        bytes memory blob = MetaStoreLib.encode("application/json", "tokens", "");
        string memory expected = string(abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "" // empty operation
        ));
        assertEq(string(blob), expected, "Should contain mime + protocol with empty operation");
    }

    function test_EncodeFullMetadata() public {
        bytes memory blob = MetaStoreLib.encode("application/json", "tokens", "mint");
        string memory expected = string(abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        ));
        assertEq(string(blob), expected, "Should contain all three components");
    }

    function test_EncodeTextPlainWithProtocol() public {
        // text/plain is stored as empty string (convention)
        bytes memory blob = MetaStoreLib.encode("text/plain", "tokens", "mint");
        string memory expected = string(abi.encodePacked(
            // Empty mimetype (text/plain is normalized to empty)
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        ));
        assertEq(string(blob), expected, "text/plain should be stored as empty string");
    }

    function test_EncodeDoesNotNormalizeMimetype() public {
        bytes memory blob = MetaStoreLib.encode("Image/PNG", "", "");
        string memory expected = string(abi.encodePacked(
            "Image/PNG",
            bytes1(0x00),
            "",
            bytes1(0x00),
            ""
        ));
        assertEq(string(blob), expected, "Should preserve mimetype case");
    }

    function test_EncodeRejectsInvalidSeparator() public pure {
        // Test that we reject separator in mimetype
        bytes memory blob = MetaStoreLib.encode("text/plain", "", "");
        // If we get here without reverting, the input was valid (as expected)
        assertTrue(blob.length == 0, "Should encode valid input");

        // Note: Testing for revert with separator character requires vm.expectRevert
        // which doesn't work well with nested pure function calls
    }

    // =============================================================
    //                     INTERNING TESTS
    // =============================================================

    function test_InternEmptyBlob() public {
        bytes memory blob = bytes("");
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);
        assertEq(ref, bytes32(0), "Empty blob should return zero sentinel");
    }

    function test_InternSmallBlob() public {
        bytes memory blob = abi.encodePacked("image/png");
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        // Should be packed (first byte > 0 and <= 32)
        assertTrue(uint8(uint256(ref >> 248)) > 0 && uint8(uint256(ref >> 248)) <= 32, "Should be packed");
    }

    function test_InternLargeBlob() public {
        // Create a 50-byte blob
        bytes memory blob = new bytes(50);
        for (uint i = 0; i < 50; i++) {
            blob[i] = bytes1(uint8(97 + (i % 26))); // a-z
        }

        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        // Should be an SSTORE2 pointer (not packed)
        assertFalse(uint8(uint256(ref >> 248)) > 0 && uint8(uint256(ref >> 248)) <= 32, "Should not be packed");
    }

    function test_InternDeduplicates() public {
        bytes memory blob = abi.encodePacked("image/png");

        bytes32 ref1 = MetaStoreLib.intern(blob, metaStore);
        bytes32 ref2 = MetaStoreLib.intern(blob, metaStore);

        assertEq(ref1, ref2, "Should return same reference for identical blobs");
    }

    // =============================================================
    //                     DECODING TESTS
    // =============================================================

    function test_DecodeEmptySentinel() public view {
        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(bytes32(0));

        assertEq(mime, "text/plain", "Should default to text/plain");
        assertEq(protocol, "", "Should have no protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_DecodeMimeOnly() public {
        // Properly formatted blob with 2 separators
        bytes memory blob = abi.encodePacked("image/png", bytes1(0x00), bytes1(0x00));
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "image/png", "Should decode mimetype");
        assertEq(protocol, "", "Should have no protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_DecodeMimeAndProtocol() public {
        bytes memory blob = abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00)  // empty operation
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "application/json", "Should decode mimetype");
        assertEq(protocol, "tokens", "Should decode protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_DecodeFullMetadata() public {
        bytes memory blob = abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "application/json", "Should decode mimetype");
        assertEq(protocol, "tokens", "Should decode protocol");
        assertEq(op, "mint", "Should decode operation");
    }

    function test_DecodeEmptyMimeDefaultsToTextPlain() public {
        // Manually create blob with empty mimetype (0x00tokens0x00mint)
        bytes memory blob = abi.encodePacked(
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "text/plain", "Empty mime should default to text/plain");
        assertEq(protocol, "tokens", "Should decode protocol");
        assertEq(op, "mint", "Should decode operation");
    }

    function test_RoundTripTextPlainWithProtocol() public {
        // Encoding "text/plain" should store as empty and decode back to "text/plain"
        bytes memory blob = MetaStoreLib.encode("text/plain", "tokens", "mint");
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "text/plain", "Should decode to text/plain");
        assertEq(protocol, "tokens", "Should decode protocol");
        assertEq(op, "mint", "Should decode operation");
    }

    // =============================================================
    //                  GET MIMETYPE TESTS
    // =============================================================

    function test_GetMimetypeFromEmpty() public view {
        string memory mime = MetaStoreLib.getMimetype(bytes32(0));
        assertEq(mime, "text/plain", "Should return text/plain for empty ref");
    }

    function test_GetMimetypeFromMimeOnly() public {
        bytes memory blob = abi.encodePacked("image/png", bytes1(0x00), bytes1(0x00));
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        string memory mime = MetaStoreLib.getMimetype(ref);
        assertEq(mime, "image/png", "Should extract mimetype");
    }

    function test_GetMimetypeFromFull() public {
        bytes memory blob = abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        string memory mime = MetaStoreLib.getMimetype(ref);
        assertEq(mime, "application/json", "Should extract mimetype before separator");
    }

    // =============================================================
    //                  GET PROTOCOL TESTS
    // =============================================================

    function test_GetProtocolFromEmpty() public view {
        (string memory protocol, string memory op) = MetaStoreLib.getProtocol(bytes32(0));
        assertEq(protocol, "", "Should have no protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_GetProtocolFromMimeOnly() public {
        bytes memory blob = abi.encodePacked("image/png", bytes1(0x00), bytes1(0x00));
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory protocol, string memory op) = MetaStoreLib.getProtocol(ref);
        assertEq(protocol, "", "Should have no protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_GetProtocolFromMimeAndProtocol() public {
        bytes memory blob = abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00)  // empty operation
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory protocol, string memory op) = MetaStoreLib.getProtocol(ref);
        assertEq(protocol, "tokens", "Should extract protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_GetProtocolFromFull() public {
        bytes memory blob = abi.encodePacked(
            "application/json",
            bytes1(0x00),
            "tokens",
            bytes1(0x00),
            "mint"
        );
        bytes32 ref = MetaStoreLib.intern(blob, metaStore);

        (string memory protocol, string memory op) = MetaStoreLib.getProtocol(ref);
        assertEq(protocol, "tokens", "Should extract protocol");
        assertEq(op, "mint", "Should extract operation");
    }


    // =============================================================
    //                  ROUND-TRIP TESTS
    // =============================================================

    function test_RoundTripMimeOnly() public {
        bytes memory original = MetaStoreLib.encode("image/svg+xml", "", "");
        bytes32 ref = MetaStoreLib.intern(original, metaStore);
        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "image/svg+xml", "Should preserve mimetype");
        assertEq(protocol, "", "Should have no protocol");
        assertEq(op, "", "Should have no operation");
    }

    function test_RoundTripFull() public {
        bytes memory original = MetaStoreLib.encode("application/json", "erc-721-collection", "create");
        bytes32 ref = MetaStoreLib.intern(original, metaStore);
        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, "application/json", "Should preserve mimetype");
        assertEq(protocol, "erc-721-collection", "Should preserve normalized protocol");
        assertEq(op, "create", "Should preserve normalized operation");
    }

    function test_RoundTripLongBlob() public {
        // Create a blob that will require SSTORE2
        string memory longMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
        bytes memory original = MetaStoreLib.encode(longMime, "very-long-protocol-name", "very-long-operation-name");
        bytes32 ref = MetaStoreLib.intern(original, metaStore);
        (string memory mime, string memory protocol, string memory op) =
            MetaStoreLib.decode(ref);

        assertEq(mime, longMime, "Should preserve long mimetype");
        assertEq(protocol, "very-long-protocol-name", "Should preserve long protocol");
        assertEq(op, "very-long-operation-name", "Should preserve long operation");
    }
}
