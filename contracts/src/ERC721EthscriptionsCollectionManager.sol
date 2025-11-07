// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./ERC721EthscriptionsCollection.sol";
import "./libraries/Proxy.sol";
import "./libraries/DedupedBlobStore.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import "./interfaces/IProtocolHandler.sol";

contract ERC721EthscriptionsCollectionManager is IProtocolHandler {
    using LibString for *;

    struct Attribute {
        string traitType;
        string value;
    }

    struct CollectionParams {
        string name;
        string symbol;
        uint256 maxSupply;
        string description;
        string logoImageUri;
        string bannerImageUri;
        string backgroundColor;
        string websiteLink;
        string twitterLink;
        string discordLink;
        bytes32 merkleRoot;
    }

    struct CollectionRecord {
        address collectionContract;
        bool locked;
        bytes32 nameRef;                // DedupedBlobStore reference
        bytes32 symbolRef;              // DedupedBlobStore reference
        uint256 maxSupply;
        bytes32 descriptionRef;         // DedupedBlobStore reference
        bytes32 logoImageRef;           // DedupedBlobStore reference
        bytes32 bannerImageRef;         // DedupedBlobStore reference
        bytes32 backgroundColorRef;     // DedupedBlobStore reference
        bytes32 websiteLinkRef;         // DedupedBlobStore reference
        bytes32 twitterLinkRef;         // DedupedBlobStore reference
        bytes32 discordLinkRef;         // DedupedBlobStore reference
        bytes32 merkleRoot;
    }

    /// @notice View struct for external consumption with decoded strings
    struct CollectionMetadata {
        address collectionContract;
        bool locked;
        string name;
        string symbol;
        uint256 maxSupply;
        string description;
        string logoImageUri;
        string bannerImageUri;
        string backgroundColor;
        string websiteLink;
        string twitterLink;
        string discordLink;
        bytes32 merkleRoot;
    }

    struct CollectionItem {
        uint256 itemIndex;
        string name;
        bytes32 ethscriptionId;
        string backgroundColor;
        string description;
        Attribute[] attributes;
    }

    struct ItemData {
        uint256 itemIndex;
        string name;
        string backgroundColor;
        string description;
        Attribute[] attributes;
        bytes32[] merkleProof;
    }

    struct Membership {
        bytes32 collectionId;
        uint256 tokenIdPlusOne; // 0 means not a member
    }

    struct RemoveItemsOperation {
        bytes32 collectionId;
        bytes32[] ethscriptionIds;
    }

    struct EditCollectionOperation {
        bytes32 collectionId;
        string description;
        string logoImageUri;
        string bannerImageUri;
        string backgroundColor;
        string websiteLink;
        string twitterLink;
        string discordLink;
        bytes32 merkleRoot;
    }

    struct EditCollectionItemOperation {
        bytes32 collectionId;
        uint256 itemIndex;
        string name;
        string backgroundColor;
        string description;
        Attribute[] attributes;
    }

    struct CreateAndAddSelfParams {
        CollectionParams metadata;
        ItemData item;
    }

    struct AddSelfToCollectionParams {
        bytes32 collectionId;
        ItemData item;
    }

    address public constant collectionsImplementation = Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_IMPLEMENTATION;
    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);
    string public constant protocolName = "erc-721-ethscriptions-collection";

    mapping(bytes32 => CollectionRecord) internal collectionStore;
    mapping(bytes32 => mapping(uint256 => CollectionItem)) internal collectionItems;
    mapping(bytes32 => Membership) public membershipOfEthscription;
    mapping(address => bytes32) internal collectionAddressToId;

    /// @dev Deduplicated storage for collection string fields (name, description, URIs, etc.)
    mapping(bytes32 => bytes32) internal collectionBlobStorage;

    bytes32[] public collectionIds;

    event CollectionCreated(
        bytes32 indexed collectionId,
        address indexed collectionContract,
        string name,
        string symbol,
        uint256 maxSupply
    );

    event ItemsAdded(bytes32 indexed collectionId, uint256 count, bytes32 updateTxHash);
    event ItemsRemoved(bytes32 indexed collectionId, uint256 count, bytes32 updateTxHash);
    event CollectionEdited(bytes32 indexed collectionId);
    event CollectionLocked(bytes32 indexed collectionId);

    modifier onlyEthscriptions() {
        require(msg.sender == address(ethscriptions), "Only Ethscriptions contract");
        _;
    }

    function collectionExists(bytes32 collectionId) public view returns (bool) {
        return collectionStore[collectionId].collectionContract != address(0);
    }

    function collectionIdForAddress(address collectionAddress) public view returns (bytes32) {
        return collectionAddressToId[collectionAddress];
    }

    function op_create_collection(bytes32 ethscriptionId, bytes calldata data) public onlyEthscriptions {
        CollectionParams memory metadata = abi.decode(data, (CollectionParams));
        _createCollection(ethscriptionId, metadata);
    }

    function op_create_collection_and_add_self(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        CreateAndAddSelfParams memory op = abi.decode(data, (CreateAndAddSelfParams));

        _createCollection(ethscriptionId, op.metadata);
        _addSingleItem(ethscriptionId, ethscriptionId, op.item);
    }

    function op_add_self_to_collection(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        AddSelfToCollectionParams memory op = abi.decode(data, (AddSelfToCollectionParams));

        _addSingleItem(op.collectionId, ethscriptionId, op.item);
    }

    function op_remove_items(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        RemoveItemsOperation memory removeOp = abi.decode(data, (RemoveItemsOperation));
        CollectionRecord storage collection = collectionStore[removeOp.collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        require(!collection.locked, "Collection is locked");
        _requireCollectionOwner(ethscriptionId, removeOp.collectionId, "Only collection owner can remove");

        ERC721EthscriptionsCollection collectionContract =
            ERC721EthscriptionsCollection(collection.collectionContract);

        for (uint256 i = 0; i < removeOp.ethscriptionIds.length; i++) {
            bytes32 itemId = removeOp.ethscriptionIds[i];
            Membership storage membership = membershipOfEthscription[itemId];
            require(membership.collectionId == removeOp.collectionId, "Ethscription not in collection");

            uint256 tokenIdPlusOne = membership.tokenIdPlusOne;
            require(tokenIdPlusOne != 0, "Token missing");
            uint256 tokenId = tokenIdPlusOne - 1;

            delete membershipOfEthscription[itemId];
            delete collectionItems[removeOp.collectionId][tokenId];

            collectionContract.removeMember(itemId, tokenId);
        }

        emit ItemsRemoved(removeOp.collectionId, removeOp.ethscriptionIds.length, ethscriptionId);
    }

    function op_edit_collection(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        EditCollectionOperation memory editOp = abi.decode(data, (EditCollectionOperation));

        CollectionRecord storage collection = collectionStore[editOp.collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        require(!collection.locked, "Collection is locked");
        _requireCollectionOwner(ethscriptionId, editOp.collectionId, "Only collection owner can edit");

        // Update fields (empty strings allowed to clear fields)
        (, collection.descriptionRef) = DedupedBlobStore.storeMemory(bytes(editOp.description), collectionBlobStorage);
        (, collection.logoImageRef) = DedupedBlobStore.storeMemory(bytes(editOp.logoImageUri), collectionBlobStorage);
        (, collection.bannerImageRef) = DedupedBlobStore.storeMemory(bytes(editOp.bannerImageUri), collectionBlobStorage);
        (, collection.backgroundColorRef) = DedupedBlobStore.storeMemory(bytes(editOp.backgroundColor), collectionBlobStorage);
        (, collection.websiteLinkRef) = DedupedBlobStore.storeMemory(bytes(editOp.websiteLink), collectionBlobStorage);
        (, collection.twitterLinkRef) = DedupedBlobStore.storeMemory(bytes(editOp.twitterLink), collectionBlobStorage);
        (, collection.discordLinkRef) = DedupedBlobStore.storeMemory(bytes(editOp.discordLink), collectionBlobStorage);
        collection.merkleRoot = editOp.merkleRoot;

        emit CollectionEdited(editOp.collectionId);
    }

    function op_edit_collection_item(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        EditCollectionItemOperation memory editOp = abi.decode(data, (EditCollectionItemOperation));

        CollectionRecord storage collection = collectionStore[editOp.collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        require(!collection.locked, "Collection is locked");
        _requireCollectionOwner(ethscriptionId, editOp.collectionId, "Only collection owner can edit items");

        CollectionItem storage item = collectionItems[editOp.collectionId][editOp.itemIndex];
        require(item.ethscriptionId != bytes32(0), "Item does not exist");

        if (bytes(editOp.name).length > 0) item.name = editOp.name;
        if (bytes(editOp.backgroundColor).length > 0) item.backgroundColor = editOp.backgroundColor;
        if (bytes(editOp.description).length > 0) item.description = editOp.description;
        if (editOp.attributes.length > 0) {
            delete item.attributes;
            for (uint256 i = 0; i < editOp.attributes.length; i++) {
                item.attributes.push(editOp.attributes[i]);
            }
        }
    }

    function op_lock_collection(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        bytes32 collectionId = abi.decode(data, (bytes32));
        CollectionRecord storage collection = collectionStore[collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        _requireCollectionOwner(ethscriptionId, collectionId, "Only collection owner can lock");

        collection.locked = true;
        emit CollectionLocked(collectionId);
    }

    function onTransfer(bytes32 ethscriptionId, address from, address to) external override onlyEthscriptions {
        if (collectionExists(ethscriptionId)) {
            ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionStore[ethscriptionId].collectionContract);
            collection.factoryTransferOwnership(to);
            return;
        }
        
        Membership storage membership = membershipOfEthscription[ethscriptionId];
        
        if (!collectionExists(membership.collectionId)) {
            return;
        }
        
        ERC721EthscriptionsCollection c = ERC721EthscriptionsCollection(collectionStore[membership.collectionId].collectionContract);

        ERC721EthscriptionsCollection(c).forceTransfer(from, to, membership.tokenIdPlusOne - 1);
    }

    // -------------------- Views --------------------

    function getCollectionAddress(bytes32 collectionId) external view returns (address) {
        return collectionStore[collectionId].collectionContract;
    }

    function getCollection(bytes32 collectionId) public view returns (CollectionMetadata memory) {
        CollectionRecord storage record = collectionStore[collectionId];
        require(record.collectionContract != address(0), "Collection does not exist");

        return CollectionMetadata({
            collectionContract: record.collectionContract,
            locked: record.locked,
            name: DedupedBlobStore.readString(record.nameRef),
            symbol: DedupedBlobStore.readString(record.symbolRef),
            maxSupply: record.maxSupply,
            description: DedupedBlobStore.readString(record.descriptionRef),
            logoImageUri: DedupedBlobStore.readString(record.logoImageRef),
            bannerImageUri: DedupedBlobStore.readString(record.bannerImageRef),
            backgroundColor: DedupedBlobStore.readString(record.backgroundColorRef),
            websiteLink: DedupedBlobStore.readString(record.websiteLinkRef),
            twitterLink: DedupedBlobStore.readString(record.twitterLinkRef),
            discordLink: DedupedBlobStore.readString(record.discordLinkRef),
            merkleRoot: record.merkleRoot
        });
    }

    function getCollectionItem(bytes32 collectionId, uint256 itemIndex) external view returns (CollectionItem memory) {
        return collectionItems[collectionId][itemIndex];
    }

    function isInCollection(bytes32 ethscriptionId, bytes32 collectionId) external view returns (bool) {
        return membershipOfEthscription[ethscriptionId].collectionId == collectionId;
    }

    function getEthscriptionTokenId(bytes32 ethscriptionId) external view returns (uint256) {
        uint256 tokenIdPlusOne = membershipOfEthscription[ethscriptionId].tokenIdPlusOne;
        require(tokenIdPlusOne != 0, "Not in collection");
        return tokenIdPlusOne - 1;
    }

    function predictCollectionAddress(bytes32 collectionId) external view returns (address) {
        if (collectionStore[collectionId].collectionContract != address(0)) {
            return collectionStore[collectionId].collectionContract;
        }

        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(this)));
        return Create2.computeAddress(collectionId, keccak256(creationCode), address(this));
    }

    function getAllCollections() external view returns (bytes32[] memory) {
        return collectionIds;
    }

    // -------------------- Helpers --------------------

    function _createCollection(bytes32 collectionId, CollectionParams memory metadata) internal {
        require(!collectionExists(collectionId), "Collection already exists");

        Proxy collectionProxy = new Proxy{salt: collectionId}(address(this));
        
        collectionProxy.upgradeToAndCall(collectionsImplementation, abi.encodeWithSelector(
            ERC721EthscriptionsCollection.initialize.selector,
            metadata.name,
            metadata.symbol,
            ethscriptions.ownerOf(collectionId)
        ));
        
        collectionProxy.changeAdmin(Predeploys.PROXY_ADMIN);

        // Store string fields using DedupedBlobStore
        (, bytes32 nameRef) = DedupedBlobStore.storeMemory(bytes(metadata.name), collectionBlobStorage);
        (, bytes32 symbolRef) = DedupedBlobStore.storeMemory(bytes(metadata.symbol), collectionBlobStorage);
        (, bytes32 descriptionRef) = DedupedBlobStore.storeMemory(bytes(metadata.description), collectionBlobStorage);
        (, bytes32 logoImageRef) = DedupedBlobStore.storeMemory(bytes(metadata.logoImageUri), collectionBlobStorage);
        (, bytes32 bannerImageRef) = DedupedBlobStore.storeMemory(bytes(metadata.bannerImageUri), collectionBlobStorage);
        (, bytes32 backgroundColorRef) = DedupedBlobStore.storeMemory(bytes(metadata.backgroundColor), collectionBlobStorage);
        (, bytes32 websiteLinkRef) = DedupedBlobStore.storeMemory(bytes(metadata.websiteLink), collectionBlobStorage);
        (, bytes32 twitterLinkRef) = DedupedBlobStore.storeMemory(bytes(metadata.twitterLink), collectionBlobStorage);
        (, bytes32 discordLinkRef) = DedupedBlobStore.storeMemory(bytes(metadata.discordLink), collectionBlobStorage);

        collectionStore[collectionId] = CollectionRecord({
            collectionContract: address(collectionProxy),
            locked: false,
            nameRef: nameRef,
            symbolRef: symbolRef,
            maxSupply: metadata.maxSupply,
            descriptionRef: descriptionRef,
            logoImageRef: logoImageRef,
            bannerImageRef: bannerImageRef,
            backgroundColorRef: backgroundColorRef,
            websiteLinkRef: websiteLinkRef,
            twitterLinkRef: twitterLinkRef,
            discordLinkRef: discordLinkRef,
            merkleRoot: metadata.merkleRoot
        });
        
        collectionAddressToId[address(collectionProxy)] = collectionId;
        collectionIds.push(collectionId);

        emit CollectionCreated(collectionId, address(collectionProxy), metadata.name, metadata.symbol, metadata.maxSupply);
    }

    function _addSingleItem(
        bytes32 collectionId,
        bytes32 ethscriptionId,
        ItemData memory item
    ) internal {
        
        CollectionRecord storage collection = collectionStore[collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        require(!collection.locked, "Collection is locked");

        address sender = _getEthscriptionCreator(ethscriptionId);

        ERC721EthscriptionsCollection collectionContract =
            ERC721EthscriptionsCollection(collection.collectionContract);
        address collectionOwner = collectionContract.owner();
        bool senderIsCollectionOwner = sender == collectionOwner;

        if (collection.maxSupply > 0) {
            uint256 supply = collectionContract.totalSupply();
            require(supply + 1 <= collection.maxSupply, "Exceeds max supply");
        }

        Membership storage membership = membershipOfEthscription[ethscriptionId];
        require(membership.collectionId == bytes32(0), "Ethscription already in collection");
        require(collectionItems[collectionId][item.itemIndex].ethscriptionId == bytes32(0), "Item slot taken");

        if (!senderIsCollectionOwner && !_inImportMode()) {
            _verifyItemMerkleProof(item, collection.merkleRoot);
        }

        _storeCollectionItem(collectionId, ethscriptionId, item);
        membership.collectionId = collectionId;
        membership.tokenIdPlusOne = item.itemIndex + 1;
        collectionContract.addMember(ethscriptionId, item.itemIndex);

        emit ItemsAdded(collectionId, 1, ethscriptionId);
    }

    function _storeCollectionItem(bytes32 collectionId, bytes32 ethscriptionId, ItemData memory item) private {
        CollectionItem storage newItem = collectionItems[collectionId][item.itemIndex];
        newItem.itemIndex = item.itemIndex;
        newItem.name = item.name;
        newItem.ethscriptionId = ethscriptionId;
        newItem.backgroundColor = item.backgroundColor;
        newItem.description = item.description;

        for (uint256 j = 0; j < item.attributes.length; j++) {
            newItem.attributes.push(item.attributes[j]);
        }
    }
    
    function _getEthscriptionCreator(bytes32 ethscriptionId) private view returns (address) {
        Ethscriptions.Ethscription memory operation = ethscriptions.getEthscription(ethscriptionId, false);
        return operation.creator;
    }

    function _requireCollectionOwner(bytes32 ethscriptionId, bytes32 collectionId, string memory errorMessage) private view {
        address sender = _getEthscriptionCreator(ethscriptionId);
        CollectionRecord storage collection = collectionStore[collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        ERC721EthscriptionsCollection collectionContract = ERC721EthscriptionsCollection(collection.collectionContract);
        address currentOwner = collectionContract.owner();
        require(currentOwner == sender, errorMessage);
    }

    function _verifyItemMerkleProof(ItemData memory item, bytes32 merkleRoot) private pure {
        require(merkleRoot != bytes32(0), "Merkle proof required");
        bytes32 leaf = keccak256(abi.encode(item));
        require(MerkleProof.verify(item.merkleProof, merkleRoot, leaf), "Invalid Merkle proof");
    }
    
    function _inImportMode() private view returns (bool) {
        return block.timestamp < Constants.historicalBackfillApproxDoneAt;
    }
    
    function getMembershipOfEthscription(bytes32 ethscriptionId) external view returns (Membership memory) {
        return membershipOfEthscription[ethscriptionId];
    }
    
    /// @notice Get collection metadata by address
    /// @param collectionAddress The collection contract address
    /// @return metadata The collection metadata with decoded strings
    function getCollectionByAddress(address collectionAddress) external view returns (CollectionMetadata memory) {
        bytes32 collectionId = collectionAddressToId[collectionAddress];
        require(collectionId != bytes32(0), "Collection not found");
        return getCollection(collectionId);
    }
}

