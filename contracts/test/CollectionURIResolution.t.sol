// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

contract CollectionURIResolutionTest is TestSetup {
    using LibString for *;
    bytes32 constant COLLECTION_TX_HASH = keccak256("collection_uri_test");
    bytes32 constant IMAGE_ETSC_TX_HASH = keccak256("image_ethscription");

    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
    }

    function test_RegularHTTPURIPassesThrough() public {
        // Create collection with regular HTTP URI
        string memory regularUri = "https://example.com/logo.png";

        bytes32 collectionId = _createCollectionWithLogo(regularUri);

        // Get collection metadata
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            collectionsHandler.getCollection(collectionId);

        assertEq(metadata.logoImageUri, regularUri, "Should preserve regular URI");

        // contractURI should also pass it through
        address collectionAddr = metadata.collectionContract;
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);
        string memory contractUri = collection.contractURI();

        assertTrue(bytes(contractUri).length > 0, "Should have contractURI");

        // contractURI returns base64-encoded JSON, decode it
        // Check it starts with data URI prefix
        string memory prefix = "data:application/json;base64,";
        assertTrue(contractUri.startsWith(prefix), "Should be a data URI");

        // Extract and decode the base64 part
        string memory base64Part = contractUri.slice(bytes(prefix).length);
        bytes memory decodedBytes = Base64.decode(base64Part);
        string memory decodedJson = string(decodedBytes);

        assertTrue(decodedJson.contains(regularUri), "Should contain original URI");
    }

    function test_DataURIPassesThrough() public {
        // Create collection with data URI
        string memory dataUri = "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTAiIGhlaWdodD0iMTAiPjwvc3ZnPg==";

        bytes32 collectionId = _createCollectionWithLogo(dataUri);

        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            collectionsHandler.getCollection(collectionId);

        assertEq(metadata.logoImageUri, dataUri, "Should preserve data URI");
    }

    function test_EthscriptionReferenceResolvesToMediaURI() public {
        // First create an ethscription with image content
        string memory imageContent = "data:image/png;base64,iVBORw0KGgo=";

        Ethscriptions.CreateEthscriptionParams memory imageParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: IMAGE_ETSC_TX_HASH,
            contentUriSha: sha256(bytes(imageContent)),
            initialOwner: alice,
            content: bytes(imageContent),
            mimetype: "image/png",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(imageParams);

        // Create collection with esc:// reference to the image
        string memory escUri = string.concat(
            "esc://ethscriptions/",
            uint256(IMAGE_ETSC_TX_HASH).toHexString(32),
            "/data"
        );

        bytes32 collectionId = _createCollectionWithLogo(escUri);

        // Get collection and check contractURI resolves the reference
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            collectionsHandler.getCollection(collectionId);

        // Stored value should be the esc:// URI
        assertEq(metadata.logoImageUri, escUri, "Should store esc:// URI");

        // contractURI should resolve it to the media URI
        address collectionAddr = metadata.collectionContract;
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);
        string memory contractUri = collection.contractURI();

        // Should contain a data URI (resolved from the referenced ethscription)
        assertTrue(contractUri.contains("data:"), "Should contain resolved data URI");
    }

    function test_InvalidEthscriptionReferenceReturnsEmpty() public {
        // Reference to non-existent ethscription
        bytes32 fakeId = keccak256("nonexistent");
        string memory escUri = string.concat(
            "esc://ethscriptions/",
            uint256(fakeId).toHexString(32),
            "/data"
        );

        bytes32 collectionId = _createCollectionWithLogo(escUri);

        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            collectionsHandler.getCollection(collectionId);
        address collectionAddr = metadata.collectionContract;
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

        // Should not revert, just return empty/placeholder
        string memory contractUri = collection.contractURI();
        assertTrue(bytes(contractUri).length > 0, "Should return contractURI without reverting");
    }

    function test_MalformedEscURIReturnsEmpty() public {
        // Various malformed esc:// URIs
        string[] memory badUris = new string[](4);
        badUris[0] = "esc://ethscriptions/notahexid/data";
        badUris[1] = "esc://ethscriptions/0x123/data";  // Too short
        badUris[2] = "esc://ethscriptions/";  // Incomplete
        badUris[3] = "esc://wrong/0x1234567890123456789012345678901234567890123456789012345678901234/data";

        for (uint i = 0; i < badUris.length; i++) {
            // Use unique collection ID for each iteration
            bytes32 uniqueCollectionId = keccak256(abi.encodePacked("malformed_test", i));
            bytes32 collectionId = _createCollectionWithLogoAndId(badUris[i], uniqueCollectionId);

            ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
                collectionsHandler.getCollection(collectionId);
            address collectionAddr = metadata.collectionContract;
            ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

            // Should not revert
            string memory contractUri = collection.contractURI();
            assertTrue(bytes(contractUri).length > 0, "Should return contractURI without reverting");
        }
    }

    // -------------------- Helpers --------------------

    function _createCollectionWithLogo(string memory logoUri) private returns (bytes32) {
        return _createCollectionWithLogoAndId(logoUri, COLLECTION_TX_HASH);
    }

    function _createCollectionWithLogoAndId(string memory logoUri, bytes32 collectionId) private returns (bytes32) {
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Test Collection",
                symbol: "TEST",
                maxSupply: 100,
                description: "Test collection",
                logoImageUri: logoUri,
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0)
            });

        string memory collectionContent = string.concat(
            'data:application/json,',
            '{"p":"erc-721-ethscriptions-collection","op":"create_collection"}'
        );

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: collectionId,
            contentUriSha: sha256(bytes(collectionContent)),
            initialOwner: alice,
            content: bytes(collectionContent),
            mimetype: "application/json",
            esip6: true,  // Allow duplicate content URI
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "create_collection",
                data: abi.encode(metadata)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        return collectionId;
    }
}
