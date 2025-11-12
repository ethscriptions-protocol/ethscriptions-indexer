// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/libraries/Predeploys.sol";
import "../src/libraries/Proxy.sol";
import "../src/ERC20FixedDenominationManager.sol";
import "../src/ERC721EthscriptionsCollectionManager.sol";
import "../src/Ethscriptions.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./TestSetup.sol";

contract AddressPredictionTest is TestSetup {
    // Test predictable address for ERC20FixedDenominationManager token proxies
    function testPredictERC20FixedDenominationTokenAddress() public {
        // Arrange
        string memory tick = "eths";
        bytes32 deployTxHash = keccak256("deploy-eths");

        // Prepare deploy op data
        ERC20FixedDenominationManager.DeployOperation memory deployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: tick,
            maxSupply: 1_000_000,
            mintAmount: 1_000
        });
        bytes memory data = abi.encode(deployOp);

        // Prediction via contract helper
        address predicted = fixedDenominationManager.predictTokenAddressByTick(tick);

        // Act: call deploy as Ethscriptions (authorized)
        vm.prank(Predeploys.ETHSCRIPTIONS);
        fixedDenominationManager.op_deploy(deployTxHash, data);

        // Assert actual matches predicted
        address actual = fixedDenominationManager.getTokenAddressByTick(tick);
        assertEq(actual, predicted, "Predicted token address should match actual deployed proxy");
    }

    // Test predictable address for ERC721EthscriptionsCollectionManager collection proxies
    function testPredictCollectionsAddress() public {
        // Arrange
        bytes32 collectionId = keccak256("collection-1");
        address creator = makeAddr("creator");

        // First, create the ethscription that will represent this collection
        Ethscriptions.CreateEthscriptionParams memory ethscriptionParams = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: collectionId,
            contentUriSha: keccak256("collection-content"),
            initialOwner: creator,
            content: bytes("collection-content"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        vm.prank(creator);
        ethscriptions.createEthscription(ethscriptionParams);

        ERC721EthscriptionsCollectionManager.CollectionParams memory metadata =
            ERC721EthscriptionsCollectionManager.CollectionParams({
                name: "My Collection",
                symbol: "MYC",
                maxSupply: 1000,
                description: "A test collection",
                logoImageUri: "data:,logo",
                bannerImageUri: "data:,banner",
                backgroundColor: "#000000",
                websiteLink: "https://example.com",
                twitterLink: "",
                discordLink: "",
                merkleRoot: bytes32(0),
                initialOwner: address(this)  // Use test contract as owner
            });

        // Manually compute predicted proxy address
        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(collectionsHandler)));
        address predicted = Create2.computeAddress(collectionId, keccak256(creationCode), address(collectionsHandler));

        // Act: create collection as Ethscriptions (authorized)
        vm.prank(Predeploys.ETHSCRIPTIONS);
        collectionsHandler.op_create_collection(collectionId, abi.encode(metadata));

        // Assert deployed matches predicted
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory collection =
            collectionsHandler.getCollection(collectionId);
        address actual = collection.collectionContract;
        assertEq(actual, predicted, "Predicted collection address should match actual deployed proxy");
    }
}
