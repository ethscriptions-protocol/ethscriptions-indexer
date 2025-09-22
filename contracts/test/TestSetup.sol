// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Ethscriptions.sol";
import "../src/TokenManager.sol";
import "../src/EthscriptionsProver.sol";
import "../src/EthscriptionsERC20.sol";
import "../src/L2/L2ToL1MessagePasser.sol";
import "../src/L2/L1Block.sol";
import {Base64} from "solady/utils/Base64.sol";
import "../src/libraries/Predeploys.sol";
import "../script/L2Genesis.s.sol";

/// @title TestSetup
/// @notice Base test contract that pre-deploys all system contracts at their known addresses
abstract contract TestSetup is Test {
    Ethscriptions public ethscriptions;
    TokenManager public tokenManager;
    EthscriptionsProver public prover;
    L1Block public l1Block;
    
    function setUp() public virtual {
        // Deploy all system contracts to temporary addresses first
        // Ethscriptions tempEthscriptions = new Ethscriptions();
        // TokenManager tempTokenManager = new TokenManager();
        // EthscriptionsProver tempProver = new EthscriptionsProver();
        // EthscriptionsERC20 tempERC20Template = new EthscriptionsERC20();
        // L2ToL1MessagePasser tempMessagePasser = new L2ToL1MessagePasser();
        // L1Block tempL1Block = new L1Block();
        
        // // Etch them at their known addresses
        // vm.etch(Predeploys.ETHSCRIPTIONS, address(tempEthscriptions).code);
        // vm.etch(Predeploys.TOKEN_MANAGER, address(tempTokenManager).code);
        // vm.etch(Predeploys.ETHSCRIPTIONS_PROVER, address(tempProver).code);
        // vm.etch(Predeploys.ERC20_TEMPLATE, address(tempERC20Template).code);
        // vm.etch(Predeploys.L2_TO_L1_MESSAGE_PASSER, address(tempMessagePasser).code);
        // vm.etch(Predeploys.L1_BLOCK_ATTRIBUTES, address(tempL1Block).code);
        
        L2Genesis genesis = new L2Genesis();
        genesis.runWithoutDump();
        
        // Initialize name and symbol for Ethscriptions contract
        // This would normally be done in genesis state
        ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);
        
        // Store contract references for tests
        tokenManager = TokenManager(Predeploys.TOKEN_MANAGER);
        prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);
        
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
        bytes32 contentUriHash = sha256(contentUriBytes);  // Use SHA-256 to match production

        // Simple parsing for tests
        bytes memory content;
        string memory mimetype = "text/plain";
        string memory mediaType = "text";
        string memory mimeSubtype = "plain";
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

                        // Parse media type and subtype
                        bytes memory mimetypeBytes = bytes(mimetype);
                        for (uint256 i = 0; i < mimetypeBytes.length; i++) {
                            if (mimetypeBytes[i] == '/') {
                                mediaType = string(new bytes(i));
                                for (uint256 j = 0; j < i; j++) {
                                    bytes(mediaType)[j] = mimetypeBytes[j];
                                }
                                mimeSubtype = string(new bytes(mimetypeBytes.length - i - 1));
                                for (uint256 j = 0; j < mimetypeBytes.length - i - 1; j++) {
                                    bytes(mimeSubtype)[j] = mimetypeBytes[i + 1 + j];
                                }
                                break;
                            }
                        }
                    }
                }
            }
        } else {
            content = contentUriBytes;
        }

        return Ethscriptions.CreateEthscriptionParams({
            transactionHash: transactionHash,
            contentUriHash: contentUriHash,
            initialOwner: initialOwner,
            content: content,
            mimetype: mimetype,
            mediaType: mediaType,
            mimeSubtype: mimeSubtype,
            esip6: esip6,
            tokenParams: Ethscriptions.TokenParams({
                op: "",
                protocol: "",
                tick: "",
                max: 0,
                lim: 0,
                amt: 0
            })
        });
    }
}