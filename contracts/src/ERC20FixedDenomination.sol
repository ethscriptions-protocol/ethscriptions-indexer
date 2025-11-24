// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC404NullOwnerCappedUpgradeable.sol";
import "./libraries/Predeploys.sol";
import "./Ethscriptions.sol";
import "./ERC20FixedDenominationManager.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

/// @title ERC20FixedDenomination
/// @notice Hybrid ERC-20/ERC-721 proxy whose supply is managed in fixed denominations by the manager contract.
/// @dev User-initiated transfers/approvals are disabled; only the manager can mutate balances.
///      Each NFT represents a fixed denomination amount (e.g., 1 NFT = mintAmount tokens).
contract ERC20FixedDenomination is ERC404NullOwnerCappedUpgradeable {
    using LibString for *;

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @notice The manager contract that controls this token
    address public constant manager = Predeploys.ERC20_FIXED_DENOMINATION_MANAGER;

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @notice The ethscription ID that deployed this token
    bytes32 public deployEthscriptionId;

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyManager();
    error TransfersOnlyViaEthscriptions();
    error ApprovalsNotAllowed();

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyManager() {
        if (msg.sender != manager) revert OnlyManager();
        _;
    }

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        uint256 mintAmount_,
        bytes32 deployEthscriptionId_
    ) external initializer {
        // cap_ is maxSupply * 10**18
        // mintAmount_ is the denomination amount (e.g., 1000 for 1000 tokens per NFT)
        // units is mintAmount_ * 10**18 (amount of wei per NFT)

        uint256 units_ = mintAmount_ * (10 ** decimals());

        __ERC404_init(name_, symbol_, cap_, units_);
        deployEthscriptionId = deployEthscriptionId_;
    }

    /// @notice Historical accessor for the fixed denomination (whole tokens per NFT)
    function mintAmount() public view returns (uint256) {
        return denomination();
    }

    /// @notice Mint one fixed-denomination note (manager only)
    /// @param to The recipient address
    /// @param nftId The specific NFT ID to mint (the mintId)
    function mint(address to, uint256 nftId) external onlyManager {
        // Mint the ERC20 tokens without triggering NFT creation
        _mintERC20WithoutNFT(to, units());
        _mintERC721(to, nftId);
    }

    /// @notice Force transfer the fixed-denomination NFT and its synced ERC20 lot (manager only)
    /// @param from The sender address
    /// @param to The recipient address
    /// @param nftId The NFT ID to transfer (the mintId)
    function forceTransfer(address from, address to, uint256 nftId) external onlyManager {
        // Transfer the ERC20 tokens without triggering dynamic NFT logic
        _transferERC20(from, to, units());

        // Transfer the specific NFT using the proper function
        _transferERC721(from, to, nftId);
    }

    // =============================================================
    //                DISABLED ERC20/721 FUNCTIONS
    // =============================================================

    /// @notice Regular transfers are disabled - only manager can transfer
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice Regular transferFrom is disabled - only manager can transfer
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice Approvals are disabled
    function approve(address, uint256) public pure override returns (bool) {
        revert ApprovalsNotAllowed();
    }

    /// @notice ERC721 approvals are disabled
    function erc721Approve(address, uint256) public pure override {
        revert ApprovalsNotAllowed();
    }

    /// @notice ERC20 approvals are disabled
    function erc20Approve(address, uint256) public pure override returns (bool) {
        revert ApprovalsNotAllowed();
    }

    /// @notice SetApprovalForAll is disabled
    function setApprovalForAll(address, bool) public pure override {
        revert ApprovalsNotAllowed();
    }

    /// @notice ERC721 transferFrom is disabled
    function erc721TransferFrom(address, address, uint256) public pure override {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice ERC20 transferFrom is disabled
    function erc20TransferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice Safe transfers are disabled
    function safeTransferFrom(address, address, uint256) public pure override {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice Safe transfers with data are disabled
    function safeTransferFrom(address, address, uint256, bytes memory) public pure override {
        revert TransfersOnlyViaEthscriptions();
    }

    // =============================================================
    //                     TOKEN URI
    // =============================================================

    /// @notice Returns metadata URI for NFT tokens
    /// @dev Returns a data URI with JSON metadata fetched from the main Ethscriptions contract
    function tokenURI(uint256 mintId) public view virtual override returns (string memory) {
        ownerOf(mintId); // reverts on invalid / nonexistent

        // Get the ethscriptionId for this mintId from the manager
        ERC20FixedDenominationManager mgr = ERC20FixedDenominationManager(manager);
        bytes32 ethscriptionId = mgr.getMintEthscriptionId(deployEthscriptionId, mintId);

        // Get the ethscription data from the main contract
        Ethscriptions ethscriptionsContract = Ethscriptions(Predeploys.ETHSCRIPTIONS);
        Ethscriptions.Ethscription memory ethscription = ethscriptionsContract.getEthscription(ethscriptionId, false);
        (string memory mediaType, string memory mediaUri) = ethscriptionsContract.getMediaUri(ethscriptionId);

        // Convert ethscriptionId to hex string (0x prefixed)
        string memory ethscriptionIdHex = uint256(ethscriptionId).toHexString(32);

        // Build the JSON metadata
        string memory jsonStart = string.concat(
            '{"name":"', name(), ' Token #', mintId.toString(), '"',
            ',"description":"Fixed denomination token for ', mintAmount().toString(), ' ', symbol(), ' tokens"'
        );

        // Add ethscription ID and number
        string memory ethscriptionFields = string.concat(
            ',"ethscription_id":"', ethscriptionIdHex, '"',
            ',"ethscription_number":', ethscription.ethscriptionNumber.toString()
        );

        // Add media field
        string memory mediaField = string.concat(
            ',"', mediaType, '":"', mediaUri, '"'
        );

        string memory json = string.concat(jsonStart, ethscriptionFields, mediaField, '}');

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

}
