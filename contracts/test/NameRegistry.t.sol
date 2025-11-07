// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "./TestSetup.sol";
import "../src/NameRegistry.sol";

contract NameRegistryTest is TestSetup {
    NameRegistry internal registry;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public override {
        super.setUp();
        registry = NameRegistry(Predeploys.NAME_REGISTRY);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function testRegisterWordCreatesToken() public {
        bytes32 txHash = keccak256("alpha");
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(txHash, alice, "data:,alpha", false);
        params.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "word-domains",
            operation: "register",
            data: abi.encode("alpha")
        });

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 expectedTokenId = ethscriptions.getTokenId(txHash);
        bytes32 nameKey = registry.nameKeyForToken(expectedTokenId);
        NameRegistry.DomainInfo memory info = registry.getDomainInfo(nameKey);

        assertEq(info.name, "alpha");
        assertEq(info.owner, alice);
        assertEq(info.tokenId, expectedTokenId);
        assertEq(registry.ownerOf(info.tokenId), alice);
        assertEq(info.ethscriptionId, txHash);
        assertEq(registry.tokenIdForNameKey(nameKey), expectedTokenId);
        assertEq(registry.nameKeyForToken(expectedTokenId), nameKey);
    }

    function testPrimarySetAndClear() public {
        bytes32 txHash = keccak256("beta");
        Ethscriptions.CreateEthscriptionParams memory registerParams = createTestParams(txHash, alice, "data:,beta", false);
        registerParams.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "word-domains",
            operation: "register",
            data: abi.encode("beta")
        });

        vm.prank(alice);
        ethscriptions.createEthscription(registerParams);

        // Set primary via second inscription
        bytes32 setPrimaryTx = keccak256("set-primary");
        Ethscriptions.CreateEthscriptionParams memory primaryParams = createTestParams(
            setPrimaryTx,
            alice,
            'data:,{"p":"word-domains","op":"set_primary","name":"beta"}',
            false
        );
        primaryParams.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "word-domains",
            operation: "set_primary",
            data: abi.encode("beta")
        });

        vm.prank(alice);
        ethscriptions.createEthscription(primaryParams);

        (,, bytes32 primaryEthscription) = registry.primaryName(alice);
        assertEq(primaryEthscription, txHash);

        // Clear primary
        bytes32 clearTx = keccak256("clear-primary");
        Ethscriptions.CreateEthscriptionParams memory clearParams = createTestParams(
            clearTx,
            alice,
            'data:,{"p":"word-domains","op":"set_primary","name":""}',
            false
        );
        clearParams.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "word-domains",
            operation: "set_primary",
            data: abi.encode("")
        });

        vm.prank(alice);
        ethscriptions.createEthscription(clearParams);

        (,, primaryEthscription) = registry.primaryName(alice);
        assertEq(primaryEthscription, bytes32(0));
    }

    function testTransfersMirrorCollection() public {
        bytes32 txHash = keccak256("gamma");
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(txHash, alice, "data:,gamma", false);
        params.protocolParams = Ethscriptions.ProtocolParams({
            protocolName: "word-domains",
            operation: "register",
            data: abi.encode("gamma")
        });

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        uint256 tokenId = ethscriptions.getTokenId(txHash);

        vm.prank(alice);
        ethscriptions.transferEthscription(bob, txHash);

        assertEq(registry.ownerOf(tokenId), bob);

        vm.prank(bob);
        vm.expectRevert(NameRegistry.TransfersDisabled.selector);
        registry.transferFrom(bob, alice, tokenId);
    }
}
