// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC721EthscriptionsSequentialEnumerableUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./libraries/SSTORE2Unlimited.sol";
import "./libraries/BytePackLib.sol";
import "./libraries/EthscriptionsRendererLib.sol";
import "./EthscriptionsProver.sol";
import "./libraries/Predeploys.sol";
import "./L2/L1Block.sol";
import "./interfaces/IProtocolHandler.sol";
import "./libraries/Constants.sol";

/// @title Ethscriptions ERC-721 Contract
/// @notice Mints Ethscriptions as ERC-721 tokens based on L1 transaction data
/// @dev Uses ethscription number as token ID and name, while transaction hash remains the primary identifier for function calls
contract Ethscriptions is ERC721EthscriptionsSequentialEnumerableUpgradeable {
    using LibString for *;
    using EthscriptionsRendererLib for EthscriptionStorage;

    // =============================================================
    //                          STRUCTS
    // =============================================================

    /// @notice Internal storage struct for ethscriptions (optimized for storage)
    struct EthscriptionStorage {
        // Full slots
        bytes32 contentUriHash;
        bytes32 contentSha;
        bytes32 l1BlockHash;
        // Packed slot (32 bytes)
        address creator;
        uint48  createdAt;
        uint48  l1BlockNumber;
        // Dynamic
        string  mimetype;
        // Packed slot (27 bytes used, 5 free)
        address initialOwner;
        uint48  ethscriptionNumber;
        bool    esip6;
        // Packed slot (26 bytes used, 6 free)
        address previousOwner;
        uint48  l2BlockNumber;
    }

    struct ProtocolParams {
        string protocolName;  // Protocol identifier (e.g., "erc-20-fixed-denomination", "erc-721-ethscriptions-collection", etc.)
        string operation;     // Operation to perform (e.g., "mint", "deploy", "create_collection", etc.)
        bytes data;          // ABI-encoded parameters specific to the protocol/operation
    }

    struct CreateEthscriptionParams {
        bytes32 ethscriptionId;
        bytes32 contentUriHash;  // SHA256 of raw content URI (for protocol uniqueness)
        address initialOwner;
        bytes content;           // Raw decoded bytes (not Base64)
        string mimetype;
        bool esip6;
        ProtocolParams protocolParams;  // Protocol operation data (optional)
    }

    /// @notice Complete denormalized ethscription data for external/off-chain consumption
    /// @dev Includes all EthscriptionStorage fields plus owner and content
    struct Ethscription {
        // Identity
        bytes32 ethscriptionId;        // L1 tx hash (the key)
        uint256 ethscriptionNumber;    // Token ID

        // Core metadata
        bytes32 contentUriHash;
        bytes32 contentSha;
        string  mimetype;
        bytes   content;               // Full content bytes (empty when includeContent=false)

        // Ownership
        address currentOwner;          // Current owner from ERC721 storage
        address creator;
        address initialOwner;
        address previousOwner;

        // Block/time data
        bytes32 l1BlockHash;
        uint256 l1BlockNumber;
        uint256 l2BlockNumber;
        uint256 createdAt;

        // Protocol
        bool    esip6;
    }

    // =============================================================
    //                     CONSTANTS & IMMUTABLES
    // =============================================================

    /// @dev L1Block predeploy for getting L1 block info
    L1Block constant l1Block = L1Block(Predeploys.L1_BLOCK_ATTRIBUTES);

    /// @dev Ethscriptions Prover contract (pre-deployed at known address)
    EthscriptionsProver public constant prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @dev Ethscription ID (L1 tx hash) => Ethscription data
    mapping(bytes32 => EthscriptionStorage) internal ethscriptions;

    /// @dev Content SHA => packed content (for <32 bytes) or SSTORE2 pointer (for >=32 bytes)
    mapping(bytes32 => bytes32) public contentStorageBySha;

    /// @dev Content URI hash => first ethscription tx hash that used it (for protocol uniqueness check)
    /// @dev bytes32(0) means unused, non-zero means the content URI has been used
    mapping(bytes32 => bytes32) public firstEthscriptionByContentUri;

    /// @dev Mapping from token ID (ethscription number) to ethscription ID (L1 tx hash)
    mapping(uint256 => bytes32) public tokenIdToEthscriptionId;

    /// @dev Protocol registry - maps protocol names to handler addresses
    mapping(string => address) public protocolHandlers;

    /// @dev Track which protocol an ethscription uses
    mapping(bytes32 => string) public protocolOf;

    /// @dev Array of genesis ethscription transaction hashes that need events emitted
    /// @notice This array is populated during genesis and cleared (by popping) when events are emitted
    bytes32[] internal pendingGenesisEvents;

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error DuplicateContentUri();
    error InvalidCreator();
    error EthscriptionAlreadyExists();
    error EthscriptionDoesNotExist();
    error OnlyDepositor();
    error InvalidHandler();
    error ProtocolAlreadyRegistered();
    error PreviousOwnerMismatch();
    error NoSuccessfulTransfers();
    error TokenDoesNotExist();

    // =============================================================
    //                          EVENTS
    // =============================================================

    /// @notice Emitted when a new ethscription is created
    event EthscriptionCreated(
        bytes32 indexed ethscriptionId,
        address indexed creator,
        address indexed initialOwner,
        bytes32 contentUriHash,
        bytes32 contentSha,
        uint256 ethscriptionNumber
    );

    /// @notice Emitted when an ethscription is transferred (Ethscriptions protocol semantics)
    /// @dev This event matches the Ethscriptions protocol transfer semantics where 'from' is the initiator
    /// For creations, this shows transfer from creator to initial owner (not from address(0))
    event EthscriptionTransferred(
        bytes32 indexed ethscriptionId,
        address indexed from,
        address indexed to,
        uint256 ethscriptionNumber
    );

    /// @notice Emitted when a protocol handler is registered
    event ProtocolRegistered(string indexed protocol, address indexed handler);

    /// @notice Emitted when a protocol handler operation fails but ethscription continues
    event ProtocolHandlerFailed(
        bytes32 indexed ethscriptionId,
        string protocol,
        bytes revertData
    );

    /// @notice Emitted when a protocol handler operation succeeds
    event ProtocolHandlerSuccess(
        bytes32 indexed ethscriptionId,
        string protocol,
        bytes returnData
    );

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    /// @notice Modifier to emit pending genesis events on first real creation
    modifier emitGenesisEvents() {
        _emitPendingGenesisEvents();
        _;
    }

    /// @notice Resolve and validate an ethscription (by ID) or revert
    function _getEthscriptionOrRevert(bytes32 ethscriptionId) internal view returns (EthscriptionStorage storage ethscription) {
        if (!_ethscriptionExists(ethscriptionId)) revert EthscriptionDoesNotExist();
        ethscription = ethscriptions[ethscriptionId];
    }

    /// @notice Resolve and validate an ethscription (by tokenId) or revert
    function _getEthscriptionOrRevert(uint256 tokenId) internal view returns (EthscriptionStorage storage ethscription) {
        bytes32 id = tokenIdToEthscriptionId[tokenId];
        ethscription = _getEthscriptionOrRevert(id);
    }

    // =============================================================
    //                    ADMIN/SETUP FUNCTIONS
    // =============================================================

    /// @notice Register a protocol handler
    /// @param protocol The protocol identifier (e.g., "erc-20-fixed-denomination", "erc-721-ethscriptions-collection")
    /// @param handler The address of the handler contract
    /// @dev Only callable by the depositor address (used during genesis setup)
    function registerProtocol(string calldata protocol, address handler) external {
        if (msg.sender != Predeploys.DEPOSITOR_ACCOUNT) revert OnlyDepositor();
        if (handler == address(0)) revert InvalidHandler();
        if (protocolHandlers[protocol] != address(0)) revert ProtocolAlreadyRegistered();

        protocolHandlers[protocol] = handler;
        emit ProtocolRegistered(protocol, handler);
    }

    // =============================================================
    //                    CORE EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Create (mint) a new ethscription token
    /// @dev Called via system transaction with msg.sender spoofed as the actual creator
    /// @param params Struct containing all ethscription creation parameters
    function createEthscription(
        CreateEthscriptionParams calldata params
    ) external emitGenesisEvents returns (uint256 tokenId) {
        address creator = msg.sender;

        if (creator == address(0)) revert InvalidCreator();
        if (_ethscriptionExists(params.ethscriptionId)) revert EthscriptionAlreadyExists();
        
        bool contentUriAlreadySeen = firstEthscriptionByContentUri[params.contentUriHash] != bytes32(0);

        if (contentUriAlreadySeen) {
            if (!params.esip6) revert DuplicateContentUri();
        } else {
            firstEthscriptionByContentUri[params.contentUriHash] = params.ethscriptionId;
        }

        // Store content and get content SHA (of raw bytes)
        bytes32 contentSha = _storeContent(params.content);

        ethscriptions[params.ethscriptionId] = EthscriptionStorage({
            contentUriHash: params.contentUriHash,
            contentSha: contentSha,
            l1BlockHash: l1Block.hash(),
            creator: creator,
            createdAt: uint48(block.timestamp),
            l1BlockNumber: uint48(l1Block.number()),
            mimetype: params.mimetype,
            initialOwner: params.initialOwner,
            ethscriptionNumber: uint48(totalSupply()),
            esip6: params.esip6,
            previousOwner: creator,
            l2BlockNumber: uint48(block.number)
        });

        // Use ethscription number as token ID
        tokenId = totalSupply();

        // Store the mapping from token ID to ethscription ID
        tokenIdToEthscriptionId[tokenId] = params.ethscriptionId;

        // Mint to initial owner (if address(0), mint to creator then transfer)
        if (params.initialOwner == address(0)) {
            _mint(creator, tokenId);
            _transfer(creator, address(0), tokenId);
        } else {
            _mint(params.initialOwner, tokenId);
        }

        emit EthscriptionCreated(
            params.ethscriptionId,
            creator,
            params.initialOwner,
            params.contentUriHash,
            contentSha,
            tokenId
        );

        // Handle protocol operations (if any)
        _callProtocolOperation(params.ethscriptionId, params.protocolParams);
    }

    /// @notice Transfer an ethscription
    /// @dev Called via system transaction with msg.sender spoofed as 'from'
    /// @param to The recipient address (can be address(0) for burning)
    /// @param ethscriptionId The ethscription to transfer (used to find token ID)
    function transferEthscription(
        address to,
        bytes32 ethscriptionId
    ) external {
        // Load and validate
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        uint256 tokenId = ethscription.ethscriptionNumber;
        // Standard ERC721 transfer will handle authorization
        transferFrom(msg.sender, to, tokenId);
    }

    /// @notice Transfer an ethscription with previous owner validation (ESIP-2)
    /// @dev Called via system transaction with msg.sender spoofed as 'from'
    /// @param to The recipient address (can be address(0) for burning)
    /// @param ethscriptionId The ethscription to transfer
    /// @param previousOwner The required previous owner for validation
    function transferEthscriptionForPreviousOwner(
        address to,
        bytes32 ethscriptionId,
        address previousOwner
    ) external {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);

        // Verify the previous owner matches
        if (ethscription.previousOwner != previousOwner) {
            revert PreviousOwnerMismatch();
        }

        // Use transferFrom which now handles burns when to == address(0)
        transferFrom(msg.sender, to, ethscription.ethscriptionNumber);
    }

    /// @notice Transfer multiple ethscriptions to a single recipient
    /// @dev Continues transferring even if individual transfers fail due to wrong ownership
    /// @param ethscriptionIds Array of ethscription IDs to transfer
    /// @param to The recipient address (can be address(0) for burning)
    /// @return successCount Number of successful transfers
    function transferEthscriptions(
        address to,
        bytes32[] calldata ethscriptionIds
    ) external returns (uint256 successCount) {
        for (uint256 i = 0; i < ethscriptionIds.length; i++) {
            // Get the ethscription to find its token ID
            if (!_ethscriptionExists(ethscriptionIds[i])) continue; // Skip non-existent ethscriptions
            EthscriptionStorage storage ethscription = ethscriptions[ethscriptionIds[i]];

            uint256 tokenId = ethscription.ethscriptionNumber;

            // Check if sender owns this token before attempting transfer
            // This prevents reverts and allows us to continue
            if (_ownerOf(tokenId) == msg.sender) {
                // Perform the transfer directly using internal _update
                _update(to, tokenId, msg.sender);
                successCount++;
            }
            // If sender doesn't own the token, just continue to next one
        }

        if (successCount == 0) revert NoSuccessfulTransfers();
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    // ---------------------- Token Metadata ----------------------

    function name() public pure override returns (string memory) {
        return "Ethscriptions";
    }
    
    function symbol() public pure override returns (string memory) {
        return "ETHSCRIPTIONS";
    }

    // ---------------------- Token URI & Media ----------------------

    /// @notice Returns the full data URI for a token
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Find the ethscription for this token ID (ethscription number)
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(tokenId);
        bytes32 id = tokenIdToEthscriptionId[tokenId];

        // Get content
        bytes memory content = _getEthscriptionContent(id);

        // Build complete token URI using the library - it handles everything internally
        return EthscriptionsRendererLib.buildTokenURI(ethscription, id, content);
    }

    /// @notice Get the media URI for an ethscription (image or animation_url)
    /// @param ethscriptionId The ethscription ID (L1 tx hash) of the ethscription
    /// @return mediaType Either "image" or "animation_url"
    /// @return mediaUri The data URI for the media
    function getMediaUri(bytes32 ethscriptionId) external view returns (string memory mediaType, string memory mediaUri) {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        bytes memory content = _getEthscriptionContent(ethscriptionId);
        return ethscription.getMediaUri(content);
    }

    // -------------------- Data Retrieval --------------------

    /// @notice Internal helper to build complete ethscription data
    /// @param ethscriptionId The ethscription ID
    /// @param includeContent Whether to include content bytes
    /// @return complete The complete ethscription data
    function _buildEthscription(bytes32 ethscriptionId, bool includeContent) internal view returns (Ethscription memory) {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);

        return Ethscription({
            // Identity
            ethscriptionId: ethscriptionId,
            ethscriptionNumber: uint256(ethscription.ethscriptionNumber),

            // Core metadata
            contentUriHash: ethscription.contentUriHash,
            contentSha: ethscription.contentSha,
            mimetype: ethscription.mimetype,
            content: includeContent ? _getEthscriptionContent(ethscriptionId) : bytes(""),

            // Ownership
            currentOwner: _ownerOf(uint256(ethscription.ethscriptionNumber)),
            creator: ethscription.creator,
            initialOwner: ethscription.initialOwner,
            previousOwner: ethscription.previousOwner,

            // Block/time data
            l1BlockHash: ethscription.l1BlockHash,
            l1BlockNumber: uint256(ethscription.l1BlockNumber),
            l2BlockNumber: uint256(ethscription.l2BlockNumber),
            createdAt: uint256(ethscription.createdAt),

            // Protocol
            esip6: ethscription.esip6
        });
    }

    /// @notice Get complete ethscription data (includes content by default)
    /// @param ethscriptionId The ethscription ID to look up
    /// @return The complete ethscription data with content
    function getEthscription(bytes32 ethscriptionId) external view returns (Ethscription memory) {
        return _buildEthscription(ethscriptionId, true);
    }

    /// @notice Get complete ethscription data with option to exclude content
    /// @param ethscriptionId The ethscription ID to look up
    /// @param includeContent Whether to include content (false for gas efficiency)
    /// @return The complete ethscription data
    function getEthscription(bytes32 ethscriptionId, bool includeContent) external view returns (Ethscription memory) {
        return _buildEthscription(ethscriptionId, includeContent);
    }

    /// @notice Get complete ethscription data by tokenId (includes content by default)
    /// @param tokenId The token ID to look up
    /// @return The complete ethscription data with content
    function getEthscription(uint256 tokenId) external view returns (Ethscription memory) {
        bytes32 ethscriptionId = tokenIdToEthscriptionId[tokenId];
        // _buildEthscription calls _getEthscriptionOrRevert which handles existence check
        return _buildEthscription(ethscriptionId, true);
    }

    /// @notice Get complete ethscription data by tokenId with option to exclude content
    /// @param tokenId The token ID to look up
    /// @param includeContent Whether to include content (false for gas efficiency)
    /// @return The complete ethscription data
    function getEthscription(uint256 tokenId, bool includeContent) external view returns (Ethscription memory) {
        bytes32 ethscriptionId = tokenIdToEthscriptionId[tokenId];
        // _buildEthscription calls _getEthscriptionOrRevert which handles existence check
        return _buildEthscription(ethscriptionId, includeContent);
    }

    // -------------------- Internal helper for content retrieval --------------------

    /// @notice Internal: Get content for an ethscription
    /// @dev Kept as internal for tokenURI and other internal uses
    function _getEthscriptionContent(bytes32 ethscriptionId) internal view returns (bytes memory) {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        bytes32 ref = contentStorageBySha[ethscription.contentSha];

        // Check if it's inline content using BytePackLib
        if (BytePackLib.isPacked(ref)) {
            return BytePackLib.unpack(ref);
        }

        // It's a pointer to SSTORE2 contract
        address pointer = address(uint160(uint256(ref)));

        return SSTORE2Unlimited.read(pointer);
    }

    // ---------------- Ownership & Existence Checks ----------------

    /// @notice Check if an ethscription exists
    /// @param ethscriptionId The ethscription ID to check
    /// @return true if the ethscription exists
    function exists(bytes32 ethscriptionId) external view returns (bool) {
        return _ethscriptionExists(ethscriptionId);
    }
    
    function exists(uint256 tokenId) external view returns (bool) {
        return _ethscriptionExists(tokenIdToEthscriptionId[tokenId]);
    }

    /// @notice Get owner of an ethscription by transaction hash
    /// @dev Overload of ownerOf that accepts transaction hash instead of token ID
    function ownerOf(bytes32 ethscriptionId) external view returns (address) {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        uint256 tokenId = ethscription.ethscriptionNumber;

        return ownerOf(tokenId);
    }

    /// @notice Get the token ID (ethscription number) for a given transaction hash
    /// @param ethscriptionId The ethscription ID to look up
    /// @return The token ID (ethscription number)
    function getTokenId(bytes32 ethscriptionId) external view returns (uint256) {
        EthscriptionStorage storage ethscription = _getEthscriptionOrRevert(ethscriptionId);
        return ethscription.ethscriptionNumber;
    }

    /// @notice Get the ethscription ID (bytes32) for a given tokenId
    /// @dev Reverts if tokenId does not exist
    function getEthscriptionId(uint256 tokenId) external view returns (bytes32) {
        bytes32 id = tokenIdToEthscriptionId[tokenId];
        if (!_ethscriptionExists(id)) revert TokenDoesNotExist();
        return id;
    }

    // =============================================================
    //                   INTERNAL FUNCTIONS
    // =============================================================

    /// @dev Override _update to track previous owner and handle token transfers
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        // Find the ethscription ID for this token ID (ethscription number)
        bytes32 id = tokenIdToEthscriptionId[tokenId];
        EthscriptionStorage storage ethscription = ethscriptions[id];

        // Call parent implementation first to handle the actual update
        from = super._update(to, tokenId, auth);

        if (from == address(0)) {
            // Mint: emit once when minted directly to initial owner
            if (to == ethscription.initialOwner) {
                emit EthscriptionTransferred(id, ethscription.creator, to, tokenId);
            }
            // no previousOwner update or tokenManager call on mint
        } else {
            // Transfers (including creator -> address(0))
            emit EthscriptionTransferred(id, from, to, tokenId);
            ethscription.previousOwner = from;

            // Notify protocol handler about the transfer if this ethscription has a protocol
            _notifyProtocolTransfer(id, from, to);
        }

        // Queue ethscription for batch proving at block boundary once proving is live
        _queueForProving(id);
    }

    /// @notice Check if an ethscription exists
    /// @dev An ethscription exists if it has been created (has a creator set)
    /// @param ethscriptionId The ethscription ID to check
    /// @return True if the ethscription exists
    function _ethscriptionExists(bytes32 ethscriptionId) internal view returns (bool) {
        // Check if this ethscription has been created
        // We can't use _tokenExists here because we need the tokenId first
        // Instead, check if creator is set (ethscriptions are never created with zero creator)
        return ethscriptions[ethscriptionId].creator != address(0);
    }

    /// @notice Internal helper to store content and return its SHA
    /// @param content The raw content bytes to store
    /// @return contentSha The SHA256 hash of the content
    function _storeContent(bytes calldata content) internal returns (bytes32 contentSha) {
        // Compute SHA256 hash of content first
        contentSha = sha256(content);

        // Check if content already exists
        bytes32 existing = contentStorageBySha[contentSha];
        if (existing != bytes32(0)) {
            // Content already stored, just return the SHA
            return contentSha;
        }

        // Store based on size
        if (content.length <= 31) {
            // Pack small content directly into bytes32 (0-31 bytes)
            contentStorageBySha[contentSha] = BytePackLib.packCalldata(content);
        } else {
            // Deploy via SSTORE2 for larger content (32+ bytes)
            address pointer = SSTORE2Unlimited.write(content);
            contentStorageBySha[contentSha] = bytes32(uint256(uint160(pointer)));
        }

        return contentSha;
    }

    function _queueForProving(bytes32 ethscriptionId) internal {
        if (block.timestamp >= Constants.historicalBackfillApproxDoneAt) {
            prover.queueEthscription(ethscriptionId);
        }
    }

    /// @notice Call a protocol handler operation during ethscription creation
    /// @param ethscriptionId The ethscription ID (L1 tx hash)
    /// @param protocolParams The protocol parameters struct
    function _callProtocolOperation(
        bytes32 ethscriptionId,
        ProtocolParams calldata protocolParams
    ) internal {
        // Skip if no protocol specified
        if (bytes(protocolParams.protocolName).length == 0) {
            return;
        }

        // Track which protocol this ethscription uses
        protocolOf[ethscriptionId] = protocolParams.protocolName;

        address handler = protocolHandlers[protocolParams.protocolName];

        // Skip if no handler is registered
        if (handler == address(0)) {
            return;
        }

        // Encode the function call with operation name
        bytes memory callData = abi.encodeWithSignature(
            string.concat("op_", protocolParams.operation, "(bytes32,bytes)"),
            ethscriptionId,
            protocolParams.data
        );

        // Call the handler - failures don't revert ethscription creation
        (bool success, bytes memory returnData) = handler.call(callData);

        if (!success) {
            emit ProtocolHandlerFailed(ethscriptionId, protocolParams.protocolName, returnData);
        } else {
            emit ProtocolHandlerSuccess(ethscriptionId, protocolParams.protocolName, returnData);
        }
    }

    /// @notice Notify protocol handler about an ethscription transfer
    /// @param ethscriptionId The ethscription ID (L1 tx hash)
    /// @param from The address transferring from
    /// @param to The address transferring to
    function _notifyProtocolTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) internal {
        string memory protocol = protocolOf[ethscriptionId];

        // Skip if no protocol assigned
        if (bytes(protocol).length == 0) {
            return;
        }

        address handler = protocolHandlers[protocol];

        // Skip if no handler is registered
        if (handler == address(0)) {
            return;
        }

        // Use try/catch for cleaner error handling
        try IProtocolHandler(handler).onTransfer(ethscriptionId, from, to) {
            // onTransfer doesn't return data, so pass empty bytes
            emit ProtocolHandlerSuccess(ethscriptionId, protocol, "");
        } catch (bytes memory revertData) {
            emit ProtocolHandlerFailed(ethscriptionId, protocol, revertData);
        }
    }

    // =============================================================
    //                    PRIVATE FUNCTIONS
    // =============================================================

    /// @notice Emit all pending genesis events
    /// @dev Emits events in chronological order then clears the array
    function _emitPendingGenesisEvents() private {
        // Store the length before we start popping
        uint256 count = pendingGenesisEvents.length;

        // Emit events in the order they were created (FIFO)
        for (uint256 i = 0; i < count; i++) {
            bytes32 ethscriptionId = pendingGenesisEvents[i];

            // Get the ethscription data
            EthscriptionStorage storage ethscription = ethscriptions[ethscriptionId];
            uint256 tokenId = ethscription.ethscriptionNumber;

            // Emit events in the same order as live mints:
            // 1. Transfer (mint), 2. EthscriptionTransferred, 3. EthscriptionCreated

            if (ethscription.initialOwner == address(0)) {
                // Token was minted to creator then burned
                // First emit mint to creator
                emit Transfer(address(0), ethscription.creator, tokenId);
                // Then emit burn from creator to null address
                emit Transfer(ethscription.creator, address(0), tokenId);
                // Emit Ethscriptions transfer event for the burn
                emit EthscriptionTransferred(
                    ethscriptionId,
                    ethscription.creator,
                    address(0),
                    ethscription.ethscriptionNumber
                );
            } else {
                // Token was minted directly to initial owner
                emit Transfer(address(0), ethscription.initialOwner, tokenId);
                // Emit Ethscriptions transfer event
                emit EthscriptionTransferred(
                    ethscriptionId,
                    ethscription.creator,
                    ethscription.initialOwner,
                    ethscription.ethscriptionNumber
                );
            }

            // Finally emit the creation event (matching the order of live mints)
            emit EthscriptionCreated(
                ethscriptionId,
                ethscription.creator,
                ethscription.initialOwner,
                ethscription.contentUriHash,
                ethscription.contentSha,
                ethscription.ethscriptionNumber
            );
        }

        // Pop the array until it's empty
        while (pendingGenesisEvents.length > 0) {
            pendingGenesisEvents.pop();
        }
    }
}
