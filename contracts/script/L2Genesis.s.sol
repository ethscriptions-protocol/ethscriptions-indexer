// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {L2GenesisConfig} from "./L2GenesisConfig.sol";
import {Predeploys} from "../src/libraries/Predeploys.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {Ethscriptions} from "../src/Ethscriptions.sol";
import {MetaStoreLib} from "../src/libraries/MetaStoreLib.sol";
import {NameRegistry} from "../src/NameRegistry.sol";
import "forge-std/console.sol";

/// @title GenesisEthscriptions
/// @notice Temporary contract that extends Ethscriptions with genesis-specific creation
/// @dev Used only during genesis, then replaced with the real Ethscriptions contract
contract GenesisEthscriptions is Ethscriptions {

    /// @notice Store a genesis ethscription ID for later event emission
    /// @dev Internal function only used during genesis setup
    /// @param ethscriptionId The ethscription ID (L1 tx hash) to store
    function _storePendingGenesisEvent(bytes32 ethscriptionId) internal {
        pendingGenesisEvents.push(ethscriptionId);
    }

    /// @notice Create an ethscription with all values explicitly set for genesis
    function createGenesisEthscription(
        CreateEthscriptionParams calldata params,
        address creator,
        uint256 createdAt,
        uint64 l1BlockNumber,
        bytes32 l1BlockHash
    ) public returns (uint256 tokenId) {
        require(creator != address(0), "Invalid creator");
        require(ethscriptions[params.ethscriptionId].creator == address(0), "Ethscription already exists");

        // Check protocol uniqueness using content URI hash
        if (firstEthscriptionByContentUri[params.contentUriSha] != bytes32(0)) {
            if (!params.esip6) revert DuplicateContentUri();
        }

        // Store content and get content hash (reusing parent's helper)
        bytes32 contentHash = _storeContent(params.content);

        // Mark content URI as used by storing this ethscription's tx hash
        firstEthscriptionByContentUri[params.contentUriSha] = params.ethscriptionId;

        // Store metadata (mimetype, protocol, operation)
        // Genesis ethscriptions have no protocol parameters
        bytes32 metaRef = MetaStoreLib.store(
            params.mimetype,
            params.protocolParams.protocolName,
            params.protocolParams.operation,
            metadataStorage
        );

        // Set all values including genesis-specific ones
        ethscriptions[params.ethscriptionId] = EthscriptionStorage({
            // Fixed-size fields
            contentUriSha: params.contentUriSha,
            contentHash: contentHash,
            l1BlockHash: l1BlockHash,
            // Packed slot 3
            creator: creator,
            createdAt: uint48(createdAt),
            l1BlockNumber: uint48(l1BlockNumber),
            // Metadata reference
            metaRef: metaRef,
            // Packed slot N
            initialOwner: params.initialOwner,
            ethscriptionNumber: uint48(totalSupply()),
            esip6: params.esip6,
            // Packed slot N+1
            previousOwner: creator,
            l2BlockNumber: 0  // Genesis ethscriptions have no L2 block
        });

        // Use ethscription number as token ID
        tokenId = totalSupply();

        // Store the mapping from token ID to ethscription ID
        tokenIdToEthscriptionId[tokenId] = params.ethscriptionId;

        // Token count is automatically tracked by enumerable's _update

        // If initial owner is zero (burned), mint to creator then burn
        if (params.initialOwner == address(0)) {
            _mint(creator, tokenId);
            _transfer(creator, address(0), tokenId);
        } else {
            _mint(params.initialOwner, tokenId);
        }

        // Store the transaction hash so all events can be emitted later
        // The emission logic in _emitPendingGenesisEvents will figure out
        // what events to emit based on the ethscription data
        _storePendingGenesisEvent(params.ethscriptionId);

        // Skip token handling for genesis
    }
}

/// @title L2Genesis
/// @notice Generates the minimal genesis state for the L2 network.
///         Sets up L1Block contract, L2ToL1MessagePasser, ProxyAdmin, and proxy infrastructure.

contract L2Genesis is Script {
    uint256 constant PRECOMPILE_COUNT = 256;
    uint256 internal constant PREDEPLOY_COUNT = 2048;
    
    string constant GENESIS_JSON_FILE = "genesis-allocs.json";

    L2GenesisConfig.Config config;

    /// @notice Main entry point for genesis generation
    function run() public {
        runWithoutDump();
        
        // Dump state and prettify with jq
        vm.dumpState(GENESIS_JSON_FILE);
        
        // Use FFI to prettify and sort the JSON keys
        string[] memory inputs = new string[](3);
        inputs[0] = "sh";
        inputs[1] = "-c";
        // Use block timestamp for unique temp file
        string memory tempFile = string.concat("/tmp/genesis-", vm.toString(block.timestamp), ".json");
        inputs[2] = string.concat("jq --sort-keys . ", GENESIS_JSON_FILE, " > ", tempFile, " && mv ", tempFile, " ", GENESIS_JSON_FILE);
        vm.ffi(inputs);
    }
    
    function runWithoutDump() public {
        // Load configuration
        config = L2GenesisConfig.getConfig();

        // Use a deployer account for genesis setup
        address deployer = Predeploys.DEPOSITOR_ACCOUNT;
        vm.startPrank(deployer);
        vm.chainId(config.l2ChainID);

        // Set up genesis state
        dealEthToPrecompiles();
        setOPStackPredeploys();
        setEthscriptionsPredeploys();  // This now includes createGenesisEthscriptions()
        deployMulticall3();
        
        // Fund dev accounts if enabled
        if (config.fundDevAccounts) {
            fundDevAccounts();
        }

        // Clean up deployer
        vm.stopPrank();
        vm.deal(deployer, 0);
        vm.resetNonce(deployer);
    }

    /// @notice Give all precompiles 1 wei (required for EVM compatibility)
    function dealEthToPrecompiles() internal {
        for (uint256 i; i < PRECOMPILE_COUNT; i++) {
            vm.deal(address(uint160(i)), 1);
        }
    }

    /// @notice Set up OP Stack predeploys with proxies
    function setOPStackPredeploys() internal {
        bytes memory proxyCode = vm.getDeployedCode("Proxy.sol:Proxy");
        // Deploy proxies at sequential addresses starting from 0x42...00
        uint160 prefix = uint160(0x420) << 148;
        
        for (uint256 i = 0; i < PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));
            
            // Deploy proxy
            vm.etch(addr, proxyCode);
            
            vm.setNonce(addr, 1);
            
            // Set admin to ProxyAdmin
            setProxyAdminSlot(addr, Predeploys.PROXY_ADMIN);
            
            bool isSupportedPredeploy = addr == Predeploys.L1_BLOCK_ATTRIBUTES ||
                addr == Predeploys.L2_TO_L1_MESSAGE_PASSER ||
                addr == Predeploys.PROXY_ADMIN;
            
            if (isSupportedPredeploy) {
                address implementation = Predeploys.predeployToCodeNamespace(addr);
                setImplementation(addr, implementation);
            }
        }
        
        // Now set implementations for OP Stack contracts
        setL1Block();
        setL2ToL1MessagePasser();
        setProxyAdmin();
    }
    
    /// @notice Set up Ethscriptions system contracts
    function setEthscriptionsPredeploys() internal {
        // Ensure proxies exist across the full 0x330… namespace, mirroring OP's approach
        bytes memory proxyCode = vm.getDeployedCode("Proxy.sol:Proxy");
        uint160 prefix = uint160(0x330) << 148;

        for (uint256 i = 0; i < PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));

            // Deploy proxy shell and prime nonce for deterministic CREATEs
            vm.etch(addr, proxyCode);
            vm.setNonce(addr, 1);
            setProxyAdminSlot(addr, Predeploys.PROXY_ADMIN);

            // Wire up implementations for the Ethscriptions predeploys that use proxies
            bool isProxiedContract = addr == Predeploys.ETHSCRIPTIONS ||
                addr == Predeploys.ERC20_FIXED_DENOMINATION_MANAGER ||
                addr == Predeploys.ETHSCRIPTIONS_PROVER ||
                addr == Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER ||
                addr == Predeploys.NAME_REGISTRY;
            if (isProxiedContract) {
                address impl = Predeploys.predeployToCodeNamespace(addr);
                setImplementation(addr, impl);
            }
        }

        // Set implementation code for non-ETHSCRIPTIONS contracts now
        _setImplementationCodeNamed(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER, "ERC20FixedDenominationManager");
        _setImplementationCodeNamed(Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER, "ERC721EthscriptionsCollectionManager");
        _setImplementationCodeNamed(Predeploys.ETHSCRIPTIONS_PROVER, "EthscriptionsProver");
        // Templates and direct deploys live directly at their addresses (no proxy wrapping)
        _setCodeAt(Predeploys.ERC20_FIXED_DENOMINATION_IMPLEMENTATION, "ERC20FixedDenomination");
        _setCodeAt(Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_IMPLEMENTATION, "ERC721EthscriptionsCollection");
        _setCodeAt(Predeploys.NAME_REGISTRY, "NameRegistry");

        // Create genesis Ethscriptions (writes via proxy to proxy storage)
        createGenesisEthscriptions();

        // Register protocol handlers via the Ethscriptions proxy
        registerProtocolHandlers();
    }

    /// @notice Register protocol handlers with the Ethscriptions contract
    function registerProtocolHandlers() internal {
        Ethscriptions ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

        ethscriptions.registerProtocol("erc-20-fixed-denomination", Predeploys.ERC20_FIXED_DENOMINATION_MANAGER);
        console.log("Registered erc-20-fixed-denomination protocol handler:", Predeploys.ERC20_FIXED_DENOMINATION_MANAGER);

        ethscriptions.registerProtocol("erc-721-ethscriptions-collection", Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER);
        console.log("Registered erc-721-ethscriptions-collection protocol handler:", Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER);

        ethscriptions.registerProtocol("word-domains", Predeploys.NAME_REGISTRY);
        console.log("Registered word-domains protocol handler:", Predeploys.NAME_REGISTRY);
    }

    /// @notice Deploy L1Block contract (stores L1 block attributes)
    function setL1Block() internal {
        _setImplementationCode(Predeploys.L1_BLOCK_ATTRIBUTES);
    }

    /// @notice Deploy L2ToL1MessagePasser contract
    function setL2ToL1MessagePasser() internal {
        _setImplementationCode(Predeploys.L2_TO_L1_MESSAGE_PASSER);
    }

    /// @notice Deploy ProxyAdmin contract
    function setProxyAdmin() internal {
        address impl = _setImplementationCode(Predeploys.PROXY_ADMIN);

        // Set the owner
        bytes32 ownerSlot = bytes32(0); // Owner is typically stored at slot 0
        vm.store(Predeploys.PROXY_ADMIN, ownerSlot, bytes32(uint256(uint160(config.proxyAdminOwner))));
        vm.store(impl, ownerSlot, bytes32(uint256(uint160(config.proxyAdminOwner))));
    }

    /// @notice Deploy Multicall3 contract
    function deployMulticall3() internal {
        console.log("Deploying Multicall3 at", Predeploys.MultiCall3);
        vm.etch(Predeploys.MultiCall3, Predeploys.MultiCall3Code);
        // Set nonce to 1 for consistency with other predeploys
        vm.setNonce(Predeploys.MultiCall3, 1);
    }

    /// @notice Fund development accounts with ETH
    function fundDevAccounts() internal {
        address[] memory accounts = L2GenesisConfig.getDevAccounts();
        uint256 amount = L2GenesisConfig.getDevAccountFundAmount();
        
        for (uint256 i = 0; i < accounts.length; i++) {
            vm.deal(accounts[i], amount);
        }
    }

    /// @notice Create genesis Ethscriptions from JSON data
    function createGenesisEthscriptions() internal {
        console.log("Creating genesis Ethscriptions...");
        
        // Read the JSON file
        string memory json = vm.readFile("script/genesisEthscriptions.json");
        
        // Parse metadata
        uint256 totalCount = abi.decode(vm.parseJson(json, ".metadata.totalCount"), (uint256));
        console.log("Found", totalCount, "genesis Ethscriptions");
        
        // Use the Ethscriptions proxy address and its implementation code-namespace address
        address ethscriptionsProxy = Predeploys.ETHSCRIPTIONS;
        address implAddr = Predeploys.predeployToCodeNamespace(ethscriptionsProxy);

        // Temporarily etch GenesisEthscriptions at the implementation address
        vm.etch(implAddr, type(GenesisEthscriptions).runtimeCode);

        // Call through the proxy using the GenesisEthscriptions interface
        GenesisEthscriptions genesisContract = GenesisEthscriptions(ethscriptionsProxy);

        // Process each ethscription (this will increment the nonce as SSTORE2 contracts are deployed)
        for (uint256 i = 0; i < totalCount; i++) {
            _createSingleGenesisEthscription(json, i, genesisContract);
        }

        console.log("Created", totalCount, "genesis Ethscriptions");

        // Overwrite the implementation bytecode with the real Ethscriptions
        // Do not reset nonce on the proxy; we only swap the implementation code
        _setImplementationCodeNamed(Predeploys.ETHSCRIPTIONS, "Ethscriptions");
    }

    /// @notice Helper to create a single genesis ethscription
    function _createSingleGenesisEthscription(
        string memory json,
        uint256 index,
        GenesisEthscriptions genesisContract
    ) internal {
        if (!vm.envOr("PERFORM_GENESIS_IMPORT", true)) {
            return;
        }
        
        string memory basePath = string.concat(".ethscriptions[", vm.toString(index), "]");
        
        // Parse all data needed
        address creator = vm.parseJsonAddress(json, string.concat(basePath, ".creator"));
        address initialOwner = vm.parseJsonAddress(json, string.concat(basePath, ".initial_owner"));
        
        console.log("Processing ethscription", index);
        console.log("  Creator:", creator);
        console.log("  Initial owner:", initialOwner);
        
        uint256 blockTimestamp = vm.parseJsonUint(json, string.concat(basePath, ".block_timestamp"));
        uint256 blockNumber = vm.parseJsonUint(json, string.concat(basePath, ".block_number"));
        bytes32 blockHash = vm.parseJsonBytes32(json, string.concat(basePath, ".block_blockhash"));
        
        // Create params struct with parsed data from JSON
        // The JSON already has all the properly processed data
        Ethscriptions.CreateEthscriptionParams memory params;
        params.ethscriptionId = vm.parseJsonBytes32(json, string.concat(basePath, ".transaction_hash"));
        params.contentUriSha = vm.parseJsonBytes32(json, string.concat(basePath, ".content_uri_hash"));
        params.initialOwner = initialOwner;
        params.content = vm.parseJsonBytes(json, string.concat(basePath, ".content"));
        params.mimetype = vm.parseJsonString(json, string.concat(basePath, ".mimetype"));
        params.esip6 = vm.parseJsonBool(json, string.concat(basePath, ".esip6"));
        params.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "",
            operation: "",
            data: ""
        });
        
        // Create the genesis ethscription with all values
        genesisContract.createGenesisEthscription(
            params,
            creator,
            blockTimestamp,
            uint64(blockNumber),
            blockHash
        );
    }

    // ============ Helper Functions ============
    
    /// @notice Disable initializers on a contract to prevent initialization
    function _disableInitializers(address _addr) internal {
        vm.store(_addr, Constants.INITIALIZABLE_STORAGE, bytes32(uint256(0x000000000000000000000000000000000000000000000000ffffffffffffffff)));
    }
    
    /// @notice Set implementation bytecode for a given predeploy using an explicit contract name
    function _setImplementationCodeNamed(address _predeploy, string memory _name) internal returns (address impl) {
        impl = Predeploys.predeployToCodeNamespace(_predeploy);
        bytes memory code = vm.getDeployedCode(string.concat(_name, ".sol:", _name));
        console.log("Setting implementation code for", _predeploy, "to", impl);
        
        _disableInitializers(impl);
        
        vm.etch(impl, code);
    }

    /// @notice Etch contract bytecode directly at a target address (used for non-proxy templates)
    function _setCodeAt(address _addr, string memory _name) internal {
        bytes memory code = vm.getDeployedCode(string.concat(_name, ".sol:", _name));
        _disableInitializers(_addr);
        vm.etch(_addr, code);
    }

    /// @notice Set the admin of a proxy contract
    function setProxyAdminSlot(address proxy, address admin) internal {
        // EIP-1967 admin slot
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        vm.store(proxy, adminSlot, bytes32(uint256(uint160(admin))));
    }

    /// @notice Set the implementation of a proxy contract
    function setImplementation(address proxy, address implementation) internal {
        // EIP-1967 implementation slot
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        vm.store(proxy, implSlot, bytes32(uint256(uint160(implementation))));
    }
    
    /// @notice Sets the bytecode in state
    function _setImplementationCode(address _addr) internal returns (address) {
        string memory cname = getName(_addr);
        address impl = Predeploys.predeployToCodeNamespace(_addr);
        vm.etch(impl, vm.getDeployedCode(string.concat(cname, ".sol:", cname)));
        return impl;
    }
    
    function getName(address _addr) internal pure returns (string memory ret) {
        // OP Stack predeploys
        if (_addr == Predeploys.L1_BLOCK_ATTRIBUTES) {
            ret = "L1Block";
        } else if (_addr == Predeploys.L2_TO_L1_MESSAGE_PASSER) {
            ret = "L2ToL1MessagePasser";
        } else if (_addr == Predeploys.PROXY_ADMIN) {
            ret = "ProxyAdmin";
        }
    }

}
