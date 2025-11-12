// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ERC721EthscriptionsCollectionManager.sol";
import "../src/ERC721EthscriptionsCollection.sol";
import "../src/Ethscriptions.sol";
import "../src/libraries/Predeploys.sol";
import "./TestSetup.sol";

contract CollectionsProtocolTest is TestSetup {
    address alice = makeAddr("alice");
    
    function test_CreateCollection() public {
        // Encode collection metadata as ABI tuple
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Test Collection",
                symbol: "TEST",
                maxSupply: 100,
                description: "A test collection",
                logoImageUri: "https://example.com/logo.png",
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0),
                initialOwner: alice  // Use alice as owner
            });

        bytes memory encodedMetadata = abi.encode(metadata);

        // Create the ethscription
        bytes32 txHash = keccak256("create_collection_tx");

        // First, create the ethscription that will represent this collection
        Ethscriptions.CreateEthscriptionParams memory ethscriptionParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: keccak256("test-collection-content"),
            initialOwner: alice,
            content: bytes("test-collection-content"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(ethscriptionParams);

        vm.prank(address(ethscriptions));
        collectionsHandler.op_create_collection(txHash, encodedMetadata);

        // Verify collection was created
        bytes32 collectionId = txHash;

        // Use the getter functions instead of direct mapping access
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory collection = collectionsHandler.getCollection(collectionId);
        assertNotEq(collection.collectionContract, address(0), "Collection contract should be deployed");
        assertEq(collection.locked, false, "Should not be locked");

        ERC721EthscriptionsCollection collectionContract = ERC721EthscriptionsCollection(collection.collectionContract);
        assertEq(collectionContract.totalSupply(), 0, "Initial size should be 0");

        // Verify metadata
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory stored = collectionsHandler.getCollection(collectionId);
        assertEq(stored.name, "Test Collection", "Name should match");
        assertEq(stored.symbol, "TEST", "Symbol should match");
        assertEq(stored.maxSupply, 100, "Max supply should match");
        assertEq(stored.description, "A test collection", "Description should match");
    }

    function test_CreateCollectionEndToEnd() public {
        // Full end-to-end test: create ethscription with JSON, let it call the protocol handler

        // The JSON data
        string memory json = '{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test NFTs","symbol":"TEST","maxSupply":"100","description":"","logoImageUri":"","bannerImageUri":"","backgroundColor":"","websiteLink":"","twitterLink":"","discordLink":""}';

        // Encode the metadata as the protocol handler expects
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Test NFTs",
                symbol: "TEST",
                maxSupply: 100,
                description: "",
                logoImageUri: "",
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0),
                initialOwner: alice  // Use alice as owner
            });

        bytes memory encodedProtocolData = abi.encode(metadata);

        // Create the ethscription with protocol params
        bytes32 txHash = keccak256(abi.encodePacked("test_collection_tx", block.timestamp));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: keccak256(bytes(json)),
            initialOwner: alice,
            content: bytes(json),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "create_collection",
                data: encodedProtocolData
            })
        });

        // Create the ethscription - this will call the protocol handler automatically
        vm.prank(alice);
        ethscriptions.createEthscription(params);

        bytes32 collectionId = txHash;

        // Read back the state
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory collection = collectionsHandler.getCollection(collectionId);

        console.log("Collection exists:", collection.collectionContract != address(0));
        console.log("Collection contract:", collection.collectionContract);
        ERC721EthscriptionsCollection collectionContract = ERC721EthscriptionsCollection(collection.collectionContract);
        console.log("Current size:", collectionContract.totalSupply());

        // Verify the collection was created
        assertTrue(collection.collectionContract != address(0), "Collection should exist");
        assertEq(collection.locked, false);
        assertEq(collectionContract.totalSupply(), 0);

        // Read metadata
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory stored = collectionsHandler.getCollection(collectionId);
        assertEq(stored.name, "Test NFTs");
        assertEq(stored.symbol, "TEST");
        assertEq(stored.maxSupply, 100);
    }

    function test_ReadCollectionStateViaEthCall() public {
        // Create a collection first
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Call Test",
                symbol: "CALL",
                maxSupply: 50,
                description: "",
                logoImageUri: "",
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0),
                initialOwner: alice  // Use alice as owner
            });

        bytes32 txHash = keccak256("call_test_tx");

        // First, create the ethscription that will represent this collection
        Ethscriptions.CreateEthscriptionParams memory ethscriptionParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: keccak256("call-test-content"),
            initialOwner: alice,
            content: bytes("call-test-content"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(ethscriptionParams);

        vm.prank(address(ethscriptions));
        collectionsHandler.op_create_collection(txHash, abi.encode(metadata));

        // Now simulate an eth_call to read the state
        bytes32 collectionId = txHash;

        // Encode the function call: getCollection(bytes32)
        bytes memory callData = abi.encodeWithSelector(
            collectionsHandler.getCollection.selector,
            collectionId
        );

        console.log("Call data:");
        console.logBytes(callData);

        // Make the call
        (bool success, bytes memory result) = address(collectionsHandler).staticcall(callData);
        assertTrue(success, "Static call should succeed");

        console.log("Result:");
        console.logBytes(result);

        // Decode the result
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory collection = abi.decode(result, (ERC721EthscriptionsCollectionManager.CollectionMetadata));

        assertTrue(collection.collectionContract != address(0), "Should have collection contract");
        assertEq(collection.locked, false);
        ERC721EthscriptionsCollection collectionContract = ERC721EthscriptionsCollection(collection.collectionContract);
        assertEq(collectionContract.totalSupply(), 0);

        console.log("Successfully read collection state via eth_call!");
    }
}
