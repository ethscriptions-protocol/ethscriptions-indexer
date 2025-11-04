// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";

contract EthscriptionsWithContentTest is TestSetup {

    function testGetEthscription() public {
        // Create a test ethscription first
        bytes32 txHash = bytes32(uint256(12345));
        address creator = address(0x1);
        address initialOwner = address(0x2);
        string memory testContent = "Hello, World!";

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256(bytes("data:text/plain,Hello, World!")),
            initialOwner: initialOwner,
            content: bytes(testContent),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Test the new getEthscription method that returns Ethscription
        Ethscriptions.Ethscription memory complete = ethscriptions.getEthscription(txHash);

        // Verify ethscription data
        assertEq(complete.ethscriptionId, txHash);
        assertEq(complete.ethscriptionNumber, tokenId);
        assertEq(complete.creator, creator);
        assertEq(complete.initialOwner, initialOwner);
        assertEq(complete.previousOwner, creator);
        assertEq(complete.currentOwner, initialOwner);
        assertEq(complete.mimetype, "text/plain");
        assertEq(complete.esip6, false);

        // Verify content
        assertEq(complete.content, bytes(testContent));

        // Test the version without content using the overloaded function
        Ethscriptions.Ethscription memory withoutContent = ethscriptions.getEthscription(txHash, false);

        // Verify same metadata but empty content
        assertEq(withoutContent.ethscriptionId, txHash);
        assertEq(withoutContent.ethscriptionNumber, tokenId);
        assertEq(withoutContent.creator, creator);
        assertEq(withoutContent.currentOwner, initialOwner);
        assertEq(withoutContent.content.length, 0, "Content should be empty");
    }

    function testGetEthscriptionByTokenId() public {
        // Create a test ethscription first
        bytes32 txHash = bytes32(uint256(67890));
        address creator = address(0x5);
        address initialOwner = address(0x6);
        string memory testContent = "Test by token ID";

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256(bytes("data:text/plain,Test by token ID")),
            initialOwner: initialOwner,
            content: bytes(testContent),
            mimetype: "text/plain",
            esip6: true,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Test getting by token ID
        Ethscriptions.Ethscription memory complete = ethscriptions.getEthscription(tokenId);

        // Verify ethscription data
        assertEq(complete.ethscriptionId, txHash, "Ethscription ID should match");
        assertEq(complete.ethscriptionNumber, tokenId, "Token ID should match");
        assertEq(complete.creator, creator);
        assertEq(complete.currentOwner, initialOwner);
        assertEq(complete.content, bytes(testContent));

        // Test without content version by token ID using the overloaded function
        Ethscriptions.Ethscription memory withoutContent = ethscriptions.getEthscription(tokenId, false);
        assertEq(withoutContent.ethscriptionId, txHash);
        assertEq(withoutContent.content.length, 0, "Content should be empty");
    }

    function testGetEthscriptionNonExistent() public {
        bytes32 nonExistentTxHash = bytes32(uint256(99999));

        // Should revert with EthscriptionDoesNotExist
        vm.expectRevert(Ethscriptions.EthscriptionDoesNotExist.selector);
        ethscriptions.getEthscription(nonExistentTxHash);

        // Same for without content version using the overloaded function
        vm.expectRevert(Ethscriptions.EthscriptionDoesNotExist.selector);
        ethscriptions.getEthscription(nonExistentTxHash, false);
    }

    function testGetEthscriptionWithLargeContent() public {
        // Test with content that's large (testing SSTORE2Unlimited)
        bytes32 txHash = bytes32(uint256(54321));
        address creator = address(0x3);
        address initialOwner = address(0x4);

        // Create content larger than inline storage (>31 bytes)
        bytes memory largeContent = new bytes(30000);
        for (uint256 i = 0; i < 30000; i++) {
            largeContent[i] = bytes1(uint8(i % 256));
        }

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256(bytes("data:application/octet-stream,<large content>")),
            initialOwner: initialOwner,
            content: largeContent,
            mimetype: "application/octet-stream",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        ethscriptions.createEthscription(params);

        // Test the getEthscription method with large content
        Ethscriptions.Ethscription memory complete = ethscriptions.getEthscription(txHash);

        // Verify content is correct
        assertEq(complete.content.length, 30000);
        assertEq(complete.content, largeContent);

        // Verify ethscription data
        assertEq(complete.creator, creator);
        assertEq(complete.initialOwner, initialOwner);
        assertEq(complete.currentOwner, initialOwner);

        // Test without content - should have zero-length content using the overloaded function
        Ethscriptions.Ethscription memory withoutContent = ethscriptions.getEthscription(txHash, false);
        assertEq(withoutContent.content.length, 0, "Content should be empty");
        assertEq(withoutContent.creator, creator);
        assertEq(withoutContent.currentOwner, initialOwner);
    }

    function testGetEthscriptionWithSmallContent() public {
        // Test with content that fits inline (≤31 bytes)
        bytes32 txHash = bytes32(uint256(11111));
        address creator = address(0x7);
        address initialOwner = address(0x8);

        // Create small content (10 bytes)
        bytes memory smallContent = hex"48656c6c6f576f726c64"; // "HelloWorld"

        // Create the ethscription
        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256(bytes("data:text/plain,HelloWorld")),
            initialOwner: initialOwner,
            content: smallContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Test the getEthscription method with small inline content
        Ethscriptions.Ethscription memory complete = ethscriptions.getEthscription(txHash);

        // Verify content is correct
        assertEq(complete.content, smallContent);
        assertEq(complete.content.length, 10);

        // Verify ownership chain
        assertEq(complete.creator, creator);
        assertEq(complete.initialOwner, initialOwner);
        assertEq(complete.currentOwner, initialOwner);
        assertEq(complete.previousOwner, creator);

        // Test getting by token ID too
        Ethscriptions.Ethscription memory byTokenId = ethscriptions.getEthscription(tokenId);
        assertEq(byTokenId.ethscriptionId, txHash);
        assertEq(byTokenId.content, smallContent);
    }
}