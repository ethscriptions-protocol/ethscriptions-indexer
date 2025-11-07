// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./ERC721EthscriptionsEnumerableUpgradeable.sol";
import "./interfaces/IProtocolHandler.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";

/// @title NameRegistry
/// @notice Handles legacy word-domain registrations and mirrors ownership as an ERC-721 collection.
contract NameRegistry is ERC721EthscriptionsEnumerableUpgradeable, IProtocolHandler {
    using Strings for uint256;

    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

    string public constant PROTOCOL_NAME = "word-domains";
    uint8 public constant MIN_LENGTH = 1;
    uint8 public constant MAX_LENGTH = 31;

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

    function protocolName() external pure returns (string memory) {
        return PROTOCOL_NAME;
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

        bytes memory json = abi.encodePacked(
            '{"name":"',
            name,
            '","description":"Dotless word domain","attributes":[',
            '{"trait_type":"Name","value":"',
            name,
            '"},',
            '{"trait_type":"Ethscription","value":"',
            _bytes32ToHex(record.ethscriptionId),
            '"}',
            ']}'
        );

        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (auth != address(0) && auth != address(this)) {
            revert TransfersDisabled();
        }
        return super._update(to, tokenId, auth);
    }

    function _bytes32ToHex(bytes32 data) internal pure returns (string memory) {
        return Strings.toHexString(uint256(data), 32);
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
