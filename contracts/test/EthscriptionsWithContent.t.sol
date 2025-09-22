// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";

contract EthscriptionsWithContentTest is TestSetup {

    function testGetEthscriptionWithContent() public {
        // Create a test ethscription first
        bytes32 txHash = bytes32(uint256(12345));
        address creator = address(0x1);
        address initialOwner = address(0x2);
        string memory testContent = "Hello, World!";

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: txHash,
            contentUriHash: keccak256(bytes("data:text/plain,Hello, World!")),
            initialOwner: initialOwner,
            content: bytes(testContent),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "",
                protocol: "",
                tick: "",
                max: 0,
                lim: 0,
                amt: 0
            })
        });

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Test the new combined method
        (Ethscriptions.Ethscription memory ethscription, bytes memory content) = ethscriptions.getEthscriptionWithContent(txHash);

        // Verify ethscription data
        assertEq(ethscription.creator, creator);
        assertEq(ethscription.initialOwner, initialOwner);
        assertEq(ethscription.previousOwner, creator);
        assertEq(ethscription.ethscriptionNumber, tokenId);
        assertEq(ethscription.content.mimetype, "text/plain");
        assertEq(ethscription.content.mediaType, "text");
        assertEq(ethscription.content.mimeSubtype, "plain");
        assertEq(ethscription.content.esip6, false);

        // Verify content
        assertEq(content, bytes(testContent));

        // Compare with individual method calls to ensure they return the same data
        Ethscriptions.Ethscription memory ethscriptionSeparate = ethscriptions.getEthscription(txHash);
        bytes memory contentSeparate = ethscriptions.getEthscriptionContent(txHash);

        // Compare structs (we'll compare individual fields since struct comparison isn't directly supported)
        assertEq(ethscription.creator, ethscriptionSeparate.creator);
        assertEq(ethscription.initialOwner, ethscriptionSeparate.initialOwner);
        assertEq(ethscription.previousOwner, ethscriptionSeparate.previousOwner);
        assertEq(ethscription.ethscriptionNumber, ethscriptionSeparate.ethscriptionNumber);
        assertEq(ethscription.createdAt, ethscriptionSeparate.createdAt);
        assertEq(ethscription.l1BlockNumber, ethscriptionSeparate.l1BlockNumber);
        assertEq(ethscription.l2BlockNumber, ethscriptionSeparate.l2BlockNumber);
        assertEq(ethscription.l1BlockHash, ethscriptionSeparate.l1BlockHash);

        // Compare content info
        assertEq(ethscription.content.contentUriHash, ethscriptionSeparate.content.contentUriHash);
        assertEq(ethscription.content.contentSha, ethscriptionSeparate.content.contentSha);
        assertEq(ethscription.content.mimetype, ethscriptionSeparate.content.mimetype);
        assertEq(ethscription.content.mediaType, ethscriptionSeparate.content.mediaType);
        assertEq(ethscription.content.mimeSubtype, ethscriptionSeparate.content.mimeSubtype);
        assertEq(ethscription.content.esip6, ethscriptionSeparate.content.esip6);

        // Compare content
        assertEq(content, contentSeparate);
    }

    function testGetEthscriptionWithContentNonExistent() public {
        bytes32 nonExistentTxHash = bytes32(uint256(99999));

        // Should revert with EthscriptionDoesNotExist
        vm.expectRevert(Ethscriptions.EthscriptionDoesNotExist.selector);
        ethscriptions.getEthscriptionWithContent(nonExistentTxHash);
    }

    function testGetEthscriptionWithContentLargeContent() public {
        // Test with content that requires multiple SSTORE2 chunks
        bytes32 txHash = bytes32(uint256(54321));
        address creator = address(0x3);
        address initialOwner = address(0x4);

        // Create content larger than CHUNK_SIZE (24575 bytes)
        bytes memory largeContent = new bytes(30000);
        for (uint256 i = 0; i < 30000; i++) {
            largeContent[i] = bytes1(uint8(i % 256));
        }

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: txHash,
            contentUriHash: keccak256(bytes("data:application/octet-stream,<large content>")),
            initialOwner: initialOwner,
            content: largeContent,
            mimetype: "application/octet-stream",
            mediaType: "application",
            mimeSubtype: "octet-stream",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "",
                protocol: "",
                tick: "",
                max: 0,
                lim: 0,
                amt: 0
            })
        });

        ethscriptions.createEthscription(params);

        // Test the combined method with large content
        (Ethscriptions.Ethscription memory ethscription, bytes memory content) = ethscriptions.getEthscriptionWithContent(txHash);

        // Verify content is correct
        assertEq(content.length, 30000);
        assertEq(content, largeContent);

        // Verify ethscription data
        assertEq(ethscription.creator, creator);
        assertEq(ethscription.initialOwner, initialOwner);
    }
}