// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";

contract EthscriptionsProverTest is TestSetup {
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address l1Target = address(0x1234);
    
    bytes32 constant TEST_TX_HASH = bytes32(uint256(0xABCD));
    bytes32 constant TOKEN_DEPLOY_HASH = bytes32(uint256(0x1234));
    bytes32 constant TOKEN_MINT_HASH = bytes32(uint256(0x5678));
    
    function setUp() public override {
        super.setUp();

        vm.warp(Constants.historicalBackfillApproxDoneAt);

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
    
    function testProveEthscriptionDataViaBatchFlush() public {
        // The ethscription creation in setUp should have queued it for proving
        // Let's transfer it to verify the proof includes previous owner
        uint256 tokenId = ethscriptions.getTokenId(TEST_TX_HASH);
        vm.prank(alice);
        ethscriptions.transferFrom(alice, bob, tokenId);

        // Now flush the batch which should prove the data with bob as current owner and alice as previous
        vm.roll(block.number + 1);

        vm.startPrank(Predeploys.L1_BLOCK_ATTRIBUTES);
        vm.recordLogs();
        prover.flushAllProofs();
        vm.stopPrank();
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
        
        assertEq(decodedProof.ethscriptionId, TEST_TX_HASH);
        assertEq(decodedProof.creator, alice); // Creator should be alice due to vm.prank
        assertEq(decodedProof.currentOwner, bob);
        assertEq(decodedProof.previousOwner, alice);
        // assertEq(decodedProof.ethscriptionNumber, 0);
        assertEq(decodedProof.esip6, false);
        assertTrue(decodedProof.contentHash != bytes32(0));
        assertTrue(decodedProof.contentUriSha != bytes32(0));
        // l1BlockHash can be zero in test environment
        assertEq(decodedProof.l1BlockHash, bytes32(0));
    }
    
    function testBatchFlushProofs() public {
        // First flush any pending proofs from setup
        vm.roll(block.number + 1);

        vm.startPrank(Predeploys.L1_BLOCK_ATTRIBUTES);
        prover.flushAllProofs();
        vm.stopPrank();

        vm.warp(Constants.historicalBackfillApproxDoneAt + 1);

        // Now move to next block for our test
        vm.roll(block.number + 1);

        // Create multiple ethscriptions in the same block
        bytes32 txHash1 = bytes32(uint256(0x123));
        bytes32 txHash2 = bytes32(uint256(0x456));
        bytes32 txHash3 = bytes32(uint256(0x789));

        // Create three ethscriptions
        vm.startPrank(alice);
        ethscriptions.createEthscription(
            Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash1,
                contentUriSha: keccak256("data:,test1"),
                initialOwner: alice,
                content: bytes("test1"),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams("", "", "")
            })
        );
        vm.stopPrank();

        vm.startPrank(bob);
        ethscriptions.createEthscription(
            Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash2,
                contentUriSha: keccak256("data:,test2"),
                initialOwner: bob,
                content: bytes("test2"),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams("", "", "")
            })
        );
        vm.stopPrank();

        // Transfer the first ethscription (should only be queued once due to deduplication)
        vm.startPrank(alice);
        ethscriptions.transferEthscription(bob, txHash1);
        vm.stopPrank();

        // Create a third ethscription
        vm.startPrank(charlie);
        ethscriptions.createEthscription(
            Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash3,
                contentUriSha: keccak256("data:,test3"),
                initialOwner: charlie,
                content: bytes("test3"),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams("", "", "")
            })
        );
        vm.stopPrank();

        // Now simulate L1Block calling flush at the start of the next block
        vm.roll(block.number + 1);

        // Prank as L1Block contract
        vm.startPrank(Predeploys.L1_BLOCK_ATTRIBUTES);
        vm.recordLogs();
        prover.flushAllProofs();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Count individual proof sent events
        uint256 proofsSent = 0;
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("EthscriptionDataProofSent(bytes32,uint256,uint256)")) {
                proofsSent++;
            }
        }
        assertEq(proofsSent, 3, "Should have sent 3 individual proofs");
    }

    function testNoProofsBeforeProvingStart() public {
        // Clear any queued proofs from setup
        vm.startPrank(Predeploys.L1_BLOCK_ATTRIBUTES);
        prover.flushAllProofs();
        vm.stopPrank();

        vm.warp(1760630076);

        bytes32 earlyTxHash = bytes32(uint256(0xBEEF));

        vm.startPrank(alice);
        ethscriptions.createEthscription(createTestParams(
            earlyTxHash,
            alice,
            "data:,early",
            false
        ));
        vm.stopPrank();

        vm.roll(block.number + 1);

        vm.startPrank(Predeploys.L1_BLOCK_ATTRIBUTES);
        vm.recordLogs();
        prover.flushAllProofs();
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 proofsSent;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("EthscriptionDataProofSent(bytes32,uint256,uint256)")) {
                proofsSent++;
            }
        }
        assertEq(proofsSent, 0, "Should not send proofs before proving start");
    }
}
