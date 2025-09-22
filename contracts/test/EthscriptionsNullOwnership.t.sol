// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";

contract EthscriptionsNullOwnershipTest is TestSetup {
    address alice = makeAddr("alice");

    function setUp() public override {
        super.setUp();
    }

    function testMintToNullAddress() public {
        bytes32 txHash = keccak256("mint_to_null");

        // Create ethscription with initialOwner as address(0)
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(0),
            "data:text/plain,Null owned",
            false
        );

        // Expect only one EthscriptionCreated event (no EthscriptionTransferred since from == address(0))
        bytes32 contentSha = sha256(bytes("Null owned")); // Raw content, not data URI
        vm.expectEmit(true, true, true, true);
        emit Ethscriptions.EthscriptionCreated(
            txHash,
            alice, // creator
            address(0), // initialOwner
            contentSha,
            11, // ethscription number (after 10 genesis)
            1 // pointerCount (content stored once)
        );

        // Should NOT emit EthscriptionTransferred for mint
        // (no expectEmit here)

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify ownership
        assertEq(ethscriptions.ownerOf(tokenId), address(0), "Should be owned by null address");
        assertEq(ethscriptions.currentOwner(txHash), address(0), "currentOwner should return null address");

        // Verify ethscription data
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(txHash);
        assertEq(etsc.creator, alice, "Creator should be alice");
        assertEq(etsc.initialOwner, address(0), "Initial owner should be null address");
        assertEq(etsc.previousOwner, alice, "Previous owner should be alice after mint-to-null pattern");

        // Verify balance (genesis has 1 null-owned, plus this one = 2)
        assertEq(ethscriptions.balanceOf(address(0)), 2, "Null address should have balance of 2 (1 genesis + 1 new)");
        assertEq(ethscriptions.balanceOf(alice), 0, "Alice should have no balance");
    }

    function testTransferToNullEmitsEvent() public {
        bytes32 txHash = keccak256("transfer_to_null");

        // First create owned by alice
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            alice,
            "data:text/plain,Will be null owned",
            false
        );

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Now transfer to null - should emit EthscriptionTransferred
        vm.expectEmit(true, true, true, true);
        emit Ethscriptions.EthscriptionTransferred(
            txHash,
            alice, // from
            address(0), // to
            11 // ethscription number
        );

        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), tokenId);

        // Verify ownership changed
        assertEq(ethscriptions.ownerOf(tokenId), address(0), "Should be owned by null address");
        assertEq(ethscriptions.currentOwner(txHash), address(0), "currentOwner should return null address");

        // Verify previousOwner updated
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(txHash);
        assertEq(etsc.previousOwner, alice, "Previous owner should be alice after transfer");
    }

    function testCannotTransferFromNull() public {
        bytes32 txHash = keccak256("null_owned");

        // Create ethscription owned by null
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(0),
            "data:text/plain,Null owned",
            false
        );

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(params);

        // No one can transfer from null address (since msg.sender can't be address(0))
        vm.prank(alice);
        vm.expectRevert();
        ethscriptions.transferFrom(address(0), alice, tokenId);
    }
}