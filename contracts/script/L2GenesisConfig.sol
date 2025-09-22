// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Constants } from "../src/libraries/Constants.sol";

/// @title L2GenesisConfig
/// @notice Configuration for L2 Genesis state generation
library L2GenesisConfig {
    /// @notice Configuration struct for L2 Genesis
    struct Config {
        uint256 l1ChainID;
        uint256 l2ChainID;
        address proxyAdminOwner;
        bool fundDevAccounts;
    }

    /// @notice Returns the default configuration for L2 Genesis
    function getConfig() internal pure returns (Config memory) {
        return Config({
            l1ChainID: 1, // Ethereum mainnet
            l2ChainID: 0xeeee, // Custom L2 chain ID
            proxyAdminOwner: Constants.DEPOSITOR_ACCOUNT, // Default admin
            fundDevAccounts: false
        });
    }

    /// @notice List of development accounts to fund (if enabled)
    function getDevAccounts() internal pure returns (address[] memory) {
        address[] memory accounts = new address[](5);
        accounts[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Hardhat account 0
        accounts[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Hardhat account 1
        accounts[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Hardhat account 2
        accounts[3] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Hardhat account 3
        accounts[4] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // Hardhat account 4
        return accounts;
    }

    /// @notice Amount of ETH to fund each dev account with
    function getDevAccountFundAmount() internal pure returns (uint256) {
        return 10000 ether;
    }
}