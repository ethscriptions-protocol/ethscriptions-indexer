// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

contract EthscriptionsTokenTest is TestSetup {
    string constant CANONICAL_PROTOCOL = "erc-20-fixed-denomination";
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    bytes32 constant DEPLOY_TX_HASH = bytes32(uint256(0x1234));
    bytes32 constant MINT_TX_HASH_1 = bytes32(uint256(0x5678));
    bytes32 constant MINT_TX_HASH_2 = bytes32(uint256(0x9ABC));

    // Event for tracking protocol handler failures
    event ProtocolHandlerFailed(
        bytes32 indexed transactionHash,
        string indexed protocol,
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
        string memory protocol,
        string memory operation,
        bytes memory data
    ) internal pure returns (Ethscriptions.CreateEthscriptionParams memory) {
        bytes memory contentUriBytes = bytes(contentUri);
        bytes32 contentUriSha = sha256(contentUriBytes);  // Use SHA-256 to match production

        // Extract content after "data:,"
        bytes memory content;
        if (contentUriBytes.length > 6) {
            content = new bytes(contentUriBytes.length - 6);
            for (uint256 i = 0; i < content.length; i++) {
                content[i] = contentUriBytes[i + 6];
            }
        }

        return Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: transactionHash,
            contentUriSha: contentUriSha,
            initialOwner: initialOwner,
            content: content,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: protocol,
                operation: operation,
                data: data
            })
        });
    }
    
    function testTokenDeploy() public {
        // Deploy a token as Alice
        vm.prank(alice);
        
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"TEST","max":"1000000","lim":"1000"}';

        // For deploy operation, encode the deploy params
        ERC20FixedDenominationManager.DeployOperation memory deployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: "TEST",
            maxSupply: 1000000,
            mintAmount: 1000
        });

        Ethscriptions.CreateEthscriptionParams memory params = createTokenParams(
            DEPLOY_TX_HASH,
            alice,
            deployContent,
            CANONICAL_PROTOCOL,
            "deploy",
            abi.encode(deployOp)
        );

        ethscriptions.createEthscription(params);
        
        // Verify token was deployed
        ERC20FixedDenominationManager.TokenInfo memory tokenInfo = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
            
        assertEq(tokenInfo.tick, "TEST");
        assertEq(tokenInfo.maxSupply, 1000000);
        assertEq(tokenInfo.mintAmount, 1000);
        assertEq(tokenInfo.totalMinted, 0);
        assertTrue(tokenInfo.tokenContract != address(0));
        
        // Verify Alice owns the deploy ethscription NFT
        Ethscriptions.Ethscription memory deployEthscription = ethscriptions.getEthscription(DEPLOY_TX_HASH);
        assertEq(ethscriptions.ownerOf(deployEthscription.ethscriptionNumber), alice);
    }
    
    function testTokenMint() public {
        // First deploy the token
        testTokenDeploy();
        
        // Now mint some tokens as Bob
        vm.prank(bob);
        
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';

        // For mint operation, encode the mint params
        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1,
            amount: 1000
        });

        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        ethscriptions.createEthscription(mintParams);
        
        // Verify Bob owns the mint ethscription NFT
        Ethscriptions.Ethscription memory mintEthscription = ethscriptions.getEthscription(MINT_TX_HASH_1);
        assertEq(ethscriptions.ownerOf(mintEthscription.ethscriptionNumber), bob);
        
        // Verify Bob has the tokens (1000 * 10^18 with 18 decimals)
        address tokenAddress = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddress);
        assertEq(token.balanceOf(bob), 1000 ether);  // 1000 * 10^18
        
        // Verify total minted increased
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 1000);
    }
    
    function testTokenTransferViaNFT() public {
        // Setup: Deploy and mint
        testTokenMint();
        
        address tokenAddress = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddress);
        
        // Bob transfers the NFT to Charlie
        vm.prank(bob);
        ethscriptions.transferEthscription(charlie, MINT_TX_HASH_1);
        
        // Verify Charlie now owns the NFT
        Ethscriptions.Ethscription memory mintEthscription1 = ethscriptions.getEthscription(MINT_TX_HASH_1);
        assertEq(ethscriptions.ownerOf(mintEthscription1.ethscriptionNumber), charlie);
        
        // Verify tokens moved from Bob to Charlie
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(charlie), 1000 ether);
    }
    
    function testMultipleMints() public {
        // Deploy the token
        testTokenDeploy();

        address tokenAddress = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddress);
        
        // Bob mints tokens
        vm.prank(bob);
        string memory mintContent1 = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';
        ERC20FixedDenominationManager.MintOperation memory mintOp1 = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1,
            amount: 1000
        });
        ethscriptions.createEthscription(createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent1,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp1)
        ));
        
        // Charlie mints tokens
        vm.prank(charlie);
        string memory mintContent2 = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"2","amt":"1000"}';
        ERC20FixedDenominationManager.MintOperation memory mintOp2 = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 2,
            amount: 1000
        });
        ethscriptions.createEthscription(createTokenParams(
            MINT_TX_HASH_2,
            charlie,
            mintContent2,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp2)
        ));
        
        // Verify balances
        assertEq(token.balanceOf(bob), 1000 ether);
        assertEq(token.balanceOf(charlie), 1000 ether);
        
        // Verify total minted
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 2000);
    }

    function testMintIdCannotBeReused() public {
        // Deploy and perform initial mint with ID 1
        testTokenMint();

        // Attempt to mint the same ID again
        vm.prank(charlie);
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';
        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1,
            amount: 1000
        });

        Ethscriptions.CreateEthscriptionParams memory params = createTokenParams(
            bytes32(uint256(0xDEADFEED)),
            charlie,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        vm.expectRevert(Ethscriptions.DuplicateContentUri.selector);
        ethscriptions.createEthscription(params);
    }
    
    function testMaxSupplyEnforcement() public {
        // Deploy a token with very low max supply
        vm.prank(alice);
        
        bytes32 smallDeployHash = bytes32(uint256(0xDEAD));
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"SMALL","max":"2000","lim":"1000"}';
        
        ERC20FixedDenominationManager.DeployOperation memory smallDeployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: "SMALL",
            maxSupply: 2000,
            mintAmount: 1000
        });

        ethscriptions.createEthscription(createTokenParams(
            smallDeployHash,
            alice,
            deployContent,
            CANONICAL_PROTOCOL,
            "deploy",
            abi.encode(smallDeployOp)
        ));
        
        // Mint up to max supply
        vm.prank(bob);
        ERC20FixedDenominationManager.MintOperation memory mintOp1Small = ERC20FixedDenominationManager.MintOperation({
            tick: "SMALL",
            id: 1,
            amount: 1000
        });
        ethscriptions.createEthscription(createTokenParams(
            bytes32(uint256(0xBEEF1)),
            bob,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"1","amt":"1000"}',
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp1Small)
        ));
        
        vm.prank(charlie);
        ERC20FixedDenominationManager.MintOperation memory mintOp2Small = ERC20FixedDenominationManager.MintOperation({
            tick: "SMALL",
            id: 2,
            amount: 1000
        });
        ethscriptions.createEthscription(createTokenParams(
            bytes32(uint256(0xBEEF2)),
            charlie,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"2","amt":"1000"}',
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp2Small)
        ));
        
        // Try to mint beyond max supply - should fail silently with event
        bytes32 exceedTxHash = bytes32(uint256(0xBEEF3));
        ERC20FixedDenominationManager.MintOperation memory exceedMintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "SMALL",
            id: 3,
            amount: 1000
        });
        Ethscriptions.CreateEthscriptionParams memory exceedParams = createTokenParams(
            exceedTxHash,
            alice,
            'data:,{"p":"erc-20","op":"mint","tick":"SMALL","id":"3","amt":"1000"}',
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(exceedMintOp)
        );

        // Token creation should succeed but mint will fail due to exceeding cap

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(exceedParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), alice);

        // Verify supply didn't increase
        address tokenAddress = fixedDenominationManager.getTokenAddressByTick("SMALL");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddress);
        assertEq(token.totalSupply(), 2000 ether); // Should still be at max
    }
    
    function testCannotTransferERC20Directly() public {
        // Setup
        testTokenMint();
        
        address tokenAddress = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddress);
        
        // Bob tries to transfer tokens directly (not via NFT) - should revert
        vm.prank(bob);
        vm.expectRevert(ERC20FixedDenomination.TransfersOnlyViaEthscriptions.selector);
        token.transfer(charlie, 500);
    }
    
    function testTokenAddressPredictability() public {
        // Predict the token address before deployment
        address predictedAddress = fixedDenominationManager.predictTokenAddressByTick("TEST");
        
        // Deploy the token
        testTokenDeploy();
        
        // Verify the actual address matches prediction
        address actualAddress = fixedDenominationManager.getTokenAddressByTick("TEST");
        assertEq(actualAddress, predictedAddress);
    }
    
    function testMintAmountMustMatch() public {
        // Deploy token with lim=1000
        testTokenDeploy();

        // Try to mint with wrong amount - should fail silently with event
        string memory wrongAmountContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"500"}';

        bytes32 wrongTxHash = bytes32(uint256(0xBAD));
        ERC20FixedDenominationManager.MintOperation memory wrongMintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1,
            amount: 500  // Wrong - should be 1000 to match lim
        });
        Ethscriptions.CreateEthscriptionParams memory wrongParams = createTokenParams(
            wrongTxHash,
            bob,
            wrongAmountContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(wrongMintOp)
        );

        // Token creation should succeed but mint will fail due to amount mismatch

        vm.prank(bob);
        uint256 tokenId = ethscriptions.createEthscription(wrongParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), bob);

        // Verify no tokens were minted
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 0); // Bob should have no tokens
    }
    
    function testCannotDeployTokenTwice() public {
        // First deploy should succeed
        testTokenDeploy();

        // Try to deploy the same token again with different parameters - should fail silently with event
        // Different max supply in content to avoid duplicate content error
        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"TEST","max":"2000000","lim":"2000"}';

        bytes32 duplicateTxHash = bytes32(uint256(0xABCD));
        ERC20FixedDenominationManager.DeployOperation memory duplicateDeployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: "TEST",
            maxSupply: 2000000,  // Different parameters but same tick
            mintAmount: 2000
        });

        Ethscriptions.CreateEthscriptionParams memory duplicateParams = createTokenParams(
            duplicateTxHash,
            alice,
            deployContent,
            CANONICAL_PROTOCOL,
            "deploy",
            abi.encode(duplicateDeployOp)
        );

        // Token creation should succeed but deploy will fail due to duplicate

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(duplicateParams);

        // Ethscription should still be created (but token deploy failed)
        assertEq(ethscriptions.ownerOf(tokenId), alice);

        // Verify the original token is still the only one
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.name(), "TEST");  // Token name format is "protocol tick"
        assertEq(token.maxSupply(), 1000000 ether); // Original cap (maxSupply), not the duplicate's
    }

    function testMintWithInvalidIdZero() public {
        // Deploy the token first
        testTokenDeploy();

        // Try to mint with ID 0 (invalid - must be >= 1)
        vm.prank(bob);
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"0","amt":"1000"}';

        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 0, // Invalid ID - should be >= 1
            amount: 1000
        });

        bytes32 invalidMintHash = bytes32(uint256(0xDEAD));
        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            invalidMintHash,
            bob,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        // Create the ethscription - mint should fail due to invalid ID
        uint256 tokenId = ethscriptions.createEthscription(mintParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), bob);

        // Verify no tokens were minted due to invalid ID
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 0); // Bob should have no tokens

        // Verify total minted didn't increase
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 0);
    }

    function testMintWithIdTooHigh() public {
        // Deploy the token first
        testTokenDeploy();

        // Try to mint with ID beyond maxId (maxSupply/mintAmount = 1000000/1000 = 1000)
        vm.prank(bob);
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1001","amt":"1000"}';

        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1001, // Invalid ID - maxId is 1000
            amount: 1000
        });

        bytes32 invalidMintHash = bytes32(uint256(0xBEEF));
        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            invalidMintHash,
            bob,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        // Create the ethscription - mint should fail due to ID too high
        uint256 tokenId = ethscriptions.createEthscription(mintParams);

        // Ethscription should still be created (but mint failed)
        assertEq(ethscriptions.ownerOf(tokenId), bob);

        // Verify no tokens were minted due to invalid ID
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 0); // Bob should have no tokens

        // Verify total minted didn't increase
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 0);
    }

    function testMintWithMaxValidId() public {
        // Deploy the token first
        testTokenDeploy();

        // Mint with the maximum valid ID (maxSupply/mintAmount = 1000000/1000 = 1000)
        vm.prank(bob);
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1000","amt":"1000"}';

        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1000, // Maximum valid ID
            amount: 1000
        });

        bytes32 validMintHash = bytes32(uint256(0xCAFE));
        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            validMintHash,
            bob,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        uint256 tokenId = ethscriptions.createEthscription(mintParams);

        // Verify Bob owns the mint ethscription NFT
        assertEq(ethscriptions.ownerOf(tokenId), bob);

        // Verify Bob has the tokens (1000 * 10^18 with 18 decimals)
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 1000 ether); // Should have tokens

        // Verify total minted increased
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 1000);
    }

    function testMintToNullOwnerMintsERC20ToZero() public {
        // Deploy the token under tick TEST
        testTokenDeploy();

        // Prepare a mint where the Ethscription initial owner is the null address
        bytes32 nullMintTx = bytes32(uint256(0xBADD0));
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"TEST","id":"1","amt":"1000"}';

        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "TEST",
            id: 1,
            amount: 1000
        });

        // Creator is Alice, but initial owner is address(0)
        Ethscriptions.CreateEthscriptionParams memory params = createTokenParams(
            nullMintTx,
            address(0),
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        vm.prank(alice);
        uint256 tokenId = ethscriptions.createEthscription(params);

        // The NFT should exist and end up owned by the null address
        assertEq(ethscriptions.ownerOf(tokenId), address(0));

        // ERC20 should be minted and credited to the null address
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.totalSupply(), 1000 ether);
        assertEq(token.balanceOf(address(0)), 1000 ether);

        // ERC20FixedDenominationManager should record a token item and increase total minted
        assertTrue(fixedDenominationManager.isTokenItem(nullMintTx));
        ERC20FixedDenominationManager.TokenInfo memory info = fixedDenominationManager.getTokenInfo(DEPLOY_TX_HASH);
        assertEq(info.totalMinted, 1000);
    }

    function testTransferTokenItemToNullAddressMovesERC20ToZero() public {
        // Setup: deploy and mint a token item to Bob
        testTokenMint();

        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("TEST");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);

        // Sanity: Bob has the ERC20 minted via the token item
        assertEq(token.balanceOf(bob), 1000 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), 1000 ether);

        // Transfer the NFT representing the token item to the null address
        Ethscriptions.Ethscription memory mintEthscription = ethscriptions.getEthscription(MINT_TX_HASH_1);
        vm.prank(bob);
        ethscriptions.transferEthscription(address(0), MINT_TX_HASH_1);

        // The NFT should now be owned by the null address
        assertEq(ethscriptions.ownerOf(mintEthscription.ethscriptionNumber), address(0));

        // ERC20 transfer follows NFT to null owner
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(0)), 1000 ether);
        assertEq(token.totalSupply(), 1000 ether);
    }

    // =============================================================
    //                    COLLECTION TESTS
    // =============================================================

    function testCollectionDeployedOnTokenDeploy() public {
        // Deploy a token as Alice
        vm.prank(alice);

        string memory deployContent = 'data:,{"p":"erc-20","op":"deploy","tick":"COLL","max":"10000","lim":"100"}';

        ERC20FixedDenominationManager.DeployOperation memory deployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: "COLL",
            maxSupply: 10000,
            mintAmount: 100
        });

        Ethscriptions.CreateEthscriptionParams memory params = createTokenParams(
            DEPLOY_TX_HASH,
            alice,
            deployContent,
            CANONICAL_PROTOCOL,
            "deploy",
            abi.encode(deployOp)
        );

        ethscriptions.createEthscription(params);

        // Verify collection was deployed
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);
        assertTrue(collectionAddr != address(0), "Collection should be deployed");

        // Verify collection properties
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);
        assertEq(collection.name(), "COLL");
        assertEq(collection.symbol(), "COLL");
        assertEq(collection.collectionId(), DEPLOY_TX_HASH);

        // Verify collection lookups work
        assertEq(fixedDenominationManager.collectionIdForAddress(collectionAddr), DEPLOY_TX_HASH);
        assertEq(fixedDenominationManager.collectionAddressForId(DEPLOY_TX_HASH), collectionAddr);
    }

    function testCollectionTokenMintedOnNoteMint() public {
        // First deploy
        testCollectionDeployedOnTokenDeploy();

        // Get collection address
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

        // Mint a note as Bob
        string memory mintContent = 'data:,{"p":"erc-20","op":"mint","tick":"COLL","id":"1","amt":"100"}';

        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: "COLL",
            id: 1,
            amount: 100
        });

        Ethscriptions.CreateEthscriptionParams memory mintParams = createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp)
        );

        vm.prank(bob);
        ethscriptions.createEthscription(mintParams);

        // Verify collection NFT was minted with tokenId = mintId
        assertEq(collection.ownerOf(1), bob, "Bob should own collection token #1");
        assertEq(collection.totalSupply(), 1, "Collection should have 1 NFT");

        // Verify ERC-20 tokens were also minted
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("COLL");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 100 ether, "Bob should have 100 tokens");
    }

    function testCollectionTokenTransferredOnNoteTransfer() public {
        // Setup: Deploy and mint
        testCollectionTokenMintedOnNoteMint();

        // Get collection
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

        // Get ERC-20 token
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("COLL");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);

        // Initial state
        assertEq(collection.ownerOf(1), bob);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(charlie), 0);

        // Transfer the mint inscription from Bob to Charlie
        vm.prank(bob);
        ethscriptions.transferEthscription(charlie, MINT_TX_HASH_1);

        // Verify both collection NFT and ERC-20 transferred
        assertEq(collection.ownerOf(1), charlie, "Charlie should now own collection token #1");
        assertEq(token.balanceOf(bob), 0, "Bob should have 0 tokens");
        assertEq(token.balanceOf(charlie), 100 ether, "Charlie should have 100 tokens");
    }

    function testCollectionTokenURI() public {
        // Setup: Deploy and mint
        testCollectionTokenMintedOnNoteMint();

        // Get collection
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

        // Get token URI
        string memory uri = collection.tokenURI(1);

        // Verify it starts with data URI prefix
        bytes memory uriBytes = bytes(uri);
        bytes memory expectedPrefix = bytes("data:application/json;base64,");
        for (uint i = 0; i < expectedPrefix.length; i++) {
            assertEq(uriBytes[i], expectedPrefix[i], "URI should start with JSON data prefix");
        }

        // Could decode and verify JSON contents but that would require base64 decoding
        // Just verify it doesn't revert and returns something
        assertTrue(bytes(uri).length > 30, "URI should have content");
    }

    function testCollectionMetadataView() public {
        // Setup: Deploy
        testCollectionDeployedOnTokenDeploy();

        // Get collection address
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);

        // Get collection metadata via manager
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata =
            fixedDenominationManager.getCollectionByAddress(collectionAddr);

        // Verify metadata
        assertEq(metadata.name, "COLL ERC-721");
        assertEq(metadata.symbol, "COLL-ERC-721");
        assertEq(metadata.maxSupply, 100); // 10000 maxSupply / 100 mintAmount = 100 notes
        assertEq(metadata.description, "Fixed denomination notes for COLL");
        assertEq(metadata.collectionContract, collectionAddr);
        assertFalse(metadata.locked);
    }

    function testCollectionItemView() public {
        // Setup: Deploy and mint
        testCollectionTokenMintedOnNoteMint();

        // Get collection item via manager
        ERC721EthscriptionsCollectionManager.CollectionItem memory item =
            fixedDenominationManager.getCollectionItem(DEPLOY_TX_HASH, 1);

        // Verify item metadata
        assertEq(item.ethscriptionId, MINT_TX_HASH_1);
        assertEq(item.name, "COLL #1");
        assertEq(item.description, "100 COLL note");
        assertEq(item.itemIndex, 1);

        // Verify attributes
        assertEq(item.attributes.length, 2);
        assertEq(item.attributes[0].traitType, "Denomination");
        assertEq(item.attributes[0].value, "100");
        assertEq(item.attributes[1].traitType, "Token");
        assertEq(item.attributes[1].value, "COLL");
    }

    function testCollectionMultipleMints() public {
        // Deploy
        testCollectionDeployedOnTokenDeploy();

        // Get collection
        address collectionAddr = fixedDenominationManager.getCollectionAddress(DEPLOY_TX_HASH);
        ERC721EthscriptionsCollection collection = ERC721EthscriptionsCollection(collectionAddr);

        // Mint note #1 as Bob
        string memory mintContent1 = 'data:,{"p":"erc-20","op":"mint","tick":"COLL","id":"1","amt":"100"}';
        ERC20FixedDenominationManager.MintOperation memory mintOp1 = ERC20FixedDenominationManager.MintOperation({
            tick: "COLL",
            id: 1,
            amount: 100
        });
        Ethscriptions.CreateEthscriptionParams memory mintParams1 = createTokenParams(
            MINT_TX_HASH_1,
            bob,
            mintContent1,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp1)
        );
        vm.prank(bob);
        ethscriptions.createEthscription(mintParams1);

        // Mint note #2 as Charlie
        string memory mintContent2 = 'data:,{"p":"erc-20","op":"mint","tick":"COLL","id":"2","amt":"100"}';
        ERC20FixedDenominationManager.MintOperation memory mintOp2 = ERC20FixedDenominationManager.MintOperation({
            tick: "COLL",
            id: 2,
            amount: 100
        });
        Ethscriptions.CreateEthscriptionParams memory mintParams2 = createTokenParams(
            MINT_TX_HASH_2,
            charlie,
            mintContent2,
            CANONICAL_PROTOCOL,
            "mint",
            abi.encode(mintOp2)
        );
        vm.prank(charlie);
        ethscriptions.createEthscription(mintParams2);

        // Verify both collection NFTs exist with correct owners
        assertEq(collection.ownerOf(1), bob, "Bob should own collection token #1");
        assertEq(collection.ownerOf(2), charlie, "Charlie should own collection token #2");
        assertEq(collection.totalSupply(), 2, "Collection should have 2 NFTs");

        // Verify both have correct ERC-20 balances
        address tokenAddr = fixedDenominationManager.getTokenAddressByTick("COLL");
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(charlie), 100 ether);
    }
}
