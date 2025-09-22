// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./Ethscriptions.sol";
import "./TokenManager.sol";
import "./EthscriptionsERC20.sol";
import "./L2/L2ToL1MessagePasser.sol";
import "./libraries/Predeploys.sol";

/// @title EthscriptionsProver
/// @notice Proves Ethscription ownership and token balances to L1 via OP Stack
/// @dev Uses L2ToL1MessagePasser to send provable messages to L1
contract EthscriptionsProver {
    /// @notice L2ToL1MessagePasser predeploy address on OP Stack
    L2ToL1MessagePasser constant L2_TO_L1_MESSAGE_PASSER = 
        L2ToL1MessagePasser(Predeploys.L2_TO_L1_MESSAGE_PASSER);
    
    /// @notice The Ethscriptions contract (pre-deployed at known address)
    Ethscriptions public constant ethscriptions = Ethscriptions(Predeploys.ETHSCRIPTIONS);
    
    /// @notice The TokenManager contract (pre-deployed at known address)
    TokenManager public constant tokenManager = TokenManager(Predeploys.TOKEN_MANAGER);
    
    /// @notice Struct for token balance proof data
    struct TokenBalanceProof {
        address holder;
        string protocol;
        string tick;
        uint256 balance;
        uint256 l2BlockNumber;
        uint256 l2Timestamp;
        // TODO: Add l1BlockNumber once we have L2->L1 block mapping
    }
    
    /// @notice Struct for ethscription data proof
    struct EthscriptionDataProof {
        bytes32 ethscriptionTxHash;
        bytes32 contentSha;
        address creator;
        address currentOwner;
        address previousOwner;
        uint256 ethscriptionNumber;
        bool isToken;
        uint256 tokenAmount;
        uint256 l2BlockNumber;
        uint256 l2Timestamp;
        // TODO: Add l1BlockNumber once we have L2->L1 block mapping
    }
    
    /// @notice Events for tracking proofs
    event TokenBalanceProofSent(
        address indexed holder,
        string tick,
        uint256 indexed l2BlockNumber,
        uint256 l2Timestamp
    );
    
    event EthscriptionDataProofSent(
        bytes32 indexed ethscriptionTxHash,
        uint256 indexed l2BlockNumber,
        uint256 l2Timestamp
    );
    
    /// @notice Prove token balance for an address
    /// @param holder The address to prove balance for
    /// @param deployTxHash The deploy transaction hash (identifies the token type)
    function proveTokenBalance(
        address holder,
        bytes32 deployTxHash
    ) external {
        // Get token info from TokenManager
        TokenManager.TokenInfo memory tokenInfo = tokenManager.getTokenInfo(deployTxHash);
        
        // Get balance
        EthscriptionsERC20 token = EthscriptionsERC20(tokenInfo.tokenContract);
        uint256 balance = token.balanceOf(holder);
        
        // Create proof struct
        TokenBalanceProof memory proof = TokenBalanceProof({
            holder: holder,
            protocol: tokenInfo.protocol,
            tick: tokenInfo.tick,
            balance: balance,
            l2BlockNumber: block.number,
            l2Timestamp: block.timestamp
        });
        
        // Encode and send to L1 with zero address and gas (only for state recording)
        bytes memory proofData = abi.encode(proof);
        L2_TO_L1_MESSAGE_PASSER.initiateWithdrawal(address(0), 0, proofData);
        
        emit TokenBalanceProofSent(holder, tokenInfo.tick, block.number, block.timestamp);
    }
    
    /// @notice Prove ethscription existence and metadata
    /// @param ethscriptionTxHash The transaction hash of the ethscription
    function proveEthscriptionData(bytes32 ethscriptionTxHash) external virtual {
        // Get ethscription data including previous owner
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(ethscriptionTxHash);
        address currentOwner = ethscriptions.currentOwner(ethscriptionTxHash);
        
        // Check if it's a token item
        bool isToken = tokenManager.isTokenItem(ethscriptionTxHash);
        uint256 tokenAmount = 0;
        if (isToken) {
            tokenAmount = tokenManager.getTokenAmount(ethscriptionTxHash);
        }
        
        // Create proof struct with previous owner
        EthscriptionDataProof memory proof = EthscriptionDataProof({
            ethscriptionTxHash: ethscriptionTxHash,
            contentSha: etsc.content.contentSha,
            creator: etsc.creator,
            currentOwner: currentOwner,
            previousOwner: etsc.previousOwner,
            ethscriptionNumber: etsc.ethscriptionNumber,
            isToken: isToken,
            tokenAmount: tokenAmount,
            l2BlockNumber: block.number,
            l2Timestamp: block.timestamp
        });
        
        // Encode and send to L1 with zero address and gas (only for state recording)
        bytes memory proofData = abi.encode(proof);
        L2_TO_L1_MESSAGE_PASSER.initiateWithdrawal(address(0), 0, proofData);
        
        emit EthscriptionDataProofSent(ethscriptionTxHash, block.number, block.timestamp);
    }
}