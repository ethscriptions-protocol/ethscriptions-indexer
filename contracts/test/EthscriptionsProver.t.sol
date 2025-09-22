// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";

contract EthscriptionsProverTest is TestSetup {
    address alice = address(0x1);
    address bob = address(0x2);
    address l1Target = address(0x1234);
    
    bytes32 constant TEST_TX_HASH = bytes32(uint256(0xABCD));
    bytes32 constant TOKEN_DEPLOY_HASH = bytes32(uint256(0x1234));
    bytes32 constant TOKEN_MINT_HASH = bytes32(uint256(0x5678));
    
    function setUp() public override {
        super.setUp();

        // Create a test ethscription with alice as creator
        vm.startPrank(alice);
        ethscriptions.createEthscription(createTestParams(
            TEST_TX_HASH,
            alice,
            "data:,test content",
            false
        ));
        vm.stopPrank();
    }
    
    function testProveEthscriptionDataOnCreation() public {
        // The ethscription creation in setUp should have triggered a proof
        // Let's transfer it to verify the proof includes previous owner
        uint256 tokenId = ethscriptions.getTokenId(TEST_TX_HASH);
        vm.prank(alice);
        ethscriptions.transferFrom(alice, bob, tokenId);
        
        // Now prove the data which should include bob as current owner and alice as previous
        vm.recordLogs();
        prover.proveEthscriptionData(TEST_TX_HASH);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find the MessagePassed event and extract proof data
        bytes memory proofData;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessagePassed(uint256,address,address,uint256,uint256,bytes,bytes32)")) {
                // Decode the non-indexed parameters from data field
                // The data field contains: value, gasLimit, data (as bytes), withdrawalHash
                (uint256 value, uint256 gasLimit, bytes memory data, bytes32 withdrawalHash) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, bytes, bytes32)
                );
                proofData = data;
                break;
            }
        }
        
        // Decode and verify proof data
        EthscriptionsProver.EthscriptionDataProof memory decodedProof = abi.decode(
            proofData,
            (EthscriptionsProver.EthscriptionDataProof)
        );
        
        assertEq(decodedProof.ethscriptionTxHash, TEST_TX_HASH);
        assertEq(decodedProof.creator, alice); // Creator should be alice due to vm.prank
        assertEq(decodedProof.currentOwner, bob);
        assertEq(decodedProof.previousOwner, alice);
        // assertEq(decodedProof.ethscriptionNumber, 0);
        assertEq(decodedProof.isToken, false);
        assertEq(decodedProof.tokenAmount, 0);
        assertTrue(decodedProof.contentSha != bytes32(0));
    }
    
    function testProveTokenBalance() public {
        // First deploy a token
        vm.prank(alice);
        bytes memory tokenDeployUri = bytes('data:,{"p":"erc-20","op":"deploy","tick":"TEST","max":"1000000","lim":"1000"}');
        ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: TOKEN_DEPLOY_HASH,
            contentUriHash: sha256(tokenDeployUri),
            initialOwner: alice,
            content: bytes('{"p":"erc-20","op":"deploy","tick":"TEST","max":"1000000","lim":"1000"}'),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "TEST",
                max: 1000000,
                lim: 1000,
                amt: 0
            })
        }));
        
        // Mint some tokens
        vm.prank(bob);
        bytes memory tokenMintUri = bytes('data:,{"p":"erc-20","op":"mint","tick":"TEST","amt":"1000"}');
        ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: TOKEN_MINT_HASH,
            contentUriHash: sha256(tokenMintUri),
            initialOwner: bob,
            content: bytes('{"p":"erc-20","op":"mint","tick":"TEST","amt":"1000"}'),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "TEST",
                max: 0,
                lim: 0,
                amt: 1000
            })
        }));
        
        // Prove token balance using the deploy hash
        vm.recordLogs();
        prover.proveTokenBalance(bob, TOKEN_DEPLOY_HASH);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find the MessagePassed event and extract proof data
        bytes memory proofData;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessagePassed(uint256,address,address,uint256,uint256,bytes,bytes32)")) {
                // Decode the non-indexed parameters from data field
                (uint256 value, uint256 gasLimit, bytes memory data, bytes32 withdrawalHash) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, bytes, bytes32)
                );
                proofData = data;
                break;
            }
        }
        
        // Decode and verify proof data
        EthscriptionsProver.TokenBalanceProof memory decodedProof = abi.decode(
            proofData,
            (EthscriptionsProver.TokenBalanceProof)
        );
        
        assertEq(decodedProof.holder, bob);
        assertEq(decodedProof.protocol, "erc-20");
        assertEq(decodedProof.tick, "TEST");
        assertEq(decodedProof.balance, 1000 ether); // 1000 * 10^18
    }
    
    function testAutomaticProofOnCreation() public {
        // Create a new ethscription and verify it triggers automatic proof
        bytes32 newTxHash = bytes32(uint256(0xFEED));
        
        vm.recordLogs();
        vm.prank(bob);
        ethscriptions.createEthscription(createTestParams(
            newTxHash,
            bob,
            "data:,automatic proof test",
            false
        ));
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find the EthscriptionDataProofSent event to verify automatic proof was generated
        bool foundProofEvent = false;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("EthscriptionDataProofSent(bytes32,uint256,uint256)")) {
                foundProofEvent = true;
                break;
            }
        }
        assertTrue(foundProofEvent, "Automatic proof was not generated on creation");
    }
    
    function testCannotProveNonExistentEthscription() public {
        bytes32 fakeTxHash = bytes32(uint256(0xDEADBEEF));
        
        vm.expectRevert();
        prover.proveEthscriptionData(fakeTxHash);
    }
}