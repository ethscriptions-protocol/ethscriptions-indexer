// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Ethscriptions.sol";
import "./L2/L2ToL1MessagePasser.sol";
import "./L2/L1Block.sol";
import "./libraries/Predeploys.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title EthscriptionsProver
/// @notice Proves Ethscription ownership and token balances to L1 via OP Stack
/// @dev Uses L2ToL1MessagePasser to send provable messages to L1
contract EthscriptionsProver {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // =============================================================
    //                           STRUCTS
    // =============================================================

    /// @notice Info stored when an ethscription is queued for proving
    struct QueuedProof {
        bytes32 l1BlockHash;
        uint48 l2BlockNumber;
        uint48 l2BlockTimestamp;
        uint48 l1BlockNumber;
    }

    /// @notice Struct for ethscription data proof
    struct EthscriptionDataProof {
        bytes32 ethscriptionId;
        bytes32 contentHash;
        bytes32 contentUriSha;
        bytes32 l1BlockHash;
        address creator;
        address currentOwner;
        address previousOwner;
        bool esip6;
        uint48 ethscriptionNumber;
        uint48 l1BlockNumber;
        uint48 l2BlockNumber;
        uint48 l2Timestamp;
    }

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @notice L1Block contract address for access control
    address constant L1_BLOCK = Predeploys.L1_BLOCK_ATTRIBUTES;

    /// @notice L2ToL1MessagePasser predeploy address on OP Stack
    L2ToL1MessagePasser constant L2_TO_L1_MESSAGE_PASSER =
        L2ToL1MessagePasser(Predeploys.L2_TO_L1_MESSAGE_PASSER);

    /// @notice The Ethscriptions contract (pre-deployed at known address)
    Ethscriptions constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @notice Set of all ethscription transaction hashes queued for proving
    EnumerableSet.Bytes32Set private queuedEthscriptions;

    /// @notice Mapping from ethscription tx hash to its queued proof info
    mapping(bytes32 => QueuedProof) private queuedProofInfo;

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyEthscriptions();
    error OnlyL1Block();

    // =============================================================
    //                          EVENTS
    // =============================================================

    /// @notice Emitted when an ethscription data proof is sent to L1
    event EthscriptionDataProofSent(
        bytes32 indexed ethscriptionId,
        uint256 indexed l2BlockNumber,
        uint256 l2Timestamp
    );

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Queue an ethscription for proving
    /// @dev Only callable by the Ethscriptions contract
    /// @param ethscriptionId The ID of the ethscription (L1 tx hash)
    function queueEthscription(bytes32 ethscriptionId) external virtual {
        if (msg.sender != address(ethscriptions)) revert OnlyEthscriptions();

        // Add to the set (deduplicates automatically)
        if (queuedEthscriptions.add(ethscriptionId)) {
            // Only store info if this is the first time we're queueing this ID
            // Capture the L1 block hash and number at the time of queuing
            L1Block l1Block = L1Block(L1_BLOCK);
            queuedProofInfo[ethscriptionId] = QueuedProof({
                l1BlockHash: l1Block.hash(),
                l2BlockNumber: uint48(block.number),
                l2BlockTimestamp: uint48(block.timestamp),
                l1BlockNumber: uint48(l1Block.number())
            });
        }
    }

    /// @notice Flush all queued proofs
    /// @dev Only callable by the L1Block contract at the start of each new block
    function flushAllProofs() external {
        if (msg.sender != L1_BLOCK) revert OnlyL1Block();

        uint256 count = queuedEthscriptions.length();

        // Process and remove each ethscription from the set
        // We iterate backwards to avoid index shifting during removal
        for (uint256 i = count; i > 0; i--) {
            bytes32 ethscriptionId = queuedEthscriptions.at(i - 1);

            // Create and send proof for current state with stored block info
            _createAndSendProof(ethscriptionId, queuedProofInfo[ethscriptionId]);

            // Clean up: remove from set and delete the proof info
            queuedEthscriptions.remove(ethscriptionId);
            delete queuedProofInfo[ethscriptionId];
        }
    }

    // =============================================================
    //                    INTERNAL FUNCTIONS
    // =============================================================

    /// @notice Internal function to create and send proof for an ethscription
    /// @param ethscriptionId The Ethscription ID (L1 tx hash)
    /// @param proofInfo The queued proof info containing block data
    function _createAndSendProof(bytes32 ethscriptionId, QueuedProof memory proofInfo) internal {
        // Get ethscription data including previous owner (without content for gas efficiency)
        Ethscriptions.Ethscription memory ethscription = ethscriptions.getEthscription(ethscriptionId, false);
        // currentOwner is already in the struct now
        address currentOwner = ethscription.currentOwner;

        // Create proof struct with all ethscription data
        EthscriptionDataProof memory proof = EthscriptionDataProof({
            ethscriptionId: ethscriptionId,
            contentHash: ethscription.contentHash,
            contentUriSha: ethscription.contentUriSha,
            l1BlockHash: proofInfo.l1BlockHash,
            creator: ethscription.creator,
            currentOwner: currentOwner,
            previousOwner: ethscription.previousOwner,
            esip6: ethscription.esip6,
            ethscriptionNumber: uint48(ethscription.ethscriptionNumber),
            l1BlockNumber: proofInfo.l1BlockNumber,
            l2BlockNumber: proofInfo.l2BlockNumber,
            l2Timestamp: proofInfo.l2BlockTimestamp
        });

        // Encode and send to L1 with zero address and gas (only for state recording)
        bytes memory proofData = abi.encode(proof);
        L2_TO_L1_MESSAGE_PASSER.initiateWithdrawal(address(0), 0, proofData);

        emit EthscriptionDataProofSent(ethscriptionId, proofInfo.l2BlockNumber, proofInfo.l2BlockTimestamp);
    }
}
