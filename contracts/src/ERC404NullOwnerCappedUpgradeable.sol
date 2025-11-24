// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import "./interfaces/IERC404.sol";
import "./lib/DoubleEndedQueue.sol";

/// @title ERC404NullOwnerCappedUpgradeable
/// @notice Hybrid ERC20/ERC721 implementation with null owner support, supply cap, and upgradeability
/// @dev Combines ERC404 NFT functionality with null owner semantics and EIP-7201 namespaced storage
abstract contract ERC404NullOwnerCappedUpgradeable is
    Initializable,
    ContextUpgradeable,
    IERC165,
    IERC20,
    IERC20Metadata,
    IERC20Errors,
    IERC404
{
    using DoubleEndedQueue for DoubleEndedQueue.Uint256Deque;

    struct TokenData {
        address owner; // current owner (can be address(0) for null-owner)
        uint88 index; // position in owned[owner] array
        bool exists; // true if the token has been minted
    }

    // =============================================================
    //                        STORAGE STRUCT
    // =============================================================

    /// @custom:storage-location erc7201:ethscriptions.storage.ERC404NullOwnerCapped
    struct TokenStorage {
        // === ERC20 State ===
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
        uint256 totalSupply;
        uint256 cap;

        // === ERC404 NFT State ===
        DoubleEndedQueue.Uint256Deque storedERC721Ids;
        mapping(address => uint256[]) owned;
        mapping(uint256 => TokenData) tokens;
        mapping(uint256 => address) getApproved;
        mapping(address => mapping(address => bool)) isApprovedForAll;
        mapping(address => bool) erc721TransferExempt;
        uint256 minted; // Number of NFTs minted
        uint256 units; // Units for NFT minting (e.g., 1000 * 10^18)
        uint256 initialChainId;
        bytes32 initialDomainSeparator;
        mapping(address => uint256) nonces;

        // === Metadata ===
        string name;
        string symbol;
    }

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @dev Unique storage slot for EIP-7201 namespaced storage
    /// keccak256(abi.encode(uint256(keccak256("ethscriptions.storage.ERC404NullOwnerCapped")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x8a0c9d8e5f7b3a2c1d4e6f8a9b7c5d3e2f1a4b6c8d9e7f5a3b2c1d4e6f8a9b00;

    /// @dev Constant for token id encoding
    uint256 public constant ID_ENCODING_PREFIX = 1 << 255;

    // =============================================================
    //                         EVENTS
    // =============================================================

    // ERC20 Events are inherited from IERC20 (Transfer, Approval)

    // ERC721 Events (using different names to avoid conflicts with ERC20)
    event ERC721Transfer(address indexed from, address indexed to, uint256 indexed id);
    event ERC721Approval(address indexed owner, address indexed spender, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error UnsafeUpdate();
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);
    error ERC20InvalidCap(uint256 cap);
    error InvalidUnits(uint256 units);
    error NotImplemented();

    // =============================================================
    //                    STORAGE ACCESSOR
    // =============================================================

    function _getS() internal pure returns (TokenStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    // =============================================================
    //                      INITIALIZERS
    // =============================================================

    function __ERC404_init(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        uint256 units_
    ) internal onlyInitializing {
        __Context_init();
        __ERC404_init_unchained(name_, symbol_, cap_, units_);
    }

    function __ERC404_init_unchained(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        uint256 units_
    ) internal onlyInitializing {
        TokenStorage storage $ = _getS();

        if (cap_ == 0 || cap_ > ID_ENCODING_PREFIX - 1) {
            revert ERC20InvalidCap(cap_);
        }
        
        uint256 base = 10 ** decimals();
        if (units_ == 0 || units_ % base != 0) {
            revert InvalidUnits(units_);
        }

        $.name = name_;
        $.symbol = symbol_;
        $.cap = cap_;
        $.units = units_;
        $.initialChainId = block.chainid;
        $.initialDomainSeparator = _computeDomainSeparator();
    }

    // =============================================================
    //                    ERC20 METADATA VIEWS
    // =============================================================

    function name() public view virtual override(IERC404, IERC20Metadata) returns (string memory) {
        TokenStorage storage $ = _getS();
        return $.name;
    }

    function symbol() public view virtual override(IERC404, IERC20Metadata) returns (string memory) {
        TokenStorage storage $ = _getS();
        return $.symbol;
    }

    function decimals() public pure override(IERC404, IERC20Metadata) returns (uint8) {
        return 18;
    }

    // =============================================================
    //                     ERC20 VIEWS
    // =============================================================

    function totalSupply() public view virtual override(IERC404, IERC20) returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.totalSupply;
    }

    function balanceOf(address account) public view virtual override(IERC404, IERC20) returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.balances[account];
    }

    function allowance(address owner, address spender) public view virtual override(IERC404, IERC20) returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.allowances[owner][spender];
    }

    function erc20TotalSupply() public view virtual returns (uint256) {
        return totalSupply();
    }

    function erc20BalanceOf(address owner_) public view virtual returns (uint256) {
        return balanceOf(owner_);
    }

    // =============================================================
    //                     ERC721 VIEWS
    // =============================================================

    function erc721TotalSupply() public view virtual override(IERC404) returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.minted;
    }

    function erc721BalanceOf(address owner_) public view virtual override(IERC404) returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.owned[owner_].length;
    }

    function ownerOf(uint256 id_) public view virtual override(IERC404) returns (address) {
        if (!_isValidTokenId(id_)) {
            revert InvalidTokenId();
        }
        
        TokenStorage storage $ = _getS();
        TokenData storage t = $.tokens[id_];

        if (!t.exists) {
            revert NotFound();
        }

        return t.owner;
    }

    function owned(address owner_) public view virtual override(IERC404) returns (uint256[] memory) {
        TokenStorage storage $ = _getS();
        return $.owned[owner_];
    }

    function getApproved(uint256 id_) public view virtual returns (address) {
        TokenStorage storage $ = _getS();
        return $.getApproved[id_];
    }

    function isApprovedForAll(address owner_, address operator_) public view virtual override(IERC404) returns (bool) {
        TokenStorage storage $ = _getS();
        return $.isApprovedForAll[owner_][operator_];
    }

    function erc721TransferExempt(address account_) public view virtual override returns (bool) {
        TokenStorage storage $ = _getS();
        return $.erc721TransferExempt[account_];
    }

    // =============================================================
    //                       QUEUE VIEWS
    // =============================================================

    function getERC721QueueLength() public view virtual override returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.storedERC721Ids.length();
    }

    function getERC721TokensInQueue(
        uint256 start_,
        uint256 count_
    ) public view virtual override returns (uint256[] memory) {
        TokenStorage storage $ = _getS();
        uint256[] memory tokensInQueue = new uint256[](count_);

        for (uint256 i = start_; i < start_ + count_;) {
            tokensInQueue[i - start_] = $.storedERC721Ids.at(i);
            unchecked {
                ++i;
            }
        }

        return tokensInQueue;
    }

    // =============================================================
    //                      OTHER VIEWS
    // =============================================================

    function maxSupply() public view virtual returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.cap;
    }

    function units() public view virtual returns (uint256) {
        TokenStorage storage $ = _getS();
        return $.units;
    }

    /// @notice Fixed denomination in whole-token units (e.g., 1000 if 1 NFT = 1000 tokens)
    function denomination() public view virtual returns (uint256) {
        return units() / (10 ** decimals());
    }

    /// @notice tokenURI must be implemented by child contract
    function tokenURI(uint256 id_) public view virtual override(IERC404) returns (string memory);

    // =============================================================
    //                   ERC20 OPERATIONS
    // =============================================================

    function transfer(address, uint256) public pure virtual override(IERC404, IERC20) returns (bool) {
        revert NotImplemented();
    }

    function approve(address, uint256) public pure virtual override(IERC404, IERC20) returns (bool) {
        revert NotImplemented();
    }

    function transferFrom(address, address, uint256) public pure virtual override(IERC404, IERC20) returns (bool) {
        revert NotImplemented();
    }

    function erc20Approve(address, uint256) public pure virtual override returns (bool) {
        revert NotImplemented();
    }

    function erc20TransferFrom(address, address, uint256) public pure virtual override returns (bool) {
        revert NotImplemented();
    }

    // =============================================================
    //                   ERC721 OPERATIONS
    // =============================================================

    function erc721Approve(address, uint256) public pure virtual override {
        revert NotImplemented();
    }

    function erc721TransferFrom(address, address, uint256) public pure virtual override {
        revert NotImplemented();
    }

    function setApprovalForAll(address, bool) public pure virtual override {
        revert NotImplemented();
    }

    function safeTransferFrom(address, address, uint256) public pure virtual override {
        revert NotImplemented();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure virtual override {
        revert NotImplemented();
    }

    function setSelfERC721TransferExempt(bool) public pure virtual override {
        revert NotImplemented();
    }

    /// @notice Low-level ERC20 transfer
    /// @dev Supports transfers to/from address(0) for null owner support
    function _transferERC20(address from_, address to_, uint256 value_) internal virtual {
        TokenStorage storage $ = _getS();

        if (from_ == address(0)) {
            // Minting with cap enforcement
            uint256 newSupply = $.totalSupply + value_;
            if (newSupply > $.cap) {
                revert ERC20ExceededCap(newSupply, $.cap);
            }
            if (newSupply > ID_ENCODING_PREFIX) {
                revert MintLimitReached();
            }
            $.totalSupply = newSupply;
        } else {
            // Transfer
            uint256 fromBalance = $.balances[from_];
            if (fromBalance < value_) {
                revert ERC20InsufficientBalance(from_, fromBalance, value_);
            }
            unchecked {
                $.balances[from_] = fromBalance - value_;
            }
        }

        unchecked {
            $.balances[to_] += value_;
        }

        emit Transfer(from_, to_, value_);
    }

    /// @notice Transfer an ERC721 token
    function _transferERC721(address from_, address to_, uint256 id_) internal virtual {
        TokenStorage storage $ = _getS();
        TokenData storage t = $.tokens[id_];
        
        if (from_ != ownerOf(id_)) {
            revert Unauthorized();
        }
        
        if (from_ != address(0)) {
            // Clear approval
            delete $.getApproved[id_];

            // Remove from sender's owned list
            uint256 lastTokenId = $.owned[from_][$.owned[from_].length - 1];
            if (lastTokenId != id_) {
                uint256 updatedIndex = t.index;
                $.owned[from_][updatedIndex] = lastTokenId;
                $.tokens[lastTokenId].index = uint88(updatedIndex);
            }
            $.owned[from_].pop();
        }

        // Add to receiver's owned list (address(0) is a real owner in null-owner semantics)
        uint256 newIndex = $.owned[to_].length;
        if (newIndex > type(uint88).max) {
            revert OwnedIndexOverflow();
        }
        t.owner = to_;
        t.index = uint88(newIndex);
        $.owned[to_].push(id_);

        emit ERC721Transfer(from_, to_, id_);
    }

    /// @notice Mint ERC20 tokens without triggering NFT creation
    /// @dev Used for fixed denomination tokens where NFTs are explicitly minted
    function _mintERC20WithoutNFT(address to_, uint256 value_) internal virtual {
        // Direct ERC20 mint without NFT logic (cap enforced in _transferERC20)
        _transferERC20(address(0), to_, value_);
    }

    /// @notice Mint a specific NFT with a given ID
    /// @dev Used for fixed denomination tokens to mint NFTs with specific mintIds
    function _mintERC721(address to_, uint256 nftId_) internal virtual {
        if (to_ == address(0)) {
            revert InvalidRecipient();
        }
        if (nftId_ == 0 || nftId_ >= ID_ENCODING_PREFIX - 1) {
            revert InvalidTokenId();
        }

        TokenStorage storage $ = _getS();

        // Add the ID_ENCODING_PREFIX to the provided ID
        uint256 id = ID_ENCODING_PREFIX + nftId_;

        TokenData storage t = $.tokens[id];

        // Check if this NFT already exists (including null-owner)
        if (t.exists) {
            revert AlreadyExists();
        }

        t.exists = true;
        _transferERC721(address(0), to_, id);

        // Increment minted supply counter
        $.minted++;
    }

    // =============================================================
    //                      HELPER FUNCTIONS
    // =============================================================

    function _isValidTokenId(uint256 id_) internal pure returns (bool) {
        return id_ > ID_ENCODING_PREFIX && id_ != type(uint256).max;
    }

    // =============================================================
    //                      ERC165 SUPPORT
    // =============================================================

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC404).interfaceId;
    }
    
  /// @notice Internal function to compute domain separator for EIP-2612 permits
    function _computeDomainSeparator() internal view virtual returns (bytes32) {
        return
        keccak256(
            abi.encode(
            keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            ),
            keccak256(bytes(name())),
            keccak256("1"),
            block.chainid,
            address(this)
            )
        );
    }
    
    function permit(
        address owner_,
        address spender_,
        uint256 value_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) public virtual {
        revert NotImplemented();
    }

    /// @notice EIP-2612 domain separator
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        TokenStorage storage $ = _getS();
        return
            block.chainid == $.initialChainId
                ? $.initialDomainSeparator
                : _computeDomainSeparator();
    }
}
