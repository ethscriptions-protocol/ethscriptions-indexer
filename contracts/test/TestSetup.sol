// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Ethscriptions.sol";
import "../src/ERC20FixedDenominationManager.sol";
import "../src/ERC721EthscriptionsCollectionManager.sol";
import "../src/EthscriptionsProver.sol";
import "../src/ERC20FixedDenomination.sol";
import "../src/L2/L2ToL1MessagePasser.sol";
import "../src/L2/L1Block.sol";
import {Base64} from "solady/utils/Base64.sol";
import "../src/libraries/Predeploys.sol";
import "../script/L2Genesis.s.sol";

/// @title TestSetup
/// @notice Base test contract that pre-deploys all system contracts at their known addresses
abstract contract TestSetup is Test {
    Ethscriptions public ethscriptions;
    ERC20FixedDenominationManager public fixedDenominationManager;
    ERC721EthscriptionsCollectionManager public collectionsHandler;
    EthscriptionsProver public prover;
    L1Block public l1Block;
    
    function setUp() public virtual {
        L2Genesis genesis = new L2Genesis();
        genesis.runWithoutDump();
        
        // Initialize name and symbol for Ethscriptions contract
        // This would normally be done in genesis state
        ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);
        
        // Store contract references for tests
        fixedDenominationManager = ERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER);
        collectionsHandler = ERC721EthscriptionsCollectionManager(Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER);
        prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);
        l1Block = L1Block(Predeploys.L1_BLOCK_ATTRIBUTES);

        // ERC20 template doesn't need initialization - it's just a template for cloning
    }

    // Helper function to create test ethscription params
    function createTestParams(
        bytes32 transactionHash,
        address initialOwner,
        string memory dataUri,
        bool esip6
    ) internal pure returns (Ethscriptions.CreateEthscriptionParams memory) {
        // Parse the data URI to extract needed info
        bytes memory contentUriBytes = bytes(dataUri);
        bytes32 contentUriSha = sha256(contentUriBytes);  // Use SHA-256 to match production

        // Simple parsing for tests
        bytes memory content;
        string memory mimetype = "text/plain";
        bool isBase64 = false;

        // Check if data URI and parse
        if (contentUriBytes.length > 5) {
            // Find comma
            uint256 commaIdx = 0;
            for (uint256 i = 5; i < contentUriBytes.length; i++) {
                if (contentUriBytes[i] == ',') {
                    commaIdx = i;
                    break;
                }
            }

            if (commaIdx > 0) {
                // Check for base64 in metadata first
                for (uint256 i = 5; i < commaIdx; i++) {
                    if (contentUriBytes[i] == 'b' && i + 5 < commaIdx) {
                        isBase64 = (contentUriBytes[i+1] == 'a' &&
                                    contentUriBytes[i+2] == 's' &&
                                    contentUriBytes[i+3] == 'e' &&
                                    contentUriBytes[i+4] == '6' &&
                                    contentUriBytes[i+5] == '4');
                        if (isBase64) break;
                    }
                }

                // Extract content after comma
                bytes memory rawContent = new bytes(contentUriBytes.length - commaIdx - 1);
                for (uint256 i = 0; i < rawContent.length; i++) {
                    rawContent[i] = contentUriBytes[commaIdx + 1 + i];
                }

                // If base64, decode it to get actual raw bytes
                if (isBase64) {
                    content = Base64.decode(string(rawContent));
                } else {
                    content = rawContent;
                }

                // Extract mimetype if present
                if (commaIdx > 5) {
                    uint256 mimeEnd = commaIdx;
                    for (uint256 i = 5; i < commaIdx; i++) {
                        if (contentUriBytes[i] == ';') {
                            mimeEnd = i;
                            break;
                        }
                    }

                    if (mimeEnd > 5) {
                        mimetype = string(new bytes(mimeEnd - 5));
                        for (uint256 i = 0; i < mimeEnd - 5; i++) {
                            bytes(mimetype)[i] = contentUriBytes[5 + i];
                        }
                    }
                }
            }
        } else {
            content = contentUriBytes;
        }

        return Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: transactionHash,
            contentUriSha: contentUriSha,
            initialOwner: initialOwner,
            content: content,
            mimetype: mimetype,
            esip6: esip6,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });
    }
}
