// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

contract EthscriptionsTokenTest is TestSetup {
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    bytes32 constant DEPLOY_TX_HASH = bytes32(uint256(0x1234));
    bytes32 constant MINT_TX_HASH_1 = bytes32(uint256(0x5678));
    bytes32 constant MINT_TX_HASH_2 = bytes32(uint256(0x9ABC));

    // Event for tracking token manager failures
    event TokenManagerFailed(
        bytes32 indexed transactionHash,
        string operation,
        bytes revertData
    );
    
    function setUp() public override {
        super.setUp();
    }

    // Helper to create token params
    function createTokenParams(
        bytes32 transactionHash,
        address initialOwner,
        string memory contentUri,
        Ethscriptions.TokenParams memory tokenParams
    ) internal pure returns (Ethscriptions.CreateEthscriptionParams memory) {
        bytes memory contentUriBytes = bytes(contentUri);
        bytes32 contentUriHash = sha256(contentUriBytes);  // Use SHA-256 to match production

        // Extract content after "data:,"
        bytes memory content;
        if (contentUriBytes.length > 6) {
            content = new bytes(contentUriBytes.length - 6);
            for (uint256 i = 0; i < content.length; i++) {
                content[i] = contentUriBytes[i + 6];
            }
        }

        return Ethscriptions.CreateEthscriptionParams({
            transactionHash: transactionHash,
            contentUriHash: contentUriHash,
            initialOwner: initialOwner,
            content: content,
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: tokenParams
        });
    }
    
    function testTokenDeploy() public {
        // Deploy a token as Alice
        vm.prank(alice);
        
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"TEST","max":"1000000","lim":"1000"}';

        Ethscriptions.CreateEthscriptionParams memory params = createTokenParams(
            DEPLOY_TX_HASH,
            alice,
            deployContent,
            Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "TEST",
                max: 1000000,
                lim: 1000,
                amt: 0
            })
        );

        ethscriptions.createEthscription(params);
        
        // Verify token was deployed
        TokenManager.TokenInfo memory tokenInfo = tokenManager.getTokenInfo(DEPLOY_TX_HASH);
            
        assertEq(tokenInfo.protocol, "erc-20");
        assertEq(tokenInfo.tick, "TEST");
        assertEq(tokenInfo.maxSupply, 1000000);
        assertEq(tokenInfo.mintAmount, 1000);
        assertEq(tokenInfo.totalMinted, 0);
        assertTrue(tokenInfo.tokenContract != address(0));
        
        // Verify Alice owns the deploy ethscription NFT
        assertEq(ethscriptions.ownerOf(ethscriptions.getTokenId(DEPLOY_TX_HASH)), alice);
    }
    
    function testTokenMint() public {
        // First deploy the token
        testTokenDeploy();
        
        // Now mint some tokens as Bob
        vm.prank(bob);
        
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';

        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent,
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "TEST",
                max: 0,
                lim: 0,
                amt: 1000
            })
        );

        ethscriptions.createEthscription(mintParams);
        
        // Verify Bob owns the mint ethscription NFT
        assertEq(ethscriptions.ownerOf(ethscriptions.getTokenId(MINT_TX_HASH_1)), bob);
        
        // Verify Bob has the tokens (1000 * 10^18 with 18 decimals)
        address tokenAddress = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddress);
        assertEq(token.balanceOf(bob), 1000 ether);  // 1000 * 10^18
        
        // Verify total minted increased
        TokenManager.TokenInfo memory info = tokenManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 1000);
    }
    
    function testTokenTransferViaNFT() public {
        // Setup: Deploy and mint
        testTokenMint();
        
        address tokenAddress = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddress);
        
        // Bob transfers the NFT to Charlie
        vm.prank(bob);
        ethscriptions.transferEthscription(charlie, MINT_TX_HASH_1);
        
        // Verify Charlie now owns the NFT
        assertEq(ethscriptions.ownerOf(ethscriptions.getTokenId(MINT_TX_HASH_1)), charlie);
        
        // Verify tokens moved from Bob to Charlie
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(charlie), 1000 ether);
    }
    
    function testMultipleMints() public {
        // Deploy the token
        testTokenDeploy();
        
        address tokenAddress = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddress);
        
        // Bob mints tokens
        vm.prank(bob);
        string memory mintContent1 = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';
        ethscriptions.createEthscription(createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent1,
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "TEST",
                max: 0,
                lim: 0,
                amt: 1000
            })
        ));
        
        // Charlie mints tokens
        vm.prank(charlie);
        string memory mintContent2 = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"2","amt":"1000"}';
        ethscriptions.createEthscription(createTokenParams(
            MINT_TX_HASH_2,
            charlie,
            mintContent2,
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "TEST",
                max: 0,
                lim: 0,
                amt: 1000
            })
        ));
        
        // Verify balances
        assertEq(token.balanceOf(bob), 1000 ether);
        assertEq(token.balanceOf(charlie), 1000 ether);
        
        // Verify total minted
        TokenManager.TokenInfo memory info = tokenManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 2000);
    }
    
    function testMaxSupplyEnforcement() public {
        // Deploy a token with very low max supply
        vm.prank(alice);
        
        bytes32 smallDeployHash = bytes32(uint256(0xDEAD));
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"SMALL","max":"2000","lim":"1000"}';
        
        ethscriptions.createEthscription(createTokenParams(
            smallDeployHash,
            alice,
            deployContent,
            Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "SMALL",
                max: 2000,
                lim: 1000,
                amt: 0
            })
        ));
        
        // Mint up to max supply
        vm.prank(bob);
        ethscriptions.createEthscription(createTokenParams(
            bytes32(uint256(0xBEEF1)),
            bob,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"1","amt":"1000"}',
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "SMALL",
                max: 0,
                lim: 0,
                amt: 1000
            })
        ));
        
        vm.prank(charlie);
        ethscriptions.createEthscription(createTokenParams(
            bytes32(uint256(0xBEEF2)),
            charlie,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"2","amt":"1000"}',
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "SMALL",
                max: 0,
                lim: 0,
                amt: 1000
            })
        ));
        
        // Try to mint beyond max supply - should fail silently with event
        bytes32 exceedTxHash = bytes32(uint256(0xBEEF3));
        Ethscriptions.CreateEthscriptionParams memory exceedParams = createTokenParams(
            exceedTxHash,
            alice,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"3","amt":"1000"}',
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "SMALL",
                max: 0,
                lim: 0,
                amt: 1000
            })
        );

        // Expect TokenManagerFailed event (will fail due to exceeding cap)
        vm.expectEmit(true, false, false, false);
        emit TokenManagerFailed(exceedTxHash, "", "");

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(exceedParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), alice);

        // Verify supply didn't increase
        address tokenAddress = tokenManager.getTokenAddressByTick("erc-20", "SMALL");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddress);
        assertEq(token.totalSupply(), 2000 ether); // Should still be at max
    }
    
    function testCannotTransferERC20Directly() public {
        // Setup
        testTokenMint();
        
        address tokenAddress = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddress);
        
        // Bob tries to transfer tokens directly (not via NFT) - should revert
        vm.prank(bob);
        vm.expectRevert("Transfers only allowed via Ethscriptions NFT");
        token.transfer(charlie, 500);
    }
    
    function testTokenAddressPredictability() public {
        // Predict the token address before deployment
        address predictedAddress = tokenManager.predictTokenAddressByTick("erc-20", "TEST");
        
        // Deploy the token
        testTokenDeploy();
        
        // Verify the actual address matches prediction
        address actualAddress = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        assertEq(actualAddress, predictedAddress);
    }
    
    function testMintAmountMustMatch() public {
        // Deploy token with lim=1000
        testTokenDeploy();

        // Try to mint with wrong amount - should fail silently with event
        string memory wrongAmountContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"500"}';

        bytes32 wrongTxHash = bytes32(uint256(0xBAD));
        Ethscriptions.CreateEthscriptionParams memory wrongParams = createTokenParams(
            wrongTxHash,
            bob,
            wrongAmountContent,
            Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "TEST",
                max: 0,
                lim: 0,
                amt: 500  // Wrong - should be 1000 to match lim
            })
        );

        // Expect TokenManagerFailed event (will fail due to amt mismatch)
        vm.expectEmit(true, false, false, false);
        emit TokenManagerFailed(wrongTxHash, "", "");

        vm.prank(bob);
        uint256 tokenId = ethscriptions.createEthscription(wrongParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), bob);

        // Verify no tokens were minted
        address tokenAddr = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddr);
        assertEq(token.balanceOf(bob), 0); // Bob should have no tokens
    }
    
    function testCannotDeployTokenTwice() public {
        // First deploy should succeed
        testTokenDeploy();

        // Try to deploy the same token again with different parameters - should fail silently with event
        // Different max supply in content to avoid duplicate content error
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"TEST","max":"2000000","lim":"2000"}';

        bytes32 duplicateTxHash = bytes32(uint256(0xABCD));
        Ethscriptions.CreateEthscriptionParams memory duplicateParams = createTokenParams(
            duplicateTxHash,
            alice,
            deployContent,
            Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "TEST",
                max: 2000000,  // Different parameters but same tick
                lim: 2000,
                amt: 0
            })
        );

        // Expect TokenManagerFailed event (token manager will reject duplicate deploy)
        vm.expectEmit(true, false, false, false);
        emit TokenManagerFailed(duplicateTxHash, "", "");

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(duplicateParams);

        // Ethscription should still be created (but token deploy failed)
        assertEq(ethscriptions.ownerOf(tokenId), alice);

        // Verify the original token is still the only one
        address tokenAddr = tokenManager.getTokenAddressByTick("erc-20", "TEST");
        EthscriptionsERC20 token = EthscriptionsERC20(tokenAddr);
        assertEq(token.name(), "erc-20 TEST");  // Format is "protocol tick"
        assertEq(token.cap(), 1000000 ether); // Original cap, not the duplicate's
    }
}