// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC721EthscriptionsEnumerableUpgradeable.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {JSONParserLib} from "solady/utils/JSONParserLib.sol";
import "./ERC721EthscriptionsCollectionManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title ERC721EthscriptionsCollection
/// @notice Thin ERC-721 wrapper for Ethscription collections where the manager controls mint/burn
contract ERC721EthscriptionsCollection is ERC721EthscriptionsEnumerableUpgradeable, OwnableUpgradeable {
    using LibString for *;

    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

    /// @notice Manager contract that deployed and controls this collection
    ERC721EthscriptionsCollectionManager public manager;

    /// @notice Collection ID stored locally to avoid callback to manager
    bytes32 public collectionId;

    // Events
    event MemberAdded(bytes32 indexed ethscriptionId, uint256 indexed tokenId);
    event MemberRemoved(bytes32 indexed ethscriptionId, uint256 indexed tokenId);

    // Errors
    error NotFactory();
    error UnknownCollection();
    error TransferNotAllowed();

    modifier onlyFactory() {
        if (msg.sender != address(manager)) revert NotFactory();
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialOwner_,
        bytes32 collectionId_
    ) external initializer {
        __ERC721_init(name_, symbol_);
        
        if (initialOwner_ == address(0)) {
            __Ownable_init(address(1));
            _transferOwnership(address(0));
        } else {
            __Ownable_init(initialOwner_);
        }
        
        manager = ERC721EthscriptionsCollectionManager(msg.sender);
        collectionId = collectionId_;
    }

    function addMember(bytes32 ethscriptionId, uint256 tokenId) external onlyFactory {
        address owner = ethscriptions.ownerOf(ethscriptionId);

        // Handle minting to address(0) - mint to creator first then transfer
        if (owner == address(0)) {
            Ethscriptions.Ethscription memory ethscription = ethscriptions.getEthscription(ethscriptionId, false);
            address creator = ethscription.creator;
            _mint(creator, tokenId);
            _transfer(creator, address(0), tokenId);
        } else {
            _mint(owner, tokenId);
        }

        emit MemberAdded(ethscriptionId, tokenId);
    }

    function removeMember(bytes32 ethscriptionId, uint256 tokenId) external onlyFactory {
        require(_tokenExists(tokenId), "Token does not exist");
        address owner = ownerOf(tokenId);
        // Mark token as non-existent (handles enumeration cleanup)
        _setTokenExists(tokenId, false);

        // Emit burn-style transfer for indexers
        emit Transfer(owner, address(0), tokenId);

        emit MemberRemoved(ethscriptionId, tokenId);
    }

    /// @notice Called by the manager to mirror Ethscription transfers
    function forceTransfer(address from, address to, uint256 tokenId) external onlyFactory {
        require(_ownerOf(tokenId) == from, "Unexpected owner");
        _transfer(from, to, tokenId);
    }

    /// @notice Let the manager update Ownable owner to match inscription holder
    function factoryTransferOwnership(address newOwner) external onlyFactory {
        _transferOwnership(newOwner);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721EthscriptionsUpgradeable)
        returns (string memory)
    {
        if (!_tokenExists(tokenId)) revert("Token does not exist");

        ERC721EthscriptionsCollectionManager.CollectionItem memory item =
            manager.getCollectionItem(collectionId, tokenId);
        if (item.ethscriptionId == bytes32(0)) revert("Token not in collection");

        // Get the ethscription data to extract the ethscription number
        Ethscriptions.Ethscription memory ethscription = ethscriptions.getEthscription(item.ethscriptionId, false);

        (string memory mediaType, string memory mediaUri) = ethscriptions.getMediaUri(item.ethscriptionId);

        // Convert ethscriptionId to hex string (0x prefixed)
        string memory ethscriptionIdHex = uint256(item.ethscriptionId).toHexString(32);

        string memory jsonStart = string.concat('{"name":"', item.name.escapeJSON(), '"');
        if (bytes(item.description).length > 0) {
            jsonStart = string.concat(jsonStart, ',"description":"', item.description.escapeJSON(), '"');
        }

        // Add ethscription ID and number
        string memory ethscriptionFields = string.concat(
            ',"ethscription_id":"', ethscriptionIdHex, '"',
            ',"ethscription_number":', ethscription.ethscriptionNumber.toString()
        );

        string memory mediaField = string.concat(
            ',"',
            mediaType,
            '":"',
            mediaUri,
            '"'
        );

        string memory bgColor = "";
        if (bytes(item.backgroundColor).length > 0) {
            bgColor = string.concat(',"background_color":"', item.backgroundColor.escapeJSON(), '"');
        }

        string memory attributesJson = ',"attributes":[';
        for (uint256 i = 0; i < item.attributes.length; i++) {
            if (i > 0) attributesJson = string.concat(attributesJson, ',');
            attributesJson = string.concat(
                attributesJson,
                '{"trait_type":"',
                item.attributes[i].traitType.escapeJSON(),
                '","value":"',
                item.attributes[i].value.escapeJSON(),
                '"}'
            );
        }
        attributesJson = string.concat(attributesJson, ']');

        string memory json = string.concat(jsonStart, ethscriptionFields, mediaField, bgColor, attributesJson, '}');

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // --- Transfer/approvals blocked externally ---------------------------------

    function transferFrom(address, address, uint256)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransferNotAllowed();
    }

    /// @notice OpenSea collection-level metadata
    /// @return JSON string with collection metadata
    function contractURI() external view returns (string memory) {
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            manager.getCollectionByAddress(address(this));

        // Resolve URIs (handles esc://ethscriptions/{id}/data references)
        string memory image = _resolveEthscriptionURI(metadata.logoImageUri);
        string memory bannerImage = _resolveEthscriptionURI(metadata.bannerImageUri);

        // Build JSON with OpenSea fields
        string memory json = string.concat(
            '{"name":"', metadata.name.escapeJSON(),
            '","description":"', metadata.description.escapeJSON(),
            '","image":"', image.escapeJSON(),
            '","banner_image":"', bannerImage.escapeJSON(),
            '","external_link":"', metadata.websiteLink.escapeJSON(),
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransferNotAllowed();
    }

    function approve(address, uint256)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransferNotAllowed();
    }

    function setApprovalForAll(address, bool)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransferNotAllowed();
    }

    // -------------------- URI Resolution Helpers --------------------

    /// @notice Resolve URI, handling esc://ethscriptions/{id}/data format
    /// @dev Returns empty string if esc:// reference not found (doesn't revert)
    /// @param uri The URI to resolve (can be regular URI, data URI, or esc:// reference)
    /// @return The resolved URI (or empty string if esc:// reference not found)
    function _resolveEthscriptionURI(string memory uri) private view returns (string memory) {
        // Check if it's an ethscription reference
        if (!uri.startsWith("esc://ethscriptions/")) {
            return uri;  // Regular URI or data URI, pass through
        }

        // Format: esc://ethscriptions/0x{64 hex chars}/data
        // Split by "/" to extract parts: ["esc:", "", "ethscriptions", "0x{id}", "data"]
        string[] memory parts = uri.split("/");

        if (parts.length != 5 || !parts[4].eq("data")) {
            return "";  // Invalid format
        }

        // The ID should be at index 3 (after esc: / / ethscriptions /)
        string memory hexId = parts[3];

        // Validate hex ID format before parsing
        if (bytes(hexId).length != 66) {
            return "";  // Must be 0x + 64 hex chars
        }

        // Parse hex string to bytes32 using JSONParserLib (reverts on invalid)
        bytes32 ethscriptionId;
        try this._parseHexToBytes32(hexId) returns (bytes32 parsed) {
            ethscriptionId = parsed;
        } catch {
            return "";  // Invalid hex format
        }

        // Try to get the ethscription's media URI
        try ethscriptions.getMediaUri(ethscriptionId) returns (string memory, string memory mediaUri) {
            return mediaUri;  // Return the data URI from the referenced ethscription
        } catch {
            return "";  // Ethscription doesn't exist, return empty (don't revert)
        }
    }

    /// @notice Parse hex string to bytes32 (external for try/catch)
    /// @dev Must be external to allow try/catch usage
    function _parseHexToBytes32(string calldata hexStr) external pure returns (bytes32) {
        return bytes32(JSONParserLib.parseUintFromHex(hexStr));
    }
}
