// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC721EthscriptionsEnumerableUpgradeable.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import "./ERC721EthscriptionsCollectionManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title ERC721EthscriptionsCollection
/// @notice Thin ERC-721 wrapper for Ethscription collections where the manager controls mint/burn
contract ERC721EthscriptionsCollection is ERC721EthscriptionsEnumerableUpgradeable, OwnableUpgradeable {
    using LibString for *;

    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

    /// @notice Factory (manager) that deployed this contract
    address public factory;

    // Events
    event MemberAdded(bytes32 indexed ethscriptionId, uint256 indexed tokenId);
    event MemberRemoved(bytes32 indexed ethscriptionId, uint256 indexed tokenId);

    // Errors
    error NotFactory();
    error UnknownCollection();
    error TransferNotAllowed();

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address initialOwner_
    ) external initializer {
        __ERC721_init(name_, symbol_);
        __Ownable_init(initialOwner_);
        factory = msg.sender;
    }

    /// @notice Lookup collection id via the factory registry
    function collectionId() public view returns (bytes32) {
        ERC721EthscriptionsCollectionManager manager = ERC721EthscriptionsCollectionManager(factory);
        bytes32 id = manager.collectionIdForAddress(address(this));
        if (id == bytes32(0)) revert UnknownCollection();
        return id;
    }

    function addMember(bytes32 ethscriptionId, uint256 tokenId) external onlyFactory {
        address owner = ethscriptions.ownerOf(ethscriptionId);
        _mint(owner, tokenId);
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

        ERC721EthscriptionsCollectionManager manager = ERC721EthscriptionsCollectionManager(factory);
        ERC721EthscriptionsCollectionManager.CollectionItem memory item =
            manager.getCollectionItem(collectionId(), tokenId);
        if (item.ethscriptionId == bytes32(0)) revert("Token not in collection");

        (string memory mediaType, string memory mediaUri) = ethscriptions.getMediaUri(item.ethscriptionId);

        string memory jsonStart = string.concat('{"name":"', item.name.escapeJSON(), '"');
        if (bytes(item.description).length > 0) {
            jsonStart = string.concat(jsonStart, ',"description":"', item.description.escapeJSON(), '"');
        }

        string memory mediaField = string.concat(
            ',"',
            mediaType,
            '":"',
            mediaUri.escapeJSON(),
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

        string memory json = string.concat(jsonStart, mediaField, bgColor, attributesJson, '}');

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
}
