// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import {LibZip} from "solady/utils/LibZip.sol";
import {LibString} from "solady/utils/LibString.sol";
import "forge-std/console.sol";

contract EndToEndCompressionTest is TestSetup {
    using LibZip for bytes;
    using LibString for *;
    
    // function testRubyCompressionEndToEnd() public {
    //     // Load example ethscription content
    //     string memory json = vm.readFile("test/example_ethscription.json");
    //     // string memory originalContent = vm.parseJsonString(json, ".result.content_uri");
    //     string memory originalContent = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAoMBg+QK2EoAAAAASUVORK5CYII=";
    //     // Call Ruby script to compress the content
    //     string[] memory inputs = new string[](3);
    //     inputs[0] = "ruby";
    //     inputs[1] = "test/compress_content.rb";
    //     inputs[2] = originalContent;
        
    //     bytes memory result = vm.ffi(inputs);
        
    //     // Parse the JSON response from Ruby
    //     string memory jsonResult = string(result);
    //     bytes memory compressedContent = vm.parseJsonBytes(jsonResult, ".compressed");
    //     bool isCompressed = vm.parseJsonBool(jsonResult, ".is_compressed");
    //     uint256 originalSize = vm.parseJsonUint(jsonResult, ".original_size");
    //     uint256 compressedSize = vm.parseJsonUint(jsonResult, ".compressed_size");
        
    //     console.log("Original size:", bytes(originalContent).length);
    //     console.log("Original rune count:", originalContent.runeCount());
    //     console.log("Compressed size:", compressedContent.length);
    //     console.log("Is compressed:", isCompressed);
        
    //     if (isCompressed) {
    //         console.log("Compression ratio:", (compressedSize * 100) / originalSize, "%");
            
    //         // Verify the compressed content can be decompressed
    //         bytes memory decompressed = LibZip.flzDecompress(compressedContent);
    //         assertEq(decompressed.toHexString(), bytes(originalContent).toHexString(), "Decompressed content should match original");
    //     }
        
    //     // // Create ethscription with the result from Ruby
    //     // bytes32 txHash = bytes32(uint256(0x52554259)); // "RUBY" in hex
    //     // address owner = address(0xCAFE);
        
    //     // vm.prank(owner);
    //     // uint256 tokenId = ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
    //     //     transactionHash: txHash,
    //     //     initialOwner: owner,
    //     //     contentUri: isCompressed ? compressedContent : bytes(originalContent),
    //     //     mimetype: "image/png",
    //     //     mediaType: "image",
    //     //     mimeSubtype: "png",
    //     //     esip6: false,
    //     //     isCompressed: isCompressed,
    //     //     tokenParams: Ethscriptions.TokenParams({
    //     //         op: "",
    //     //         protocol: "",
    //     //         tick: "",
    //     //         max: 0,
    //     //         lim: 0,
    //     //         amt: 0
    //     //     })
    //     // }));
        
    //     // // Verify the ethscription was created
    //     // assertEq(tokenId, uint256(txHash));
    //     // assertEq(ethscriptions.ownerOf(tokenId), owner);
        
    //     // // Get tokenURI - should automatically decompress if needed
    //     // string memory tokenURI = ethscriptions.tokenURI(tokenId);
    //     // assertEq(tokenURI, originalContent, "Retrieved content should match original");
        
    //     // console.log("Successfully created ethscription with Ruby compression decision!");
    // }
    
    // function testMultipleContentsWithRuby() public {
    //     // Test various content types through Ruby
    //     string[3] memory testContents;
    //     testContents[0] = "data:text/plain,Hello World!"; // Small text - shouldn't compress
        
    //     // Build a repetitive JSON string that should compress well
    //     bytes memory jsonData = abi.encodePacked('{"data":"');
    //     for (uint i = 0; i < 100; i++) {
    //         jsonData = abi.encodePacked(jsonData, 'AAAAAAAAAA');
    //     }
    //     jsonData = abi.encodePacked(jsonData, '"}');
    //     testContents[1] = string(abi.encodePacked("data:application/json,", jsonData));
        
    //     testContents[2] = "data:image/svg+xml,<svg><rect/><rect/><rect/><rect/><rect/></svg>"; // SVG - should compress
        
    //     for (uint i = 0; i < testContents.length; i++) {
    //         console.log("Testing content", i);
            
    //         string[] memory inputs = new string[](3);
    //         inputs[0] = "ruby";
    //         inputs[1] = "test/compress_content.rb";
    //         inputs[2] = testContents[i];
            
    //         bytes memory result = vm.ffi(inputs);
    //         string memory jsonResult = string(result);
            
    //         bool isCompressed = vm.parseJsonBool(jsonResult, ".is_compressed");
    //         uint256 originalSize = vm.parseJsonUint(jsonResult, ".original_size");
    //         uint256 compressedSize = vm.parseJsonUint(jsonResult, ".compressed_size");
            
    //         console.log("  Original size:", originalSize);
    //         console.log("  Result size:", compressedSize);
    //         console.log("  Compressed:", isCompressed);
            
    //         if (isCompressed) {
    //             uint256 ratio = (compressedSize * 100) / originalSize;
    //             console.log("  Compression ratio:", ratio, "%");
    //             // Should be at least 10% smaller if compressed
    //             assertTrue(ratio <= 90, "Compression should achieve at least 10% reduction");
    //         }
    //     }
    // }
}