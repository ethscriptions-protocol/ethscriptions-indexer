// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Predeploys
/// @notice Defines all predeploy addresses for the L2 chain
library Predeploys {
    // ============ OP Stack Predeploys ============
    
    /// @notice L1Block predeploy (stores L1 block information)
    address constant L1_BLOCK_ATTRIBUTES = 0x4200000000000000000000000000000000000015;
    
    /// @notice L2ToL1MessagePasser predeploy (for L2->L1 messages)
    address constant L2_TO_L1_MESSAGE_PASSER = 0x4200000000000000000000000000000000000016;
    
    /// @notice ProxyAdmin predeploy (manages all proxy upgrades)
    address constant PROXY_ADMIN = 0x4200000000000000000000000000000000000018;
    
    // ============ Ethscriptions System Predeploys ============
    // Using 0xee namespace for Ethscriptions contracts
    
    /// @notice Ethscriptions NFT contract
    address constant ETHSCRIPTIONS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    /// @notice TokenManager for ERC20 token creation
    address constant TOKEN_MANAGER = 0x3300000000000000000000000000000000000002;
    
    /// @notice EthscriptionsProver for L1 provability
    address constant ETHSCRIPTIONS_PROVER = 0x3300000000000000000000000000000000000003;
    
    /// @notice EthscriptionsERC20 template for cloning
    address constant ERC20_TEMPLATE = 0x3300000000000000000000000000000000000004;
    
    // ============ Helper Functions ============
    
    /// @notice Returns true if the address is a predeploy
    function isPredeployNamespace(address _addr) internal pure returns (bool) {
        return uint160(_addr) >> 11 == uint160(0x4200000000000000000000000000000000000000) >> 11;
    }
    
    /// @notice Converts a predeploy address to its code namespace equivalent
    function predeployToCodeNamespace(address _addr) internal pure returns (address) {
        require(
            isPredeployNamespace(_addr), 
            "Predeploys: can only derive code-namespace address for predeploy addresses"
        );
        return address(
            uint160(uint256(uint160(_addr)) & 0xffff | uint256(uint160(0xc0D3C0d3C0d3C0D3c0d3C0d3c0D3C0d3c0d30000)))
        );
    }
}