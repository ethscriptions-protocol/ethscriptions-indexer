// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Minimal ERC-721 implementation that supports null address ownership.
 * Unlike standard ERC-721, tokens can be owned by address(0) and still exist.
 * This is required for Ethscriptions protocol compatibility.
 *
 * Simplifications from standard ERC-721:
 * - No safe transfer functionality (no onERC721Received checks)
 * - No approval functionality (approve, getApproved, setApprovalForAll removed)
 * - No name/symbol storage (must be overridden by child)
 * - No tokenURI implementation (must be overridden by child)
 * - No burn function (transfer to address(0) instead)
 * - Keeps only core transfer and ownership logic
 */
abstract contract ERC721EthscriptionsUpgradeable is Initializable, ContextUpgradeable, ERC165Upgradeable, IERC721, IERC721Metadata, IERC721Errors {
    using Strings for uint256;

    /// @custom:storage-location erc7201:ethscriptions.storage.ERC721
    struct ERC721Storage {
        // Token owners (can be address(0) for null-owned tokens)
        mapping(uint256 tokenId => address) _owners;
        // Balance per address (including null address)
        mapping(address owner => uint256) _balances;

        // === Ethscriptions-specific storage ===
        // Explicit existence tracking (true = token exists)
        mapping(uint256 tokenId => bool) _existsFlag;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC721.ethscriptions")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC721StorageLocation = 0x03f081da1bf59345b57bd2323b19ea3e2315141ee27bd283a32089733412b400;

    function _getERC721Storage() private pure returns (ERC721Storage storage $) {
        assembly {
            $.slot := ERC721StorageLocation
        }
    }

    /**
     * @dev Initializes the contract.
     */
    function __ERC721_init() internal onlyInitializing {
        __ERC721_init_unchained();
    }

    function __ERC721_init_unchained() internal onlyInitializing {
        // No initialization needed for simplified version
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165Upgradeable, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     * Modified to support null address balance queries.
     */
    function balanceOf(address owner) public view virtual returns (uint256) {
        ERC721Storage storage $ = _getERC721Storage();
        return $._balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _requireOwned(tokenId);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     * Must be overridden by child contract.
     */
    function name() public view virtual returns (string memory);

    /**
     * @dev See {IERC721Metadata-symbol}.
     * Must be overridden by child contract.
     */
    function symbol() public view virtual returns (string memory);

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     * Must be overridden by child contract.
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory);

    /**
     * @dev Approval functions removed - not needed for Ethscriptions.
     * These can be added back in child contracts if needed.
     */
    function approve(address, uint256) public virtual {
        revert("Approvals not supported");
    }

    function getApproved(uint256) public view virtual returns (address) {
        return address(0);
    }

    function setApprovalForAll(address, bool) public virtual {
        revert("Approvals not supported");
    }

    function isApprovedForAll(address, address) public view virtual returns (bool) {
        return false;
    }

    /**
     * @dev See {IERC721-transferFrom}.
     * Modified to allow transfers to address(0) (not burns, just transfers).
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        // Removed check for to == address(0) to allow null transfers
        address previousOwner = _update(to, tokenId, _msgSender());
        if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /**
     * @dev Safe transfer functions removed - not needed for Ethscriptions.
     */
    function safeTransferFrom(address, address, uint256) public virtual {
        revert("Safe transfers not supported");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public virtual {
        revert("Safe transfers not supported");
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist.
     * Modified to check existence flag instead of owner == address(0).
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        ERC721Storage storage $ = _getERC721Storage();
        return $._owners[tokenId]; // May be address(0) for null-owned
    }

    /**
     * @dev Simplified authorization - only owner can transfer.
     */
    function _checkAuthorized(address owner, address spender, uint256 tokenId) internal view virtual {
        ERC721Storage storage $ = _getERC721Storage();

        if (!$._existsFlag[tokenId]) {
            revert ERC721NonexistentToken(tokenId);
        }

        // Only the owner can transfer (no approvals)
        // Since spender (msg.sender) can never be address(0), null-owned tokens are automatically protected
        if (owner != spender) {
            revert ERC721InsufficientApproval(spender, tokenId);
        }
    }

    /**
     * @dev Transfers `tokenId` from its current owner to `to`.
     * Modified to handle null address as a valid owner.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual returns (address) {
        ERC721Storage storage $ = _getERC721Storage();

        bool existed = $._existsFlag[tokenId];
        address from = _ownerOf(tokenId);

        // Perform authorization check if needed
        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        // Handle transfer/mint
        if (existed) {
            // This is a transfer - update from balance
            $._balances[from] -= 1;
        } else {
            // This is a mint - mark as existing
            $._existsFlag[tokenId] = true;
        }

        // Update to balance
        $._balances[to] += 1;

        $._owners[tokenId] = to;
        emit Transfer(from, to, tokenId);

        return from;
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     * Routes through _update to ensure consistent behavior.
     * Does not allow minting directly to address(0) - mint then transfer instead.
     */
    function _mint(address to, uint256 tokenId) internal {
        ERC721Storage storage $ = _getERC721Storage();

        // Check if token already exists
        if ($._existsFlag[tokenId]) {
            revert ERC721InvalidSender(address(0));
        }

        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }

        // Mint the token via _update
        _update(to, tokenId, address(0));
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     * Modified to allow transfers to address(0) (not burns).
     */
    function _transfer(address from, address to, uint256 tokenId) internal {
        address previousOwner = _update(to, tokenId, address(0));
        if (!_tokenExists(tokenId)) {
            revert ERC721NonexistentToken(tokenId);
        } else if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /**
     * @dev Reverts if the `tokenId` doesn't have a current owner (it hasn't been minted, or it has been burned).
     * Modified to use existence flag instead of owner == address(0).
     */
    function _requireOwned(uint256 tokenId) internal view returns (address) {
        ERC721Storage storage $ = _getERC721Storage();
        if (!$._existsFlag[tokenId]) {
            revert ERC721NonexistentToken(tokenId);
        }
        return $._owners[tokenId]; // May be address(0) for null-owned
    }

    /**
     * @dev Returns whether `tokenId` exists.
     * Tokens start existing when they are minted (`_mint`).
     */
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        ERC721Storage storage $ = _getERC721Storage();
        return $._existsFlag[tokenId];
    }
}