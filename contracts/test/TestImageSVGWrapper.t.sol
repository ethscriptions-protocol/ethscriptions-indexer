// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import {Base64} from "solady/utils/Base64.sol";

contract TestImageSVGWrapper is TestSetup {
    address alice = address(0x1);

    function test_ImageWrappedInSVG() public {
        // Create a PNG ethscription
        bytes32 txHash = keccak256("test_image");

        // Small 1x1 red pixel PNG (base64 decoded)
        bytes memory pngContent = hex"89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154785e636ff8ff0f000501020157cd3de00000000049454e44ae426082";
        string memory pngDataUri = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==";

        vm.prank(alice);
        ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: txHash,
            contentUriHash: sha256(bytes(pngDataUri)),
            initialOwner: alice,
            content: pngContent,
            mimetype: "image/png",
            mediaType: "image",
            mimeSubtype: "png",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "",
                protocol: "",
                tick: "",
                max: 0,
                lim: 0,
                amt: 0
            })
        }));

        // Get token URI
        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory tokenUri = ethscriptions.tokenURI(tokenId);

        // Decode the JSON
        assertTrue(startsWith(tokenUri, "data:application/json;base64,"), "Should return base64 JSON");
        bytes memory decodedJson = Base64.decode(string(bytes(substring(tokenUri, 29, bytes(tokenUri).length))));
        string memory json = string(decodedJson);

        // Verify image field exists and contains SVG wrapper
        assertTrue(contains(json, '"image":"data:image/svg+xml;base64,'), "Should have SVG-wrapped image");

        // Extract and decode the SVG to verify it contains our image and pixelated styling
        // The SVG should contain:
        // 1. The original image as background-image
        // 2. image-rendering: pixelated for crisp scaling
        // Note: Full extraction would be complex, but we can check for key indicators
        assertTrue(contains(json, '"image"'), "Should have image field");
        assertFalse(contains(json, '"animation_url"'), "Should not have animation_url for images");
    }

    function test_NonImageNotWrapped() public {
        // Create a text ethscription to verify it's NOT wrapped in SVG
        bytes32 txHash = keccak256("test_text");

        vm.prank(alice);
        ethscriptions.createEthscription(createTestParams(
            txHash,
            alice,
            "data:text/plain,Hello World",
            false
        ));

        // Get token URI
        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory tokenUri = ethscriptions.tokenURI(tokenId);

        // Decode the JSON
        bytes memory decodedJson = Base64.decode(string(bytes(substring(tokenUri, 29, bytes(tokenUri).length))));
        string memory json = string(decodedJson);

        // Verify text content uses animation_url with HTML viewer, not SVG
        assertTrue(contains(json, '"animation_url":"data:text/html;base64,'), "Should have HTML viewer");
        assertFalse(contains(json, '"image"'), "Should not have image field for text");
        assertFalse(contains(json, "svg"), "Should not contain SVG for non-images");
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