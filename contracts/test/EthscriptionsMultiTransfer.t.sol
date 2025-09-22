// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibZip} from "solady/utils/LibZip.sol";

contract EthscriptionsMultiTransferTest is TestSetup {
    using LibString for uint256;
    using LibString for address;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    bytes32[] testHashes;

    function setUp() public override {
        super.setUp();

        // Give alice some ETH
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    function createTestEthscription(
        address creator,
        address initialOwner,
        uint256 index
    ) internal returns (bytes32) {
        bytes32 txHash = keccak256(abi.encodePacked("test", index));
        string memory content = string.concat("data:text/plain,Test Content ", index.toString());

        vm.prank(creator);
        ethscriptions.createEthscription(
            createTestParams(
                txHash,
                initialOwner,
                content,
                false
            )
        );

        return txHash;
    }

    function test_TransferMultipleEthscriptions_Success() public {
        // Create 5 ethscriptions owned by alice
        bytes32[] memory hashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            hashes[i] = createTestEthscription(alice, alice, i);
        }

        // Alice transfers all 5 to bob
        vm.prank(alice);
        uint256 successCount = ethscriptions.transferMultipleEthscriptions(hashes, bob);

        assertEq(successCount, 5, "Should have 5 successful transfers");

        // Verify all are now owned by bob
        for (uint256 i = 0; i < 5; i++) {
            address owner = ethscriptions.ownerOf(hashes[i]);
            assertEq(owner, bob, "Bob should own the ethscription");
        }
    }

    function test_TransferMultipleEthscriptions_PartialSuccess() public {
        // Create 5 ethscriptions - 3 owned by alice, 2 owned by bob
        bytes32[] memory hashes = new bytes32[](5);
        for (uint256 i = 0; i < 3; i++) {
            hashes[i] = createTestEthscription(alice, alice, i);
        }
        for (uint256 i = 3; i < 5; i++) {
            hashes[i] = createTestEthscription(bob, bob, i);
        }

        // Alice tries to transfer all 5 to charlie (but only owns 3)
        vm.prank(alice);
        uint256 successCount = ethscriptions.transferMultipleEthscriptions(hashes, charlie);

        assertEq(successCount, 3, "Should have 3 successful transfers");

        // Verify ownership
        for (uint256 i = 0; i < 3; i++) {
            address owner = ethscriptions.ownerOf(hashes[i]);
            assertEq(owner, charlie, "Charlie should own alice's ethscriptions");
        }
        for (uint256 i = 3; i < 5; i++) {
            address owner = ethscriptions.ownerOf(hashes[i]);
            assertEq(owner, bob, "Bob should still own his ethscriptions");
        }
    }

    function test_TransferMultipleEthscriptions_NoSuccessReverts() public {
        // Create 3 ethscriptions owned by bob
        bytes32[] memory hashes = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            hashes[i] = createTestEthscription(bob, bob, i);
        }

        // Alice tries to transfer them (but owns none)
        vm.prank(alice);
        vm.expectRevert("No successful transfers");
        ethscriptions.transferMultipleEthscriptions(hashes, charlie);
    }

    function test_TransferMultipleEthscriptions_Burn() public {
        // Create 3 ethscriptions owned by alice
        bytes32[] memory hashes = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            hashes[i] = createTestEthscription(alice, alice, i);
        }

        // Alice burns all 3 by transferring to address(0)
        vm.prank(alice);
        uint256 successCount = ethscriptions.transferMultipleEthscriptions(hashes, address(0));

        assertEq(successCount, 3, "Should have 3 successful burns");

        // Verify all are owned by address(0) (null ownership, not burned)
        for (uint256 i = 0; i < 3; i++) {
            assertEq(ethscriptions.currentOwner(hashes[i]), address(0), "Should be owned by null address");
        }
    }

    function test_TransferMultipleEthscriptions_EmitsEvents() public {
        // Create 2 ethscriptions owned by alice
        bytes32[] memory hashes = new bytes32[](2);
        for (uint256 i = 0; i < 2; i++) {
            hashes[i] = createTestEthscription(alice, alice, i);
        }

        // Expect transfer events (starting from ethscription #11 due to genesis)
        for (uint256 i = 0; i < 2; i++) {
            vm.expectEmit(true, true, true, true);
            emit Ethscriptions.EthscriptionTransferred(
                hashes[i],
                alice,
                bob,
                11 + i // ethscription number starts at 11 due to genesis
            );
        }

        // Alice transfers both to bob
        vm.prank(alice);
        ethscriptions.transferMultipleEthscriptions(hashes, bob);
    }

    function test_TokenURI_ReturnsValidJSON() public {
        // Create an ethscription
        bytes32 txHash = createTestEthscription(alice, alice, 1);
        uint256 tokenId = ethscriptions.getTokenId(txHash);

        // Get the token URI
        string memory uri = ethscriptions.tokenURI(tokenId);

        // Check it starts with the correct data URI prefix
        assertTrue(
            startsWith(uri, "data:application/json;base64,"),
            "Should return base64-encoded JSON data URI"
        );

        // Decode the base64 to get the JSON
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Check JSON contains expected fields (ethscription #11 because of genesis ethscriptions)
        assertTrue(contains(json, '"name":"Ethscription #11"'), "Should have name");
        assertTrue(contains(json, '"description":"Ethscription #11 created by'), "Should have description");
        assertTrue(contains(json, '"animation_url":"data:text/html;base64,'), "Should have HTML viewer for text");
        assertFalse(contains(json, '"image"'), "Should not have image field for text content");
        assertTrue(contains(json, '"attributes":['), "Should have attributes array");

        // Check for specific attributes
        assertTrue(contains(json, '"trait_type":"Ethscription Number"'), "Should have ethscription number");
        assertTrue(contains(json, '"trait_type":"Creator"'), "Should have creator");
        assertTrue(contains(json, '"trait_type":"MIME Type","value":"text/plain"'), "Should have MIME type");
        assertTrue(contains(json, '"trait_type":"ESIP-6","value":"false"'), "Should have ESIP-6 flag");
    }

    function test_TokenURI_CompressedContent() public {
        // Create ethscription with compressed content
        bytes32 txHash = keccak256("compressed_test");
        bytes memory originalContent = bytes("data:text/plain,This is a test content that will be compressed");

        // Compress the content using LibZip
        bytes memory compressedContent = LibZip.flzCompress(originalContent);

        // We no longer support compression, just use the original content
        vm.prank(alice);
        ethscriptions.createEthscription(
            createTestParams(
                txHash,
                alice,
                string(originalContent),
                false
            )
        );

        // Get token URI
        string memory uri = ethscriptions.tokenURI(ethscriptions.getTokenId(txHash));

        // Decode and check
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Should contain HTML viewer in animation_url field for text content
        assertTrue(
            contains(json, '"animation_url":"data:text/html;base64,'),
            "Should have HTML viewer for text"
        );
        assertFalse(contains(json, '"image"'), "Should not have image field for text content");
    }

    function test_TokenURI_AllAttributes() public {
        // Create an ethscription and check all attributes are present
        bytes32 txHash = createTestEthscription(alice, bob, 99);

        string memory uri = ethscriptions.tokenURI(ethscriptions.getTokenId(txHash));
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Check all expected attributes
        string[11] memory expectedTraits = [
            "Ethscription Number",
            "Creator",
            "Initial Owner",
            "Content SHA",
            "MIME Type",
            "Media Type",
            "MIME Subtype",
            "ESIP-6",
            "L1 Block Number",
            "L2 Block Number",
            "Created At"
        ];

        for (uint256 i = 0; i < expectedTraits.length; i++) {
            assertTrue(
                contains(json, string.concat('"trait_type":"', expectedTraits[i], '"')),
                string.concat("Should have ", expectedTraits[i], " attribute")
            );
        }
    }

    // Helper functions
    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (prefixBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) return false;
        }
        return true;
    }

    function contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (substrBytes.length > strBytes.length) return false;

        for (uint256 i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function substring(string memory str, uint256 start, uint256 end) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        return string(result);
    }
}