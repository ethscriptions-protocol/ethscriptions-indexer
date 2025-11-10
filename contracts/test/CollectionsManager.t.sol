// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "../src/ERC721EthscriptionsCollectionManager.sol";
import "../src/ERC721EthscriptionsCollection.sol";
import "../src/libraries/Constants.sol";
import {LibString} from "solady/utils/LibString.sol";

contract ERC721EthscriptionsCollectionManagerTest is TestSetup {
    using LibString for *;
    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address charlie = address(0xc0ffee);

    bytes32 constant COLLECTION_TX_HASH = bytes32(uint256(0x1234));
    bytes32 constant ITEM1_TX_HASH = bytes32(uint256(0x5678));
    bytes32 constant ITEM2_TX_HASH = bytes32(uint256(0x9ABC));
    bytes32 constant ITEM3_TX_HASH = bytes32(uint256(0xDEF0));

    function setUp() public override {
        super.setUp();
    }

    function testCreateCollection() public {
        // Create a collection as Alice
        vm.prank(alice);

        string memory collectionContent = 'data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test Collection","symbol":"TEST","max_supply":"100"}';

        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Test Collection",
                symbol: "TEST",
                maxSupply: 100,
                description: "A test collection for unit tests",
                logoImageUri: "esc://ethscriptions/0x123/data",
                bannerImageUri: "esc://ethscriptions/0x456/data",
                backgroundColor: "#FF5733",
                websiteLink: "https://example.com",
                twitterLink: "https://twitter.com/test",
                discordLink: "https://discord.gg/test",
                merkleRoot: bytes32(0)
            });

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: COLLECTION_TX_HASH,
            contentUriSha: sha256(bytes(collectionContent)),
            initialOwner: alice,
            content: bytes(collectionContent),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "create_collection",
                data: abi.encode(metadata)
            })
        });

        ethscriptions.createEthscription(params);

        // Verify collection was created
        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        assertTrue(collectionAddress != address(0));

        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);
        assertEq(collection.name(), "Test Collection");
        assertEq(collection.symbol(), "TEST");
        // Collection owner is tracked through the original ethscription ownership

        // Verify metadata was stored
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory stored = collectionsHandler.getCollection(COLLECTION_TX_HASH);
        assertEq(stored.name, "Test Collection");
        assertEq(stored.symbol, "TEST");
        assertEq(stored.maxSupply, 100);
        assertEq(stored.description, "A test collection for unit tests");
        assertEq(stored.backgroundColor, "#FF5733");
    }

    function testCreateCollectionAndAddSelf() public {
        // Create ethscription that both creates a collection and adds itself as the first item
        bytes32 collectionAndItemId = bytes32(uint256(0xC0FFEE));

        // Prepare collection metadata
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Self Collection",
                symbol: "SELF",
                maxSupply: 100,
                description: "A collection where creator is first item",
                logoImageUri: "esc://ethscriptions/0x123/data",
                bannerImageUri: "esc://ethscriptions/0x456/data",
                backgroundColor: "#112233",
                websiteLink: "https://example.com",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0)
            });

        // Prepare item data
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes =
            new ERC721EthscriptionsCollectionManager.Attribute[](2);
        attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Type",
            value: "Genesis"
        });
        attributes[1] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Creator",
            value: "Alice"
        });

        // Define content for the ethscription
        bytes memory itemContent = bytes("collection and item content");
        bytes32 itemContentHash = keccak256(itemContent);

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: itemContentHash,  // keccak256 of the ethscription content
                itemIndex: 0,
                name: "Genesis Item #0",
                backgroundColor: "#445566",
                description: "The first item in this collection",
                attributes: attributes,
                merkleProof: new bytes32[](0)
            });

        ERC721EthscriptionsCollectionManager.CreateAndAddSelfParams memory params =
            ERC721EthscriptionsCollectionManager.CreateAndAddSelfParams({
                metadata: metadata,
                item: itemData
            });

        // Create the ethscription
        Ethscriptions.CreateEthscriptionParams memory ethscriptionParams =
            Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: collectionAndItemId,
                contentUriSha: sha256(itemContent),
                initialOwner: alice,
                content: itemContent,
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "erc-721-ethscriptions-collection",
                    operation: "create_collection_and_add_self",
                    data: abi.encode(params)
                })
            });

        vm.prank(alice);
        ethscriptions.createEthscription(ethscriptionParams);

        // Verify collection was created
        address collectionAddress = collectionsHandler.getCollectionAddress(collectionAndItemId);
        assertTrue(collectionAddress != address(0), "Collection should be created");

        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);
        assertEq(collection.name(), "Self Collection");
        assertEq(collection.symbol(), "SELF");

        // Verify item was added as token ID 0
        assertEq(collection.ownerOf(0), alice);

        // Verify item metadata
        ERC721EthscriptionsCollectionManager.CollectionItem memory item =
            collectionsHandler.getCollectionItem(collectionAndItemId, 0);
        assertEq(item.name, "Genesis Item #0");
        assertEq(item.description, "The first item in this collection");
        assertEq(item.backgroundColor, "#445566");
        assertEq(item.attributes.length, 2);
        assertEq(item.attributes[0].traitType, "Type");
        assertEq(item.attributes[0].value, "Genesis");
    }

    function testAddToCollection() public {
        // First create a collection
        testCreateCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Create an ethscription that adds itself to the collection at creation time
        string memory itemContent = 'data:,{"p":"erc-721-ethscriptions-collection","op":"add_self","collection":"0x1234","item":"artwork1"}';
        bytes32 itemContentHash = keccak256(bytes(itemContent));

        // Create item data with attributes
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes = new ERC721EthscriptionsCollectionManager.Attribute[](3);
        attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Type",
            value: "Artwork"
        });
        attributes[1] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Rarity",
            value: "Common"
        });
        attributes[2] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Color",
            value: "Blue"
        });

        ERC721EthscriptionsCollectionManager.ItemData memory itemData = ERC721EthscriptionsCollectionManager.ItemData({
            contentHash: itemContentHash,  // keccak256 of the ethscription content
            itemIndex: 0,
            name: "Test Item #0",
            backgroundColor: "#0000FF",
            description: "First test item",
            attributes: attributes,
            merkleProof: new bytes32[](0)
        });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        // Create the ethscription with protocol set to add itself to the collection
        Ethscriptions.CreateEthscriptionParams memory itemParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(bytes(itemContent)),
            initialOwner: alice,
            content: bytes(itemContent),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(itemParams);

        // Verify item was added with metadata
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Test Item #0");
        assertEq(item.ethscriptionId, ITEM1_TX_HASH);
        assertEq(item.backgroundColor, "#0000FF");
        assertEq(item.description, "First test item");
        assertEq(item.attributes.length, 3);
        assertEq(item.attributes[0].traitType, "Type");
        assertEq(item.attributes[0].value, "Artwork");
        assertEq(item.attributes[1].traitType, "Rarity");
        assertEq(item.attributes[1].value, "Common");
        assertEq(item.attributes[2].traitType, "Color");
        assertEq(item.attributes[2].value, "Blue");

        // Verify item was added to collection
        // Token ID is the item index (0 for the first item)
        uint256 tokenId = 0;
        assertEq(collection.ownerOf(tokenId), alice);
        // Verify item is in collection via ERC721EthscriptionsCollectionManager
        ERC721EthscriptionsCollectionManager.CollectionItem memory item2 = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, tokenId);
        assertEq(item2.ethscriptionId, ITEM1_TX_HASH);
    }

    function testTransferCollectionItem() public {
        // Setup: Create collection and add item
        testAddToCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Transfer the ethscription NFT
        vm.prank(alice);
        ethscriptions.transferEthscription(bob, ITEM1_TX_HASH);

        // Verify ownership synced in collection
        // Token ID is the item index (0 for the first item)
        uint256 tokenId = 0;
        assertEq(collection.ownerOf(tokenId), bob);
    }

    function testBurnCollectionItem() public {
        // Setup: Create collection and add item
        testAddToCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        uint256 tokenId = collectionsHandler.getEthscriptionTokenId(ITEM1_TX_HASH);

        // Burn the ethscription (transfer to address(0))
        vm.prank(alice);
        ethscriptions.transferEthscription(address(0), ITEM1_TX_HASH);

        // Verify item is still in collection but owned by address(0)
        // Token ID is the item index (0 for the first item)
        assertEq(collection.ownerOf(tokenId), address(0));
    }

    function testRemoveFromCollection() public {
        // Setup: Create collection and add item
        testAddToCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Remove item from collection (only collection owner can do this)
        vm.prank(alice);

        string memory removeContent = 'data:,{"p":"erc-721-ethscriptions-collection","op":"remove","collection":"0x1234","item":"0x5678"}';

        bytes32[] memory itemsToRemove = new bytes32[](1);
        itemsToRemove[0] = ITEM1_TX_HASH;

        ERC721EthscriptionsCollectionManager.RemoveItemsOperation memory removeOp = ERC721EthscriptionsCollectionManager.RemoveItemsOperation({
            collectionId: COLLECTION_TX_HASH,
            ethscriptionIds: itemsToRemove
        });

        Ethscriptions.CreateEthscriptionParams memory removeParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0xFEED)),
            contentUriSha: sha256(bytes(removeContent)),
            initialOwner: alice,
            content: bytes(removeContent),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "remove_items",
                data: abi.encode(removeOp)
            })
        });

        // Check token exists before removal
        uint256 tokenId = 0;
        address ownerBefore = collection.ownerOf(tokenId);
        assertEq(ownerBefore, alice, "Should own token before removal");

        vm.prank(alice);
        ethscriptions.createEthscription(removeParams);

        // Check membership was removed from manager
        (bytes32 collId, uint256 tokenIdPlusOne) = collectionsHandler.membershipOfEthscription(ITEM1_TX_HASH);
        assertEq(collId, bytes32(0), "Collection ID should be zero after removal");
        assertEq(tokenIdPlusOne, 0, "Token ID plus one should be zero after removal");

        // Verify item was removed - token should no longer exist
        // This should revert with ERC721NonexistentToken
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", tokenId));
        collection.ownerOf(tokenId);
    }

    function testOnlyOwnerCanRemove() public {
        // Setup: Create collection and add item
        testAddToCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Try to remove item as non-owner (should fail silently)
        vm.prank(bob);

        bytes32[] memory itemsToRemove = new bytes32[](1);
        itemsToRemove[0] = ITEM1_TX_HASH;

        ERC721EthscriptionsCollectionManager.RemoveItemsOperation memory removeOp = ERC721EthscriptionsCollectionManager.RemoveItemsOperation({
            collectionId: COLLECTION_TX_HASH,
            ethscriptionIds: itemsToRemove
        });

        Ethscriptions.CreateEthscriptionParams memory removeParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0xBAD)),
            contentUriSha: sha256(bytes("data:,remove")),
            initialOwner: bob,
            content: bytes("remove"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "remove_items",
                data: abi.encode(removeOp)
            })
        });

        vm.prank(bob);
        ethscriptions.createEthscription(removeParams);

        // Verify item is still in collection (remove failed)
        // Token ID is the item index (0 for the first item)
        uint256 tokenId = 0;
        assertEq(collection.ownerOf(tokenId), alice);
    }

    function testMultipleItemsInCollection() public {
        // Create collection
        testCreateCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Add multiple items (each adds itself at creation time)
        bytes32[3] memory itemHashes = [ITEM1_TX_HASH, ITEM2_TX_HASH, ITEM3_TX_HASH];
        address[3] memory owners = [alice, bob, charlie];

        for (uint i = 0; i < 3; i++) {
            // Create item data for self-add
            ERC721EthscriptionsCollectionManager.Attribute[] memory attributes = new ERC721EthscriptionsCollectionManager.Attribute[](1);
            attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({
                traitType: "Type",
                value: "Test"
            });

            string memory itemName = i == 0 ? "Item #0" : i == 1 ? "Item #1" : "Item #2";
            bytes32 itemContentHash = keccak256(abi.encodePacked("item", i));

            ERC721EthscriptionsCollectionManager.ItemData memory itemData = ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: itemContentHash,
                itemIndex: uint256(i),
                name: itemName,
                backgroundColor: "#000000",
                description: "Test item",
                attributes: attributes,
                merkleProof: new bytes32[](0)
            });

            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
                ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                    collectionId: COLLECTION_TX_HASH,
                    item: itemData
                });

            // Create ethscription that adds itself to the collection
            Ethscriptions.CreateEthscriptionParams memory itemParams = Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: itemHashes[i],
                contentUriSha: sha256(abi.encodePacked("item", i)),
                initialOwner: owners[i],
                content: abi.encodePacked("item", i),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "erc-721-ethscriptions-collection",
                    operation: "add_self_to_collection",
                    data: abi.encode(addSelfParams)
                })
            });

            vm.prank(alice);
            ethscriptions.createEthscription(itemParams);
        }

        // Verify all items are in collection with correct owners
        for (uint i = 0; i < 3; i++) {
            uint256 tokenId = uint256(i); // Token ID matches the item index
            assertEq(collection.ownerOf(tokenId), owners[i]);
        }

        // Collection has 3 items
    }

    function testTokenURIGeneration() public {
        // First create a collection with metadata
        testCreateCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Create an ethscription with image content to add
        vm.prank(alice);

        string memory imageContent = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
        bytes32 imageContentHash = keccak256(bytes(imageContent));

        // Create item data with attributes
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes = new ERC721EthscriptionsCollectionManager.Attribute[](4);
        attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Type",
            value: "Female"
        });
        attributes[1] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Hair",
            value: "Blonde Bob"
        });
        attributes[2] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Eyes",
            value: "Green Eye Shadow"
        });
        attributes[3] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Rarity",
            value: "Rare"
        });

        ERC721EthscriptionsCollectionManager.ItemData memory itemData = ERC721EthscriptionsCollectionManager.ItemData({
            contentHash: imageContentHash,
            itemIndex: 0,
            name: "Ittybit #0000",
            backgroundColor: "#648595",
            description: "A rare ittybit with green eye shadow",
            attributes: attributes,
            merkleProof: new bytes32[](0)
        });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        // Create the ethscription with image content
        Ethscriptions.CreateEthscriptionParams memory itemParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(bytes(imageContent)),
            initialOwner: alice,
            content: bytes(imageContent),
            mimetype: "image/png",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(itemParams);

        // Get the token URI and verify it contains the expected data
        // Get tokenId from ERC721EthscriptionsCollectionManager (it should be 0)
        uint256 tokenId = 0;
        string memory tokenUri = collection.tokenURI(tokenId);

        // The URI should be a base64-encoded JSON data URI
        assertTrue(bytes(tokenUri).length > 0);
        // Should start with data:application/json;base64,
        assertTrue(LibString.startsWith(tokenUri, "data:application/json;base64,"));

        // Verify the item metadata was stored correctly
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Ittybit #0000");
        assertEq(item.backgroundColor, "#648595");
        assertEq(item.attributes.length, 4);
        assertEq(item.attributes[1].traitType, "Hair");
        assertEq(item.attributes[1].value, "Blonde Bob");
    }

    function testCollectionAddressIsPredictable() public {
        // Predict the collection address before deployment
        address predictedAddress = collectionsHandler.predictCollectionAddress(COLLECTION_TX_HASH);

        // Create the collection
        testCreateCollection();

        // Verify the actual address matches prediction
        address actualAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        assertEq(actualAddress, predictedAddress);
    }

    function testEditCollectionItem() public {
        // Setup: Create collection and add item
        testAddToCollection();

        // Edit item 0 - update name, description, and attributes
        vm.prank(alice);

        ERC721EthscriptionsCollectionManager.Attribute[] memory newAttributes = new ERC721EthscriptionsCollectionManager.Attribute[](3);
        newAttributes[0] = ERC721EthscriptionsCollectionManager.Attribute({traitType: "Color", value: "Blue"});
        newAttributes[1] = ERC721EthscriptionsCollectionManager.Attribute({traitType: "Size", value: "Large"});
        newAttributes[2] = ERC721EthscriptionsCollectionManager.Attribute({traitType: "Rarity", value: "Epic"});

        ERC721EthscriptionsCollectionManager.EditCollectionItemOperation memory editOp = ERC721EthscriptionsCollectionManager.EditCollectionItemOperation({
            collectionId: COLLECTION_TX_HASH,
            itemIndex: 0,
            name: "Updated Item Name",
            backgroundColor: "#0000FF",
            description: "This item has been updated",
            attributes: newAttributes
        });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0xED171)),
            contentUriSha: sha256(bytes("edit")),
            initialOwner: alice,
            content: bytes("edit"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection_item",
                data: abi.encode(editOp)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(editParams);

        // Verify item was updated
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Updated Item Name");
        assertEq(item.backgroundColor, "#0000FF");
        assertEq(item.description, "This item has been updated");
        assertEq(item.attributes.length, 3);
        assertEq(item.attributes[0].traitType, "Color");
        assertEq(item.attributes[0].value, "Blue");
        assertEq(item.attributes[1].traitType, "Size");
        assertEq(item.attributes[1].value, "Large");
        assertEq(item.attributes[2].traitType, "Rarity");
        assertEq(item.attributes[2].value, "Epic");
    }

    function testEditCollectionItemPartialUpdate() public {
        // Setup: Create collection and add item with attributes
        testCreateCollection();

        // Create ethscription that adds itself to the collection with attributes
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes = new ERC721EthscriptionsCollectionManager.Attribute[](2);
        attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({traitType: "Hair Color", value: "Brown"});
        attributes[1] = ERC721EthscriptionsCollectionManager.Attribute({traitType: "Hair", value: "Blonde Bob"});

        bytes32 itemContentHash = keccak256(bytes("item content"));

        ERC721EthscriptionsCollectionManager.ItemData memory itemData = ERC721EthscriptionsCollectionManager.ItemData({
            contentHash: itemContentHash,
            itemIndex: 0,
            name: "Test Item #0",
            backgroundColor: "#FF5733",
            description: "First item description",
            attributes: attributes,
            merkleProof: new bytes32[](0)
        });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory itemParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(bytes("item content")),
            initialOwner: alice,
            content: bytes("item content"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(itemParams);

        // Edit item 0 - only update name and description, keep existing attributes
        vm.prank(alice);

        ERC721EthscriptionsCollectionManager.EditCollectionItemOperation memory editOp = ERC721EthscriptionsCollectionManager.EditCollectionItemOperation({
            collectionId: COLLECTION_TX_HASH,
            itemIndex: 0,
            name: "Partially Updated",
            backgroundColor: "", // Empty string - don't update
            description: "Only name and description changed",
            attributes: new ERC721EthscriptionsCollectionManager.Attribute[](0) // Empty array - keep existing
        });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0xED172)),
            contentUriSha: sha256(bytes("partial-edit")),
            initialOwner: alice,
            content: bytes("partial-edit"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection_item",
                data: abi.encode(editOp)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(editParams);

        // Verify partial update
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Partially Updated");
        assertEq(item.description, "Only name and description changed");
        assertEq(item.backgroundColor, "#FF5733"); // Original value preserved
        assertEq(item.attributes.length, 2); // Original attributes preserved
        assertEq(item.attributes[0].traitType, "Hair Color");
        assertEq(item.attributes[0].value, "Brown");
    }

    function testOnlyOwnerCanEditItem() public {
        // Setup: Create collection and add item
        testAddToCollection();

        // Try to edit item as non-owner (should revert)
        vm.prank(bob);

        ERC721EthscriptionsCollectionManager.EditCollectionItemOperation memory editOp = ERC721EthscriptionsCollectionManager.EditCollectionItemOperation({
            collectionId: COLLECTION_TX_HASH,
            itemIndex: 0,
            name: "Unauthorized Edit",
            backgroundColor: "#000000",
            description: "This should not work",
            attributes: new ERC721EthscriptionsCollectionManager.Attribute[](0)
        });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0xBADED17)),
            contentUriSha: sha256(bytes("bad-edit")),
            initialOwner: bob,
            content: bytes("bad-edit"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection_item",
                data: abi.encode(editOp)
            })
        });

        vm.prank(bob);
        ethscriptions.createEthscription(editParams);

        // Verify item was not changed
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Test Item #0"); // Original name preserved
    }

    function testEditNonExistentItem() public {
        // Setup: Create collection
        testCreateCollection();

        // Try to edit non-existent item (should revert)
        vm.prank(alice);

        ERC721EthscriptionsCollectionManager.EditCollectionItemOperation memory editOp = ERC721EthscriptionsCollectionManager.EditCollectionItemOperation({
            collectionId: COLLECTION_TX_HASH,
            itemIndex: 999, // Non-existent index
            name: "Should Fail",
            backgroundColor: "#000000",
            description: "This item doesn't exist",
            attributes: new ERC721EthscriptionsCollectionManager.Attribute[](0)
        });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x901743)),
            contentUriSha: sha256(bytes("no-item")),
            initialOwner: alice,
            content: bytes("no-item"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection_item",
                data: abi.encode(editOp)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(editParams);

        // The operation should fail silently (no revert in createEthscription)
        // Verify by checking that getting the item returns default values
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 999);
        assertEq(item.ethscriptionId, bytes32(0)); // Default value for non-existent item
    }

    function testSyncOwnership() public {
        // Setup: Create collection and add items
        testAddToCollection();

        // Get the collection contract
        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Initially Alice owns the token
        assertEq(collection.ownerOf(0), alice);

        // Now transfer the underlying ethscription to Bob (simulating a transfer outside the ERC721)
        // We need to mock this transfer in the Ethscriptions contract
        vm.prank(alice);
        ethscriptions.transferEthscription(bob, ITEM1_TX_HASH);

        // Verify the ethscription is now owned by Bob
        // Note: ERC721's ownerOf always returns the current ethscription owner
        assertEq(ethscriptions.ownerOf(ITEM1_TX_HASH), bob);
        assertEq(collection.ownerOf(0), bob); // Immediately reflects the new owner

        // Now sync the ownership
        vm.prank(charlie); // Anyone can trigger sync
        bytes32[] memory ethscriptionIds = new bytes32[](1);
        ethscriptionIds[0] = ITEM1_TX_HASH;

        Ethscriptions.CreateEthscriptionParams memory syncParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x5914C)),
            contentUriSha: sha256(bytes("sync")),
            initialOwner: charlie,
            content: bytes("sync"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "sync_ownership",
                data: abi.encode(COLLECTION_TX_HASH, ethscriptionIds)
            })
        });

        vm.prank(charlie);
        ethscriptions.createEthscription(syncParams);

        // Verify the ERC721 ownership is now synced
        assertEq(collection.ownerOf(0), bob);
    }

    function testSyncOwnershipMultipleItems() public {
        // Setup: Create collection with multiple items
        testMultipleItemsInCollection();

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        // Transfer multiple ethscriptions to different owners
        vm.prank(alice);
        ethscriptions.transferEthscription(charlie, ITEM1_TX_HASH);

        vm.prank(bob);
        ethscriptions.transferEthscription(alice, ITEM2_TX_HASH);

        // Verify ethscriptions have new owners
        assertEq(ethscriptions.ownerOf(ITEM1_TX_HASH), charlie);
        assertEq(ethscriptions.ownerOf(ITEM2_TX_HASH), alice);

        // Ownership should sync automatically via onTransfer callback
        // since these ethscriptions have the collection protocol set
        assertEq(collection.ownerOf(0), charlie); // Should be synced automatically
        assertEq(collection.ownerOf(1), alice);   // Should be synced automatically
    }

    function testSyncOwnershipNonExistentItem() public {
        // Setup: Create collection
        testCreateCollection();

        // Try to sync an ethscription that's not in the collection
        bytes32[] memory ethscriptionIds = new bytes32[](1);
        ethscriptionIds[0] = bytes32(uint256(0x999999)); // Non-existent in collection

        Ethscriptions.CreateEthscriptionParams memory syncParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x5914CE)),
            contentUriSha: sha256(bytes("sync-nonexistent")),
            initialOwner: alice,
            content: bytes("sync-nonexistent"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "sync_ownership",
                data: abi.encode(COLLECTION_TX_HASH, ethscriptionIds)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(syncParams);

        // Should complete without error (non-existent items are skipped)
        // No assertion needed - just verifying no revert
    }

    function testSyncOwnershipNonExistentCollection() public {
        bytes32 fakeCollectionId = bytes32(uint256(0xFABE));
        bytes32[] memory ethscriptionIds = new bytes32[](1);
        ethscriptionIds[0] = ITEM1_TX_HASH;

        Ethscriptions.CreateEthscriptionParams memory syncParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x5914CF)),
            contentUriSha: sha256(bytes("sync-fake")),
            initialOwner: alice,
            content: bytes("sync-fake"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "sync_ownership",
                data: abi.encode(fakeCollectionId, ethscriptionIds)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(syncParams);

        // The operation should fail silently (protocol handler catches the require)
        // No assertion needed - just verifying completion
    }

    function testEditLockedCollection() public {
        // Setup: Create collection and add item
        testAddToCollection();

        // Lock the collection
        vm.prank(alice);

        Ethscriptions.CreateEthscriptionParams memory lockParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x10CCC)),
            contentUriSha: sha256(bytes("lock")),
            initialOwner: alice,
            content: bytes("lock"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "lock_collection",
                data: abi.encode(COLLECTION_TX_HASH)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(lockParams);

        // Try to edit item in locked collection (should fail)
        vm.prank(alice);

        ERC721EthscriptionsCollectionManager.EditCollectionItemOperation memory editOp = ERC721EthscriptionsCollectionManager.EditCollectionItemOperation({
            collectionId: COLLECTION_TX_HASH,
            itemIndex: 0,
            name: "Should not update",
            backgroundColor: "#000000",
            description: "Collection is locked",
            attributes: new ERC721EthscriptionsCollectionManager.Attribute[](0)
        });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: bytes32(uint256(0x10C3ED)),
            contentUriSha: sha256(bytes("locked-edit")),
            initialOwner: alice,
            content: bytes("locked-edit"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection_item",
                data: abi.encode(editOp)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(editParams);

        // Verify item was not changed
        ERC721EthscriptionsCollectionManager.CollectionItem memory item = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(item.name, "Test Item #0"); // Original name preserved
    }

    function testNonOwnerCanAddItemWithValidMerkleProof() public {
        _exitImportMode();
        bytes memory allowlistedContent = bytes("allowlisted-item");
        bytes memory siblingContent = bytes("sibling-item");

        ERC721EthscriptionsCollectionManager.Attribute[] memory allowlistedAttributes =
            _attributeArray("Tier", "Founder");
        ERC721EthscriptionsCollectionManager.Attribute[] memory siblingAttributes =
            _attributeArray("Tier", "Guest");

        bytes32 allowlistedLeaf = _computeLeafHash(
            keccak256(allowlistedContent),
            0,
            "Allowlisted Item",
            "#111111",
            "Reserved for the allowlist",
            allowlistedAttributes
        );
        bytes32 siblingLeaf = _computeLeafHash(
            keccak256(siblingContent),
            1,
            "Sibling Item",
            "#222222",
            "Another whitelisted entry",
            siblingAttributes
        );

        bytes32 merkleRoot = _hashPair(allowlistedLeaf, siblingLeaf);
        _createCollectionWithMerkleRoot(COLLECTION_TX_HASH, merkleRoot);

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: keccak256(allowlistedContent),
                itemIndex: 0,
                name: "Allowlisted Item",
                backgroundColor: "#111111",
                description: "Reserved for the allowlist",
                attributes: allowlistedAttributes,
                merkleProof: _singleProofArray(siblingLeaf)
            });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory addParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(allowlistedContent),
            initialOwner: bob,
            content: allowlistedContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(bob);
        ethscriptions.createEthscription(addParams);

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        assertTrue(collectionAddress != address(0));
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);

        assertEq(collection.ownerOf(0), bob);
        ERC721EthscriptionsCollectionManager.CollectionItem memory stored = collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(stored.ethscriptionId, ITEM1_TX_HASH);
        assertEq(stored.name, "Allowlisted Item");
    }

    function testNonOwnerCannotAddItemWithoutMerkleRoot() public {
        _exitImportMode();
        _createCollectionWithMerkleRoot(COLLECTION_TX_HASH, bytes32(0));

        bytes memory allowlistedContent = bytes("allowlisted-item");
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes =
            _attributeArray("Tier", "Founder");

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: keccak256(allowlistedContent),
                itemIndex: 0,
                name: "Allowlisted Item",
                backgroundColor: "#111111",
                description: "Reserved for the allowlist",
                attributes: attributes,
                merkleProof: new bytes32[](0)
            });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory addParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(allowlistedContent),
            initialOwner: bob,
            content: allowlistedContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.recordLogs();
        vm.prank(bob);
        ethscriptions.createEthscription(addParams);

        _assertProtocolFailure(ITEM1_TX_HASH, "Merkle proof required");

        ERC721EthscriptionsCollectionManager.CollectionItem memory stored =
            collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(stored.ethscriptionId, bytes32(0));

        ERC721EthscriptionsCollectionManager.Membership memory membership =
            collectionsHandler.getMembershipOfEthscription(ITEM1_TX_HASH);
        assertEq(membership.collectionId, bytes32(0));
    }

    function testNonOwnerCannotAddItemWithInvalidMerkleProof() public {
        _exitImportMode();
        bytes memory allowlistedContent = bytes("allowlisted-item");
        bytes memory siblingContent = bytes("sibling-item");

        ERC721EthscriptionsCollectionManager.Attribute[] memory allowlistedAttributes =
            _attributeArray("Tier", "Founder");
        ERC721EthscriptionsCollectionManager.Attribute[] memory siblingAttributes =
            _attributeArray("Tier", "Guest");

        bytes32 allowlistedLeaf = _computeLeafHash(
            keccak256(allowlistedContent),
            0,
            "Allowlisted Item",
            "#111111",
            "Reserved for the allowlist",
            allowlistedAttributes
        );
        bytes32 siblingLeaf = _computeLeafHash(
            keccak256(siblingContent),
            1,
            "Sibling Item",
            "#222222",
            "Another whitelisted entry",
            siblingAttributes
        );

        bytes32 merkleRoot = _hashPair(allowlistedLeaf, siblingLeaf);
        _createCollectionWithMerkleRoot(COLLECTION_TX_HASH, merkleRoot);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(0xdeadbeef));

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: keccak256(allowlistedContent),
                itemIndex: 0,
                name: "Allowlisted Item",
                backgroundColor: "#111111",
                description: "Reserved for the allowlist",
                attributes: allowlistedAttributes,
                merkleProof: invalidProof
            });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory addParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(allowlistedContent),
            initialOwner: bob,
            content: allowlistedContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.recordLogs();
        vm.prank(bob);
        ethscriptions.createEthscription(addParams);

        _assertProtocolFailure(ITEM1_TX_HASH, "Invalid Merkle proof");

        ERC721EthscriptionsCollectionManager.CollectionItem memory stored =
            collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(stored.ethscriptionId, bytes32(0));

        ERC721EthscriptionsCollectionManager.Membership memory membership =
            collectionsHandler.getMembershipOfEthscription(ITEM1_TX_HASH);
        assertEq(membership.collectionId, bytes32(0));
    }

    function testCollectionOwnerBypassesMerkleProof() public {
        _exitImportMode();
        bytes32 enforcedRoot = keccak256("allowlist-root");
        _createCollectionWithMerkleRoot(COLLECTION_TX_HASH, enforcedRoot);

        bytes memory itemContent = bytes("owner-merkle-item");
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes = _attributeArray("Tier", "Owner");

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: keccak256(itemContent),
                itemIndex: 0,
                name: "Owner Item",
                backgroundColor: "#010101",
                description: "Owner should bypass proof enforcement",
                attributes: attributes,
                merkleProof: new bytes32[](0)
            });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory addParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(itemContent),
            initialOwner: alice,
            content: itemContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(addParams);

        address collectionAddress = collectionsHandler.getCollectionAddress(COLLECTION_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddress);
        assertEq(collection.ownerOf(0), alice);

        ERC721EthscriptionsCollectionManager.CollectionItem memory stored =
            collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(stored.ethscriptionId, ITEM1_TX_HASH);
    }

    function testEditingMerkleRootChangesNonOwnerAccess() public {
        _exitImportMode();

        bytes memory allowlistedContent = bytes("allowlisted-item");
        bytes memory siblingContent = bytes("sibling-item");

        ERC721EthscriptionsCollectionManager.Attribute[] memory allowlistedAttributes =
            _attributeArray("Tier", "Founder");
        ERC721EthscriptionsCollectionManager.Attribute[] memory siblingAttributes =
            _attributeArray("Tier", "Guest");

        bytes32 allowlistedLeaf = _computeLeafHash(
            keccak256(allowlistedContent),
            0,
            "Allowlisted Item",
            "#111111",
            "Reserved for the allowlist",
            allowlistedAttributes
        );
        bytes32 siblingLeaf = _computeLeafHash(
            keccak256(siblingContent),
            1,
            "Sibling Item",
            "#222222",
            "Another whitelisted entry",
            siblingAttributes
        );

        bytes32 merkleRoot = _hashPair(allowlistedLeaf, siblingLeaf);
        _createCollectionWithMerkleRoot(COLLECTION_TX_HASH, bytes32(0));

        ERC721EthscriptionsCollectionManager.ItemData memory itemData =
            ERC721EthscriptionsCollectionManager.ItemData({
                contentHash: keccak256(allowlistedContent),
                itemIndex: 0,
                name: "Allowlisted Item",
                backgroundColor: "#111111",
                description: "Reserved for the allowlist",
                attributes: allowlistedAttributes,
                merkleProof: _singleProofArray(siblingLeaf)
            });

        ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams memory addSelfParams =
            ERC721EthscriptionsCollectionManager.AddSelfToCollectionParams({
                collectionId: COLLECTION_TX_HASH,
                item: itemData
            });

        Ethscriptions.CreateEthscriptionParams memory firstAttempt = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM1_TX_HASH,
            contentUriSha: sha256(allowlistedContent),
            initialOwner: bob,
            content: allowlistedContent,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.recordLogs();
        vm.prank(bob);
        ethscriptions.createEthscription(firstAttempt);
        _assertProtocolFailure(ITEM1_TX_HASH, "Merkle proof required");

        ERC721EthscriptionsCollectionManager.CollectionItem memory emptySlot =
            collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(emptySlot.ethscriptionId, bytes32(0));

        _editCollectionMerkleRoot(bytes32(uint256(0xED111)), COLLECTION_TX_HASH, merkleRoot);

        Ethscriptions.CreateEthscriptionParams memory secondAttempt = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: ITEM2_TX_HASH,
            contentUriSha: sha256(allowlistedContent),
            initialOwner: bob,
            content: allowlistedContent,
            mimetype: "text/plain",
            esip6: true,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "add_self_to_collection",
                data: abi.encode(addSelfParams)
            })
        });

        vm.prank(bob);
        ethscriptions.createEthscription(secondAttempt);

        ERC721EthscriptionsCollectionManager.CollectionItem memory stored =
            collectionsHandler.getCollectionItem(COLLECTION_TX_HASH, 0);
        assertEq(stored.ethscriptionId, ITEM2_TX_HASH);

        ERC721EthscriptionsCollectionManager.Membership memory membership =
            collectionsHandler.getMembershipOfEthscription(ITEM2_TX_HASH);
        assertEq(membership.collectionId, COLLECTION_TX_HASH);
        assertEq(membership.tokenIdPlusOne, 1);

        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            collectionsHandler.getCollection(COLLECTION_TX_HASH);
        assertEq(metadata.merkleRoot, merkleRoot);
    }

    function _createCollectionWithMerkleRoot(bytes32 collectionId, bytes32 merkleRoot) private {
        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "Merkle Collection",
                symbol: "MRKL",
                maxSupply: 100,
                description: "Collection that requires proofs",
                logoImageUri: "",
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: merkleRoot
            });

        string memory collectionContent =
            'data:,{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Merkle Collection"}';

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: collectionId,
            contentUriSha: sha256(bytes(collectionContent)),
            initialOwner: alice,
            content: bytes(collectionContent),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "create_collection",
                data: abi.encode(metadata)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(params);
    }

    function _attributeArray(string memory trait, string memory value)
        private
        pure
        returns (ERC721EthscriptionsCollectionManager.Attribute[] memory attrs)
    {
        attrs = new ERC721EthscriptionsCollectionManager.Attribute[](1);
        attrs[0] = ERC721EthscriptionsCollectionManager.Attribute({traitType: trait, value: value});
    }

    function _computeLeafHash(
        bytes32 contentHash,
        uint256 itemIndex,
        string memory name,
        string memory backgroundColor,
        string memory description,
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(contentHash, itemIndex, name, backgroundColor, description, attributes));
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _singleProofArray(bytes32 sibling) private pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = sibling;
    }

    function _assertProtocolFailure(bytes32 ethscriptionId, string memory expectedMessage) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 failureTopic = keccak256("ProtocolHandlerFailed(bytes32,string,bytes)");
        bool found;
        string memory protocol;
        bytes memory revertData;

        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory entry = logs[i];
            if (entry.topics.length >= 2 && entry.topics[0] == failureTopic && entry.topics[1] == ethscriptionId) {
                (protocol, revertData) = abi.decode(entry.data, (string, bytes));
                found = true;
                break;
            }
        }

        assertTrue(found, "Expected ProtocolHandlerFailed event");
        assertEq(protocol, "erc-721-ethscriptions-collection");

        bytes memory expected = abi.encodeWithSignature("Error(string)", expectedMessage);
        assertEq(keccak256(revertData), keccak256(expected));
    }

    function _exitImportMode() private {
        vm.warp(Constants.historicalBackfillApproxDoneAt + 1);
    }

    function _editCollectionMerkleRoot(bytes32 editEthscriptionId, bytes32 collectionId, bytes32 newRoot) private {
        ERC721EthscriptionsCollectionManager.EditCollectionOperation memory editOp =
            ERC721EthscriptionsCollectionManager.EditCollectionOperation({
                collectionId: collectionId,
                description: "",
                logoImageUri: "",
                bannerImageUri: "",
                backgroundColor: "",
                websiteLink: "",
                twitterLink: "",
                discordLink: "",
                merkleRoot: newRoot
            });

        Ethscriptions.CreateEthscriptionParams memory editParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: editEthscriptionId,
            contentUriSha: sha256(bytes("edit-merkle")),
            initialOwner: alice,
            content: bytes("edit-merkle"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "edit_collection",
                data: abi.encode(editOp)
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(editParams);
    }
}
