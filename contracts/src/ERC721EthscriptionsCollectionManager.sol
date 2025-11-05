// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./ERC721EthscriptionsCollection.sol";
import "./libraries/Proxy.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import "./interfaces/IProtocolHandler.sol";

contract ERC721EthscriptionsCollectionManager is IProtocolHandler {
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
        bytes32 ethscriptionId;
        string backgroundColor;
        string description;
        Attribute[] attributes;
        bytes32[] merkleProof;
    }

    struct Membership {
        bytes32 collectionId;
        uint256 tokenIdPlusOne; // 0 means not a member
    }

    struct AddItemsBatchOperation {
        bytes32 collectionId;
        ItemData[] items;
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

    address public constant collectionsImplementation = Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_IMPLEMENTATION;
    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);
    string public constant protocolName = "erc-721-ethscriptions-collection";

    mapping(bytes32 => CollectionRecord) private collectionStore;
    mapping(bytes32 => mapping(uint256 => CollectionItem)) public collectionItems;
    mapping(bytes32 => Membership) public membershipOfEthscription;
    mapping(address => bytes32) private collectionAddressToId;

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

    function op_create_and_add_self(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        CreateAndAddSelfParams memory op = abi.decode(data, (CreateAndAddSelfParams));
        require(op.item.ethscriptionId == ethscriptionId, "Self item must be creator");

        _createCollection(ethscriptionId, op.metadata);

        ItemData[] memory items = new ItemData[](1);
        items[0] = op.item;

        address sender = _getEthscriptionCreator(ethscriptionId);
        _addItems(AddItemsBatchOperation({collectionId: ethscriptionId, items: items}), sender, ethscriptionId);
    }

    function op_add_items_batch(bytes32 ethscriptionId, bytes calldata data) public onlyEthscriptions {
        address sender = _getEthscriptionCreator(ethscriptionId);
        AddItemsBatchOperation memory addOp = abi.decode(data, (AddItemsBatchOperation));
        _addItems(addOp, sender, ethscriptionId);
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

        if (bytes(editOp.description).length > 0) collection.description = editOp.description;
        if (bytes(editOp.logoImageUri).length > 0) collection.logoImageUri = editOp.logoImageUri;
        if (bytes(editOp.bannerImageUri).length > 0) collection.bannerImageUri = editOp.bannerImageUri;
        if (bytes(editOp.backgroundColor).length > 0) collection.backgroundColor = editOp.backgroundColor;
        if (bytes(editOp.websiteLink).length > 0) collection.websiteLink = editOp.websiteLink;
        if (bytes(editOp.twitterLink).length > 0) collection.twitterLink = editOp.twitterLink;
        if (bytes(editOp.discordLink).length > 0) collection.discordLink = editOp.discordLink;
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
        CollectionRecord storage collection = collectionStore[ethscriptionId];
        if (collection.collectionContract != address(0)) {
            ERC721EthscriptionsCollection(collection.collectionContract).factoryTransferOwnership(to);
            return;
        }

        Membership storage membership = membershipOfEthscription[ethscriptionId];
        bytes32 parentId = membership.collectionId;
        if (parentId == bytes32(0)) {
            return;
        }

        address collectionContract = collectionStore[parentId].collectionContract;
        if (collectionContract == address(0)) {
            return;
        }

        uint256 tokenIdPlusOne = membership.tokenIdPlusOne;
        if (tokenIdPlusOne == 0) {
            return;
        }

        ERC721EthscriptionsCollection(collectionContract).forceTransfer(from, to, tokenIdPlusOne - 1);
    }

    // -------------------- Views --------------------

    function getCollectionAddress(bytes32 collectionId) external view returns (address) {
        return collectionStore[collectionId].collectionContract;
    }

    function getCollection(bytes32 collectionId) external view returns (CollectionRecord memory) {
        return collectionStore[collectionId];
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
        bytes memory initCalldata = abi.encodeWithSelector(
            ERC721EthscriptionsCollection.initialize.selector,
            metadata.name,
            metadata.symbol,
            ethscriptions.ownerOf(collectionId)
        );
        
        collectionProxy.upgradeToAndCall(collectionsImplementation, initCalldata);
        collectionProxy.changeAdmin(Predeploys.PROXY_ADMIN);

        collectionStore[collectionId] = CollectionRecord({
            collectionContract: address(collectionProxy),
            locked: false,
            name: metadata.name,
            symbol: metadata.symbol,
            maxSupply: metadata.maxSupply,
            description: metadata.description,
            logoImageUri: metadata.logoImageUri,
            bannerImageUri: metadata.bannerImageUri,
            backgroundColor: metadata.backgroundColor,
            websiteLink: metadata.websiteLink,
            twitterLink: metadata.twitterLink,
            discordLink: metadata.discordLink,
            merkleRoot: metadata.merkleRoot
        });
        
        collectionAddressToId[address(collectionProxy)] = collectionId;
        collectionIds.push(collectionId);

        emit CollectionCreated(collectionId, address(collectionProxy), metadata.name, metadata.symbol, metadata.maxSupply);
    }

    function _addItems(
        AddItemsBatchOperation memory addOp,
        address sender,
        bytes32 updateTxHash
    ) internal {
        CollectionRecord storage collection = collectionStore[addOp.collectionId];
        require(collection.collectionContract != address(0), "Collection does not exist");
        require(!collection.locked, "Collection is locked");

        ERC721EthscriptionsCollection collectionContract =
            ERC721EthscriptionsCollection(collection.collectionContract);
        address collectionOwner = collectionContract.owner();
        bool senderIsCollectionOwner = sender == collectionOwner;

        if (collection.maxSupply > 0) {
            uint256 supply = collectionContract.totalSupply();
            require(supply + addOp.items.length <= collection.maxSupply, "Exceeds max supply");
        }

        for (uint256 i = 0; i < addOp.items.length; i++) {
            ItemData memory item = addOp.items[i];

            Membership storage membership = membershipOfEthscription[item.ethscriptionId];
            require(membership.collectionId == bytes32(0), "Ethscription already in collection");
            require(collectionItems[addOp.collectionId][item.itemIndex].ethscriptionId == bytes32(0), "Item slot taken");

            if (!senderIsCollectionOwner) {
                require(collection.merkleRoot != bytes32(0), "Merkle proof required");
                bytes32 leaf = keccak256(abi.encodePacked(addOp.collectionId, item.ethscriptionId));
                require(MerkleProof.verify(item.merkleProof, collection.merkleRoot, leaf), "Invalid Merkle proof");
            }

            _storeCollectionItem(addOp.collectionId, item);
            membership.collectionId = addOp.collectionId;
            membership.tokenIdPlusOne = item.itemIndex + 1;
            collectionContract.addMember(item.ethscriptionId, item.itemIndex);
        }

        emit ItemsAdded(addOp.collectionId, addOp.items.length, updateTxHash);
    }

    function _storeCollectionItem(bytes32 collectionId, ItemData memory item) private {
        CollectionItem storage newItem = collectionItems[collectionId][item.itemIndex];
        newItem.itemIndex = item.itemIndex;
        newItem.name = item.name;
        newItem.ethscriptionId = item.ethscriptionId;
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
}
