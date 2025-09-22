// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "./libraries/Predeploys.sol";
import "./EthscriptionsProver.sol";

contract EthscriptionsERC20 is ERC20Upgradeable, ERC20CappedUpgradeable {
    address public constant tokenManager = Predeploys.TOKEN_MANAGER;
    EthscriptionsProver public constant prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);
    
    bytes32 public deployTxHash; // The ethscription hash that deployed this token
    
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        bytes32 deployTxHash_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Capped_init(cap_);
        deployTxHash = deployTxHash_;
    }
    
    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "Only TokenManager");
        _;
    }
    
    function mint(address to, uint256 amount) external onlyTokenManager {
        _mint(to, amount);
    }
    
    function forceTransfer(address from, address to, uint256 amount) external onlyTokenManager {
        // This is used by TokenManager to shadow NFT transfers
        // It bypasses approval checks since it's a system-level transfer
        _transfer(from, to, amount);
    }
    
    // Override transfer functions to prevent user-initiated transfers
    // Only the TokenManager can move tokens via forceTransfer
    function transfer(address, uint256) public pure override returns (bool) {
        revert("Transfers only allowed via Ethscriptions NFT");
    }
    
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("Transfers only allowed via Ethscriptions NFT");
    }
    
    function approve(address, uint256) public pure override returns (bool) {
        revert("Approvals not allowed");
    }
    
    function increaseAllowance(address, uint256) public pure returns (bool) {
        revert("Approvals not allowed");
    }
    
    function decreaseAllowance(address, uint256) public pure returns (bool) {
        revert("Approvals not allowed");
    }
    
    // Required overrides for multiple inheritance
    function _update(address from, address to, uint256 value) 
        internal 
        override(ERC20Upgradeable, ERC20CappedUpgradeable) 
    {
        super._update(from, to, value);
        
        // Automatically prove token balances after any update including burns
        // For transfers: prove both from and to
        // For mints (from == address(0)): only prove to
        // For burns (to == address(0)): only prove from
        if (from != address(0)) {
            prover.proveTokenBalance(from, deployTxHash);
        }
        if (to != address(0)) {
            prover.proveTokenBalance(to, deployTxHash);
        }
    }
}