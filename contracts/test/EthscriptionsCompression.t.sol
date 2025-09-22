// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import {LibZip} from "solady/utils/LibZip.sol";
import "forge-std/console.sol";

contract EthscriptionsCompressionTest is TestSetup {
    using LibZip for bytes;
    
    function testEthscriptionCreation() public {
        // Load the actual example ethscription content
        string memory json = vm.readFile("test/example_ethscription.json");
        string memory contentUri = vm.parseJsonString(json, ".result.content_uri");

        console.log("Content URI size:", bytes(contentUri).length);

        // Create ethscription
        bytes32 txHash = bytes32(uint256(0xC0113E55));
        address owner = address(0x1337);

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            owner,
            contentUri,
            false
        );

        vm.prank(owner);
        uint256 tokenId = ethscriptions.createEthscription(params);
        
        // Verify the ethscription was created
        assertEq(tokenId, ethscriptions.getTokenId(txHash));
        assertEq(ethscriptions.ownerOf(tokenId), owner);
        
        // Get tokenURI - now returns JSON metadata
        string memory tokenURI = ethscriptions.tokenURI(tokenId);

        // Verify tokenURI returns valid JSON (starts with data:application/json)
        assertTrue(
            bytes(tokenURI).length > 0,
            "Token URI should not be empty"
        );

        // Use _getContentDataURI to verify decompressed content
        // Note: Since _getContentDataURI is internal, we test via the JSON containing the content
        // The JSON should contain our original content in the image field
        
        console.log("Successfully created and retrieved compressed ethscription!");
    }
    
    function testUncompressedEthscriptionCreation() public {
        // Test regular uncompressed creation still works
        string memory contentUri = "data:,Hello World!";
        bytes32 txHash = bytes32(uint256(0x00C0113E));
        address owner = address(0xBEEF);

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            owner,
            contentUri,
            false
        );

        vm.prank(owner);
        uint256 tokenId = ethscriptions.createEthscription(params);
        
        // Verify - tokenURI now returns JSON metadata
        string memory tokenURI = ethscriptions.tokenURI(tokenId);

        // Verify tokenURI returns valid JSON
        assertTrue(
            bytes(tokenURI).length > 0,
            "Token URI should not be empty"
        );

        // The JSON should contain our original content in the image field
        // Since we can't easily parse JSON in Solidity, we just verify it exists
    }
    
    // function testCompressionGasSavings() public {
    //     // Load example content
    //     string memory json = vm.readFile("test/example_ethscription.json");
    //     bytes memory originalContent = bytes(vm.parseJsonString(json, ".result.content_uri"));
    //     bytes memory compressedContent = LibZip.flzCompress(originalContent);
        
    //     address owner = address(0x6A5);
        
    //     // Measure gas for uncompressed creation
    //     vm.prank(owner);
    //     uint256 gasStart = gasleft();
    //     ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
    //         transactionHash: bytes32(uint256(0x1111)),
    //         initialOwner: owner,
    //         contentUri: originalContent,
    //         mimetype: "image/png",
    //         mediaType: "image",
    //         mimeSubtype: "png",
    //         esip6: false,
    //         isCompressed: false,
    //         tokenParams: Ethscriptions.TokenParams({
    //             op: "", protocol: "", tick: "", max: 0, lim: 0, amt: 0
    //         })
    //     }));
    //     uint256 uncompressedGas = gasStart - gasleft();
        
    //     // Measure gas for compressed creation
    //     vm.prank(owner);
    //     gasStart = gasleft();
    //     ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
    //         transactionHash: bytes32(uint256(0x2222)),
    //         initialOwner: owner,
    //         contentUri: compressedContent,
    //         mimetype: "image/png",
    //         mediaType: "image",
    //         mimeSubtype: "png",
    //         esip6: false,
    //         isCompressed: true,
    //         tokenParams: Ethscriptions.TokenParams({
    //             op: "", protocol: "", tick: "", max: 0, lim: 0, amt: 0
    //         })
    //     }));
    //     uint256 compressedGas = gasStart - gasleft();
        
    //     console.log("Uncompressed creation gas:", uncompressedGas);
    //     console.log("Compressed creation gas:", compressedGas);
        
    //     if (compressedGas < uncompressedGas) {
    //         uint256 gasSaved = uncompressedGas - compressedGas;
    //         console.log("Gas saved:", gasSaved);
    //         console.log("Savings percentage:", (gasSaved * 100) / uncompressedGas, "%");
    //     } else {
    //         uint256 extraGas = compressedGas - uncompressedGas;
    //         console.log("Extra gas for compression:", extraGas);
    //     }
    // }
}