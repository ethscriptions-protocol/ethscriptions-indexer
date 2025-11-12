// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./ERC20FixedDenomination.sol";
import "./libraries/Proxy.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import "./interfaces/IProtocolHandler.sol";
import "./ERC721EthscriptionsCollection.sol";
import "./ERC721EthscriptionsCollectionManager.sol";

/// @title ERC20FixedDenominationManager
/// @notice Manages ERC-20 tokens that move in a fixed denomination per mint/transfer lot.
/// @dev Deploys and controls ERC20FixedDenomination proxies; callable only by the Ethscriptions contract.
contract ERC20FixedDenominationManager is IProtocolHandler {
    using LibString for string;

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct TokenInfo {
        address tokenContract;
        bytes32 deployEthscriptionId;
        string tick;
        uint256 maxSupply;
        uint256 mintAmount;
        uint256 totalMinted;
        address collectionContract;  // ERC-721 collection for this token's notes
    }

    struct TokenItem {
        bytes32 deployEthscriptionId;  // Which token this ethscription belongs to
        uint256 amount;                // How many tokens this ethscription represents
        uint256 mintId;                // Fixed denomination note identifier
    }

    struct DeployOperation {
        string tick;
        uint256 maxSupply;
        uint256 mintAmount;
    }

    struct MintOperation {
        string tick;
        uint256 id;
        uint256 amount;
    }

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @dev Implementation contract used for proxy deployments
    address public constant tokenImplementation = Predeploys.ERC20_FIXED_DENOMINATION_IMPLEMENTATION;
    address public constant collectionImplementation = Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_IMPLEMENTATION;
    address public constant ethscriptions = Predeploys.ETHSCRIPTIONS;

    string public constant protocolName = "erc-20-fixed-denomination";

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    mapping(string => TokenInfo) internal tokensByTick;
    mapping(bytes32 => string) internal deployToTick;  // deployEthscriptionId => tick
    mapping(bytes32 => TokenItem) internal tokenItems;
    mapping(bytes32 => mapping(uint256 => bytes32)) internal mintIds; // deploy inscription => mint id => ethscriptionId
    mapping(address => bytes32) public collectionIdForAddress;  // collection address => deployEthscriptionId
    mapping(bytes32 => address) public collectionAddressForId;  // deployEthscriptionId => collection address

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyEthscriptions();
    error TokenAlreadyDeployed();
    error TokenNotDeployed();
    error MintAmountMismatch();
    error InvalidMintId();
    error InvalidMaxSupply();
    error InvalidMintAmount();
    error MaxSupplyNotDivisibleByMintAmount();

    // =============================================================
    //                          EVENTS
    // =============================================================

    event ERC20FixedDenominationTokenDeployed(
        bytes32 indexed deployEthscriptionId,
        address indexed tokenAddress,
        string tick,
        uint256 maxSupply,
        uint256 mintAmount
    );

    event ERC20FixedDenominationTokenMinted(
        bytes32 indexed deployEthscriptionId,
        address indexed to,
        uint256 amount,
        uint256 mintId,
        bytes32 ethscriptionId
    );

    event ERC721CollectionDeployed(
        bytes32 indexed deployEthscriptionId,
        address indexed collectionAddress,
        string tick
    );

    event ERC20FixedDenominationTokenTransferred(
        bytes32 indexed deployEthscriptionId,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 mintId,
        bytes32 ethscriptionId
    );

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyEthscriptions() {
        if (msg.sender != ethscriptions) revert OnlyEthscriptions();
        _;
    }

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Handles a deploy inscription for a fixed-denomination ERC-20.
    /// @param ethscriptionId The deploy inscription hash (also used as CREATE2 salt).
    /// @param data ABI-encoded DeployOperation parameters (tick, maxSupply, mintAmount).
    function op_deploy(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        DeployOperation memory deployOp = abi.decode(data, (DeployOperation));

        TokenInfo storage token = tokensByTick[deployOp.tick];

        if (token.deployEthscriptionId != bytes32(0)) revert TokenAlreadyDeployed();
        if (deployOp.maxSupply == 0) revert InvalidMaxSupply();
        if (deployOp.mintAmount == 0) revert InvalidMintAmount();
        if (deployOp.maxSupply % deployOp.mintAmount != 0) revert MaxSupplyNotDivisibleByMintAmount();

        bytes32 erc20Salt = _getContractSalt(deployOp.tick, "erc20");
        Proxy tokenProxy = new Proxy{salt: erc20Salt}(address(this));

        string memory name = deployOp.tick;
        string memory symbol = deployOp.tick.upper();

        tokenProxy.upgradeToAndCall(tokenImplementation, abi.encodeWithSelector(
                ERC20FixedDenomination.initialize.selector,
                name,
                symbol,
                deployOp.maxSupply * 10**18,
                ethscriptionId
            )
        );
        
        tokenProxy.changeAdmin(Predeploys.PROXY_ADMIN);

        // Deploy collection for this fixed denomination token
        bytes32 erc721Salt = _getContractSalt(deployOp.tick, "erc721");
        Proxy collectionProxy = new Proxy{salt: erc721Salt}(address(this));

        bytes memory collectionInitCalldata = abi.encodeWithSelector(
            ERC721EthscriptionsCollection.initialize.selector,
            deployOp.tick,  // Collection name
            deployOp.tick.upper()  // Collection symbol
            address(this),  // Manager owns the collection
            ethscriptionId  // Collection ID is the deploy ethscription ID
        );

        collectionProxy.upgradeToAndCall(collectionImplementation, collectionInitCalldata);
        collectionProxy.changeAdmin(Predeploys.PROXY_ADMIN);

        tokensByTick[deployOp.tick] = TokenInfo({
            tokenContract: address(tokenProxy),
            deployEthscriptionId: ethscriptionId,
            tick: deployOp.tick,
            maxSupply: deployOp.maxSupply,
            mintAmount: deployOp.mintAmount,
            totalMinted: 0,
            collectionContract: address(collectionProxy)
        });

        deployToTick[ethscriptionId] = deployOp.tick;

        // Set up collection lookups
        collectionIdForAddress[address(collectionProxy)] = ethscriptionId;
        collectionAddressForId[ethscriptionId] = address(collectionProxy);

        emit ERC20FixedDenominationTokenDeployed(
            ethscriptionId,
            address(tokenProxy),
            deployOp.tick,
            deployOp.maxSupply,
            deployOp.mintAmount
        );

        emit ERC721CollectionDeployed(
            ethscriptionId,
            address(collectionProxy),
            deployOp.tick
        );
    }

    /// @notice Processes a mint inscription and mints the fixed denomination to the inscription owner.
    /// @param ethscriptionId The mint inscription hash.
    /// @param data ABI-encoded MintOperation parameters (tick, id, amount).
    function op_mint(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        MintOperation memory mintOp = abi.decode(data, (MintOperation));

        TokenInfo storage token = tokensByTick[mintOp.tick];

        if (token.deployEthscriptionId == bytes32(0)) revert TokenNotDeployed();
        if (mintOp.amount != token.mintAmount) revert MintAmountMismatch();

        uint256 maxId = token.maxSupply / token.mintAmount;
        if (mintOp.id < 1 || mintOp.id > maxId) revert InvalidMintId();

        Ethscriptions ethscriptionsContract = Ethscriptions(ethscriptions);
        Ethscriptions.Ethscription memory ethscription = ethscriptionsContract.getEthscription(ethscriptionId);
        address initialOwner = ethscription.initialOwner;

        tokenItems[ethscriptionId] = TokenItem({
            deployEthscriptionId: token.deployEthscriptionId,
            amount: mintOp.amount,
            mintId: mintOp.id
        });
        mintIds[token.deployEthscriptionId][mintOp.id] = ethscriptionId;

        ERC20FixedDenomination(token.tokenContract).mint(initialOwner, mintOp.amount * 10**18);
        token.totalMinted += mintOp.amount;

        // Mint collection NFT with tokenId = mintId
        ERC721EthscriptionsCollection(token.collectionContract).addMember(ethscriptionId, mintOp.id);

        emit ERC20FixedDenominationTokenMinted(token.deployEthscriptionId, initialOwner, mintOp.amount, mintOp.id, ethscriptionId);
    }

    /// @notice Mirrors ERC-20 balances when a mint inscription NFT transfers.
    /// @param ethscriptionId The mint inscription hash being transferred.
    /// @param from The previous owner of the inscription NFT.
    /// @param to The new owner of the inscription NFT.
    function onTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) external virtual override onlyEthscriptions {
        TokenItem memory item = tokenItems[ethscriptionId];

        if (item.deployEthscriptionId == bytes32(0)) return;

        string memory tick = deployToTick[item.deployEthscriptionId];
        TokenInfo storage token = tokensByTick[tick];

        ERC20FixedDenomination(token.tokenContract).forceTransfer(from, to, item.amount * 10**18);

        // Transfer collection NFT with tokenId = mintId
        ERC721EthscriptionsCollection(token.collectionContract).forceTransfer(from, to, item.mintId);

        emit ERC20FixedDenominationTokenTransferred(item.deployEthscriptionId, from, to, item.amount, item.mintId, ethscriptionId);
    }

    // =============================================================
    //                  EXTERNAL VIEW FUNCTIONS
    // =============================================================

    function getTokenAddress(bytes32 deployEthscriptionId) external view returns (address) {
        string memory tick = deployToTick[deployEthscriptionId];
        return tokensByTick[tick].tokenContract;
    }

    function getTokenAddressByTick(string memory tick) external view returns (address) {
        return tokensByTick[tick].tokenContract;
    }

    function getTokenInfo(bytes32 deployEthscriptionId) external view returns (TokenInfo memory) {
        string memory tick = deployToTick[deployEthscriptionId];
        return tokensByTick[tick];
    }

    function getTokenInfoByTick(string memory tick) external view returns (TokenInfo memory) {
        return tokensByTick[tick];
    }

    function predictTokenAddressByTick(string memory tick) external view returns (address) {
        if (tokensByTick[tick].tokenContract != address(0)) {
            return tokensByTick[tick].tokenContract;
        }

        bytes32 erc20Salt = _getContractSalt(tick, "erc20");
        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(this)));
        return Create2.computeAddress(erc20Salt, keccak256(creationCode), address(this));
    }

    function predictCollectionAddressByTick(string memory tick) external view returns (address) {
        if (tokensByTick[tick].collectionContract != address(0)) {
            return tokensByTick[tick].collectionContract;
        }

        bytes32 erc721Salt = _getContractSalt(tick, "erc721");
        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(this)));
        return Create2.computeAddress(erc721Salt, keccak256(creationCode), address(this));
    }

    function isTokenItem(bytes32 ethscriptionId) external view returns (bool) {
        return tokenItems[ethscriptionId].deployEthscriptionId != bytes32(0);
    }

    function getTokenItem(bytes32 ethscriptionId) external view returns (TokenItem memory) {
        return tokenItems[ethscriptionId];
    }

    // =============================================================
    //                  COLLECTION VIEW FUNCTIONS
    // =============================================================

    /// @notice Get collection metadata for a given collection address
    /// @dev Called by ERC721EthscriptionsCollection.contractURI()
    function getCollectionByAddress(address collectionAddress) external view returns (
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory
    ) {
        bytes32 deployId = collectionIdForAddress[collectionAddress];
        require(deployId != bytes32(0), "Collection not found");

        string memory tick = deployToTick[deployId];
        TokenInfo memory token = tokensByTick[tick];

        return ERC721EthscriptionsCollectionManager.CollectionMetadata({
            collectionContract: collectionAddress,
            locked: false,  // Fixed denomination collections are never locked
            name: string.concat(token.tick, " ERC-721"),
            symbol: string.concat(token.tick, "-ERC-721"),
            maxSupply: token.maxSupply / token.mintAmount,  // Number of notes, not total tokens
            description: string.concat("Fixed denomination notes for ", token.tick),
            logoImageUri: "",
            bannerImageUri: "",
            backgroundColor: "",
            websiteLink: "",
            twitterLink: "",
            discordLink: "",
            merkleRoot: bytes32(0)
        });
    }

    /// @notice Get collection item data for a specific tokenId
    /// @dev Called by ERC721EthscriptionsCollection.tokenURI()
    function getCollectionItem(bytes32 collectionId, uint256 tokenId) external view returns (
        ERC721EthscriptionsCollectionManager.CollectionItem memory
    ) {
        // tokenId is the mintId for fixed denomination tokens
        bytes32 ethscriptionId = mintIds[collectionId][tokenId];
        require(ethscriptionId != bytes32(0), "Token does not exist");

        TokenItem memory item = tokenItems[ethscriptionId];
        string memory tick = deployToTick[collectionId];
        TokenInfo memory token = tokensByTick[tick];

        // Create attributes array
        ERC721EthscriptionsCollectionManager.Attribute[] memory attributes =
            new ERC721EthscriptionsCollectionManager.Attribute[](2);

        attributes[0] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Denomination",
            value: LibString.toString(token.mintAmount)
        });

        attributes[1] = ERC721EthscriptionsCollectionManager.Attribute({
            traitType: "Token",
            value: token.tick
        });

        return ERC721EthscriptionsCollectionManager.CollectionItem({
            itemIndex: tokenId,
            name: string.concat(token.tick, " #", LibString.toString(tokenId)),
            ethscriptionId: ethscriptionId,
            backgroundColor: "",
            description: string.concat(LibString.toString(token.mintAmount), " ", token.tick, " note"),
            attributes: attributes
        });
    }

    function getCollectionAddress(bytes32 deployEthscriptionId) external view returns (address) {
        return collectionAddressForId[deployEthscriptionId];
    }

    // =============================================================
    //                    PRIVATE FUNCTIONS
    // =============================================================

    function _getContractSalt(string memory tick, string memory contractType) private pure returns (bytes32) {
        return keccak256(abi.encode(tick, contractType));
    }
}
