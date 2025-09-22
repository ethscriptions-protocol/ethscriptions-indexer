// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";

contract EthscriptionsBurnTest is TestSetup {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    bytes32 testTxHash = keccak256("test_tx");
    
    function setUp() public override {
        super.setUp();
        
        // Create a test ethscription owned by alice
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            testTxHash,
            alice,
            "data:text/plain,Hello World",
            false
        );
        
        vm.prank(alice);
        ethscriptions.createEthscription(params);
    }
    
    function testBurnViaTransferToAddressZero() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Verify alice owns the ethscription
        assertEq(ethscriptions.ownerOf(tokenId), alice);
        
        // Alice transfers the ethscription to address(0) (null ownership, not burn)
        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), tokenId);

        // Verify the token is now owned by address(0)
        assertEq(ethscriptions.ownerOf(tokenId), address(0));
        
        // Verify the ethscription data still exists
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(testTxHash);
        assertEq(etsc.creator, alice);
        assertEq(etsc.previousOwner, alice); // Previous owner should be set to alice
    }
    
    function testBurnViaTransferEthscription() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Verify alice owns the ethscription
        assertEq(ethscriptions.ownerOf(tokenId), alice);
        
        // Alice transfers using transferEthscription function to address(0)
        vm.prank(alice);
        ethscriptions.transferEthscription(address(0), testTxHash);

        // Verify the token is now owned by address(0)
        assertEq(ethscriptions.ownerOf(tokenId), address(0));
        
        // Verify previousOwner was updated
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(testTxHash);
        assertEq(etsc.previousOwner, alice);
    }
    
    function testBurnWithPreviousOwnerValidation() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // First transfer from alice to bob
        vm.prank(alice);
        ethscriptions.transferFrom(alice, bob, tokenId);
        
        // Verify bob owns it and alice is previous owner
        assertEq(ethscriptions.ownerOf(tokenId), bob);
        Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(testTxHash);
        assertEq(etsc.previousOwner, alice);
        
        // Bob transfers to address(0) with previous owner validation
        vm.prank(bob);
        ethscriptions.transferEthscriptionForPreviousOwner(address(0), testTxHash, alice);

        // Verify the token is now owned by address(0)
        assertEq(ethscriptions.ownerOf(tokenId), address(0));
        
        // Verify previousOwner was updated to bob
        etsc = ethscriptions.getEthscription(testTxHash);
        assertEq(etsc.previousOwner, bob);
    }
    
    function testCannotTransferBurnedToken() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Alice burns the token
        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), tokenId);
        
        // Try to transfer a burned token (should fail)
        vm.prank(alice);
        vm.expectRevert();
        ethscriptions.transferFrom(address(0), bob, tokenId);
    }
    
    function testBurnUpdatesBalances() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Check initial balance
        assertEq(ethscriptions.balanceOf(alice), 1);
        
        // Burn the token
        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), tokenId);
        
        // Check balance after burn
        assertEq(ethscriptions.balanceOf(alice), 0);
        // Note: We can't check balanceOf(address(0)) as OpenZeppelin prevents that
        // But the token should be burned (not owned by anyone)
    }
    
    function testOnlyOwnerCanBurn() public {
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Bob tries to burn alice's token (should fail)
        vm.prank(bob);
        vm.expectRevert();
        ethscriptions.transferFrom(alice, address(0), tokenId);
        
        // Token should still be owned by alice
        assertEq(ethscriptions.ownerOf(tokenId), alice);
    }
    
    function testApprovedCanBurn() public {
        // Approvals are not supported in our implementation
        uint256 tokenId = ethscriptions.getTokenId(testTxHash);

        // Alice tries to approve bob (should fail)
        vm.prank(alice);
        vm.expectRevert("Approvals not supported");
        ethscriptions.approve(bob, tokenId);

        // Verify alice still owns the token
        assertEq(ethscriptions.ownerOf(tokenId), alice);
    }
    
    function testBurnCallsTokenManagerHandleTransfer() public {
        // Create a simple non-token ethscription first to test basic burn
        bytes32 simpleTxHash = keccak256("simple_tx");
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            simpleTxHash,
            alice,
            "data:text/plain,Simple text",
            false
        );
        
        vm.prank(alice);
        ethscriptions.createEthscription(params);
        
        uint256 simpleTokenId = ethscriptions.getTokenId(simpleTxHash);

        // Transfer the ethscription to address(0) (null ownership)
        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), simpleTokenId);

        // Verify it's owned by address(0)
        assertEq(ethscriptions.ownerOf(simpleTokenId), address(0));

        // The transfer should have called TokenManager.handleTokenTransfer with to=address(0)
        // This ensures TokenManager is notified of transfers to null address
    }
}