// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./ERC721EthscriptionsEnumerableUpgradeable.sol";
import "./interfaces/IProtocolHandler.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title NameRegistry
/// @notice Handles legacy word-domain registrations and mirrors ownership as an ERC-721 collection.
contract NameRegistry is ERC721EthscriptionsEnumerableUpgradeable, IProtocolHandler {
    using LibString for *;

    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

    string public constant protocolName = "word-domains";

    struct DomainRecord {
        bytes32 packedName;
        bytes32 ethscriptionId;
        address owner;
        uint256 tokenId;
    }

    struct DomainInfo {
        string name;
        bytes32 ethscriptionId;
        address owner;
        uint256 tokenId;
    }

    mapping(bytes32 => DomainRecord) private domains;
    mapping(uint256 => bytes32) private nameKeyByTokenId;
    mapping(address => bytes32) internal primaryNameKey;

    error OnlyEthscriptions();
    error NameAlreadyRegistered();
    error EthscriptionAlreadyLinked();
    error InvalidName();
    error DomainNotFound();
    error NotDomainOwner();
    error TransfersDisabled();
    error TokenDoesNotExist();

    event DomainRegistered(bytes32 indexed nameKey, string name, address indexed owner, bytes32 indexed ethscriptionId, uint256 tokenId);
    event PrimarySet(address indexed owner, bytes32 indexed nameKey);
    event PrimaryCleared(address indexed owner);

    modifier onlyEthscriptions() {
        if (msg.sender != address(ethscriptions)) revert OnlyEthscriptions();
        _;
    }
    
    function name() public view override returns (string memory) {
        return "Name Registry";
    }
    
    function symbol() public view override returns (string memory) {
        return "NAME";
    }

    // ============================
    // Protocol handler functions
    // ============================

    function op_register(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        // Ruby indexer already validated and normalized the name, just trust it
        string memory name = abi.decode(data, (string));

        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(ethscriptionId, false);

        bytes32 nameKey = LibString.packOne(name);
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId != bytes32(0)) revert NameAlreadyRegistered();

        address owner = ethscriptions.ownerOf(ethscriptionId);
        uint256 tokenId = etsc.ethscriptionNumber;

        domains[nameKey] = DomainRecord({
            packedName: nameKey,
            ethscriptionId: ethscriptionId,
            owner: owner,
            tokenId: tokenId
        });
        nameKeyByTokenId[tokenId] = nameKey;

        if (owner == address(0)) {
            _mint(etsc.creator, tokenId);
            _transfer(etsc.creator, address(0), tokenId);
        } else {
            _mint(owner, tokenId);
        }

        emit DomainRegistered(nameKey, name, owner, ethscriptionId, tokenId);
    }

    function op_set_primary(bytes32 ethscriptionId, bytes calldata data) external onlyEthscriptions {
        // Ruby indexer already validated and normalized the name, just trust it
        string memory name = abi.decode(data, (string));
        address actor = ethscriptions.ownerOf(ethscriptionId);

        if (bytes(name).length == 0) {
            primaryNameKey[actor] = bytes32(0);
            emit PrimaryCleared(actor);
            return;
        }

        bytes32 nameKey = LibString.packOne(name);
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId == bytes32(0)) revert DomainNotFound();
        if (record.owner != actor) revert NotDomainOwner();

        primaryNameKey[actor] = nameKey;
        emit PrimarySet(actor, nameKey);
    }

    function onTransfer(bytes32 ethscriptionId, address from, address to) external override onlyEthscriptions {
        uint256 tokenId = ethscriptions.getTokenId(ethscriptionId);
        bytes32 nameKey = nameKeyByTokenId[tokenId];
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId == bytes32(0)) return;

        record.owner = to;
        
        _transfer(from, to, tokenId);

        if (primaryNameKey[from] == nameKey) {
            primaryNameKey[from] = bytes32(0);
            emit PrimaryCleared(from);
        }
    }

    // ============================
    // View helpers
    // ============================

    function getDomainInfo(bytes32 nameKey) external view returns (DomainInfo memory info) {
        return _domainInfo(nameKey);
    }

    function primaryName(address owner)
        external
        view
        returns (string memory name, bytes32 nameKey, bytes32 ethscriptionId)
    {
        nameKey = primaryNameKey[owner];
        if (nameKey == bytes32(0)) {
            return ("", bytes32(0), bytes32(0));
        }

        DomainRecord storage record = domains[nameKey];

        // Validate ownership - if they don't own it, return empty
        if (record.owner != owner) {
            return ("", bytes32(0), bytes32(0));
        }

        return (LibString.unpackOne(record.packedName), nameKey, record.ethscriptionId);
    }

    function tokenIdForNameKey(bytes32 nameKey) external view returns (uint256) {
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId == bytes32(0)) revert DomainNotFound();
        return record.tokenId;
    }

    function nameKeyForToken(uint256 tokenId) external view returns (bytes32) {
        bytes32 nameKey = nameKeyByTokenId[tokenId];
        if (domains[nameKey].ethscriptionId == bytes32(0)) revert TokenDoesNotExist();
        return nameKey;
    }

    // ============================
    // Metadata
    // ============================

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();

        bytes32 nameKey = nameKeyByTokenId[tokenId];
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId == bytes32(0)) revert TokenDoesNotExist();
        string memory name = LibString.unpackOne(record.packedName);

        // Get the ethscription data to extract the ethscription number
        Ethscriptions.Ethscription memory ethscription = ethscriptions.getEthscription(record.ethscriptionId, false);

        // Get the media URI from the ethscription
        (string memory mediaType, string memory mediaUri) = ethscriptions.getMediaUri(record.ethscriptionId);

        // Convert ethscriptionId to hex string (0x prefixed)
        string memory ethscriptionIdHex = uint256(record.ethscriptionId).toHexString(32);

        bytes memory json = abi.encodePacked(
            '{"name":"',
            name.escapeJSON(),
            '","description":"Dotless word domain"',
            ',"ethscription_id":"',
            ethscriptionIdHex,
            '","ethscription_number":',
            ethscription.ethscriptionNumber.toString(),
            ',"',
            mediaType,
            '":"',
            mediaUri,
            '","attributes":[',
            '{"trait_type":"Name","value":"',
            name.escapeJSON(),
            '"}',
            ']}'
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /// @notice OpenSea collection-level metadata
    /// @return JSON string with collection metadata
    function contractURI() external pure returns (string memory) {
        return string(abi.encodePacked(
            'data:application/json;base64,',
            Base64.encode(bytes(
                '{"name":"Word Domains Registry",'
                '"description":"On-chain word domain name system for Ethscriptions. Register unique, dotless domain names as NFTs.",'
                '"image":"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNTAwIiBoZWlnaHQ9IjUwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iNTAwIiBoZWlnaHQ9IjUwMCIgZmlsbD0iIzEwMTAxMCIvPjx0ZXh0IHg9IjI1MCIgeT0iMjUwIiBmb250LXNpemU9IjgwIiBmb250LWZhbWlseT0ibW9ub3NwYWNlIiB0ZXh0LWFuY2hvcj0ibWlkZGxlIiBmaWxsPSIjMDBmZjAwIj5bTkFNRVNdPC90ZXh0Pjwvc3ZnPg==",'
                '"external_link":"https://ethscriptions.com"}'
            ))
        ));
    }

    // --- Transfer/approvals blocked externally ---------------------------------

    function transferFrom(address, address, uint256)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransfersDisabled();
    }

    function safeTransferFrom(address, address, uint256)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransfersDisabled();
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransfersDisabled();
    }

    function approve(address, uint256)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransfersDisabled();
    }

    function setApprovalForAll(address, bool)
        public
        pure
        override(ERC721EthscriptionsUpgradeable, IERC721)
    {
        revert TransfersDisabled();
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (auth != address(0) && auth != address(this)) {
            revert TransfersDisabled();
        }
        return super._update(to, tokenId, auth);
    }

    function _domainInfo(bytes32 nameKey) internal view returns (DomainInfo memory info) {
        DomainRecord storage record = domains[nameKey];
        if (record.ethscriptionId == bytes32(0)) revert DomainNotFound();

        info = DomainInfo({
            name: LibString.unpackOne(record.packedName),
            ethscriptionId: record.ethscriptionId,
            owner: record.owner,
            tokenId: record.tokenId
        });
    }
}
