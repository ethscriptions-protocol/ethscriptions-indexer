// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "forge-std/StdJson.sol";
import {Base64} from "solady/utils/Base64.sol";

contract EthscriptionsTextRendererTest is TestSetup {
    using stdJson for string;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function test_TextContent_UsesAnimationUrl() public {
        // Create a plain text ethscription
        bytes32 txHash = keccak256("test_text");
        string memory textContent = "Hello World!";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            alice,
            string.concat("data:text/plain,", textContent),
            false
        );

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory uri = ethscriptions.tokenURI(tokenId);

        // Decode the base64 JSON
        assertTrue(startsWith(uri, "data:application/json;base64,"), "Should return base64-encoded JSON");
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Verify it uses animation_url, not image
        assertTrue(contains(json, '"animation_url"'), "Should have animation_url field");
        assertFalse(contains(json, '"image"'), "Should NOT have image field");
        assertTrue(contains(json, "data:text/html;base64,"), "animation_url should be HTML viewer");
    }

    function test_JsonContent_UsesViewerWithPrettyPrint() public {
        // Create a JSON ethscription
        bytes32 txHash = keccak256("test_json");
        string memory jsonContent = '{"p":"erc-20","op":"mint","tick":"test","amt":"1000"}';

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            alice,
            string.concat("data:application/json,", jsonContent),
            false
        );

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory uri = ethscriptions.tokenURI(tokenId);

        // Decode the base64 JSON
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Verify it uses animation_url with HTML viewer for JSON content
        assertTrue(contains(json, '"animation_url"'), "Should have animation_url field");
        assertFalse(contains(json, '"image"'), "Should NOT have image field");
        // JSON should use the HTML viewer (not pass through directly)
        assertTrue(contains(json, "data:text/html;base64,"), "Should use HTML viewer for JSON");
    }

    function test_ImageContent_UsesImageField() public {
        // Create an image ethscription (base64 encoded PNG)
        bytes32 txHash = keccak256("test_image");
        string memory base64Image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            alice,
            string.concat("data:image/png;base64,", base64Image),
            false // esip6
        );

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory uri = ethscriptions.tokenURI(tokenId);

        // Decode the base64 JSON
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // Verify it uses image field, not animation_url
        assertTrue(contains(json, '"image"'), "Should have image field");
        assertFalse(contains(json, '"animation_url"'), "Should NOT have animation_url field");
        // Image should now be wrapped in SVG for pixel-perfect rendering
        assertTrue(contains(json, '"image":"data:image/svg+xml;base64,'), "image should be SVG-wrapped");
    }

    function test_HtmlContent_PassesThroughAsBase64() public {
        // Create an HTML ethscription
        bytes32 txHash = keccak256("test_html");
        string memory htmlContent = "<html><body><h1>Test</h1></body></html>";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            alice,
            string.concat("data:text/html,", htmlContent),
            false
        );

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 tokenId = ethscriptions.getTokenId(txHash);
        string memory uri = ethscriptions.tokenURI(tokenId);

        // Decode the base64 JSON
        bytes memory base64Part = bytes(substring(uri, 29, bytes(uri).length));
        bytes memory decodedJson = Base64.decode(string(base64Part));
        string memory json = string(decodedJson);

        // HTML should pass through as base64 for safety
        assertTrue(contains(json, '"animation_url"'), "Should have animation_url field");
        assertFalse(contains(json, '"image"'), "Should NOT have image field");
        assertTrue(contains(json, '"animation_url":"data:text/html;base64,'), "Should use base64 encoded HTML");
    }

    // Helper functions
    function startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);

        if (strBytes.length < prefixBytes.length) {
            return false;
        }

        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    function contains(string memory str, string memory substr) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory substrBytes = bytes(substr);

        if (strBytes.length < substrBytes.length) {
            return false;
        }

        for (uint i = 0; i <= strBytes.length - substrBytes.length; i++) {
            bool found = true;
            for (uint j = 0; j < substrBytes.length; j++) {
                if (strBytes[i + j] != substrBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }

    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}