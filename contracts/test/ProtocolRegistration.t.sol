// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "../src/interfaces/IProtocolHandler.sol";

/// @title Protocol Registration Tests
/// @notice Tests for concurrent protocol handler registration and related edge cases
contract ProtocolRegistrationTest is TestSetup {
    address alice = address(0xa11ce);
    address bob = address(0xb0b);
    address charlie = address(0xc0ffee);

    // Mock protocol handler for testing
    MockProtocolHandler mockHandler1;
    MockProtocolHandler mockHandler2;
    MockProtocolHandler mockHandler3;

    function setUp() public override {
        super.setUp();

        mockHandler1 = new MockProtocolHandler();
        mockHandler2 = new MockProtocolHandler();
        mockHandler3 = new MockProtocolHandler();
    }

    /// @notice Test that the same protocol cannot be registered twice
    function testCannotRegisterSameProtocolTwice() public {
        // Register a protocol
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("test-protocol", address(mockHandler1));

        // Verify it was registered
        assertEq(ethscriptions.protocolHandlers("test-protocol"), address(mockHandler1));

        // Try to register the same protocol again (should revert)
        vm.expectRevert(Ethscriptions.ProtocolAlreadyRegistered.selector);
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("test-protocol", address(mockHandler2));

        // Verify the original handler is still registered
        assertEq(ethscriptions.protocolHandlers("test-protocol"), address(mockHandler1));
    }

    /// @notice Test concurrent registration attempts of the same protocol
    /// @dev Simulates race condition where two handlers try to register simultaneously
    function testConcurrentRegistrationSameProtocol() public {
        // First registration succeeds
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("concurrent-test", address(mockHandler1));

        // Second registration with different handler fails
        vm.expectRevert(Ethscriptions.ProtocolAlreadyRegistered.selector);
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("concurrent-test", address(mockHandler2));

        // Verify only first handler is registered
        assertEq(ethscriptions.protocolHandlers("concurrent-test"), address(mockHandler1));
    }

    /// @notice Test that multiple different protocols can be registered
    function testRegisterMultipleDifferentProtocols() public {
        vm.startPrank(Predeploys.DEPOSITOR_ACCOUNT);

        // Register three different protocols
        ethscriptions.registerProtocol("protocol-1", address(mockHandler1));
        ethscriptions.registerProtocol("protocol-2", address(mockHandler2));
        ethscriptions.registerProtocol("protocol-3", address(mockHandler3));

        vm.stopPrank();

        // Verify all were registered correctly
        assertEq(ethscriptions.protocolHandlers("protocol-1"), address(mockHandler1));
        assertEq(ethscriptions.protocolHandlers("protocol-2"), address(mockHandler2));
        assertEq(ethscriptions.protocolHandlers("protocol-3"), address(mockHandler3));
    }

    /// @notice Test that protocol registration is restricted to authorized accounts
    function testUnauthorizedCannotRegisterProtocol() public {
        // Try to register from unauthorized account (should revert)
        vm.expectRevert(Ethscriptions.OnlyDepositor.selector);
        vm.prank(alice);
        ethscriptions.registerProtocol("unauthorized", address(mockHandler1));

        // Verify protocol was not registered
        assertEq(ethscriptions.protocolHandlers("unauthorized"), address(0));
    }

    /// @notice Test registration with zero address handler
    function testCannotRegisterZeroAddressHandler() public {
        vm.expectRevert(Ethscriptions.InvalidHandler.selector);
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("zero-handler", address(0));
    }

    /// @notice Test that pre-registered protocols (erc-20, collections) are already set
    function testPreRegisteredProtocols() public {
        // Verify fixed denomination protocol maps to ERC20FixedDenominationManager
        assertEq(ethscriptions.protocolHandlers("erc-20-fixed-denomination"), Predeploys.ERC20_FIXED_DENOMINATION_MANAGER);

        // Verify collections is registered to ERC721EthscriptionsCollectionManager
        assertEq(ethscriptions.protocolHandlers("erc-721-ethscriptions-collection"), Predeploys.ERC721_ETHSCRIPTIONS_COLLECTION_MANAGER);
    }

    /// @notice Test that ethscriptions with registered protocol call the handler on transfer
    function testRegisteredProtocolHandlerIsCalledOnTransfer() public {
        // Register a mock handler
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("mock-protocol", address(mockHandler1));

        // Create an ethscription with this protocol
        bytes32 txHash = bytes32(uint256(0x1234));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: sha256(bytes('data:,{"p":"mock-protocol","op":"test"}')),
            initialOwner: alice,
            content: bytes('{"p":"mock-protocol","op":"test"}'),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "mock-protocol",
                operation: "test",
                data: abi.encode(uint256(42))
            })
        });

        vm.prank(alice);
        ethscriptions.createEthscription(params);

        // Transfer it to trigger the handler
        vm.prank(alice);
        ethscriptions.transferEthscription(bob, txHash);

        // Verify the handler was called
        assertTrue(mockHandler1.transferCalled());
        assertEq(mockHandler1.lastTxHash(), txHash);
        assertEq(mockHandler1.lastFrom(), alice);
        assertEq(mockHandler1.lastTo(), bob);
    }

    /// @notice Test protocol registration with maximum length protocol name
    function testRegisterMaxLengthProtocolName() public {
        // Create a 50-character protocol name (if there's a limit)
        string memory longName = "protocol-with-a-very-long-name-12345678901234";

        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol(longName, address(mockHandler1));

        assertEq(ethscriptions.protocolHandlers(longName), address(mockHandler1));
    }

    /// @notice Test that unregistered protocols don't cause failures
    function testUnregisteredProtocolDoesNotRevert() public {
        bytes32 txHash = bytes32(uint256(0x5678));

        // Create ethscription with unregistered protocol
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: sha256(bytes('data:,{"p":"unregistered","op":"test"}')),
            initialOwner: alice,
            content: bytes('{"p":"unregistered","op":"test"}'),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "unregistered",
                operation: "test",
                data: ""
            })
        });

        // Should not revert - just creates ethscription without protocol handling
        vm.prank(alice);
        ethscriptions.createEthscription(params);

        // Verify ethscription was created
        Ethscriptions.Ethscription memory eth = ethscriptions.getEthscription(txHash);
        assertEq(eth.initialOwner, alice);
    }

    /// @notice Test registering protocol with non-contract address
    /// @dev This actually succeeds - validation happens when handler is called
    function testRegisterProtocolWithNonContractAddress() public {
        // EOA can be registered (validation happens at call time)
        vm.prank(Predeploys.DEPOSITOR_ACCOUNT);
        ethscriptions.registerProtocol("eoa-handler", alice);

        // Verify it was registered
        assertEq(ethscriptions.protocolHandlers("eoa-handler"), alice);
    }
}

/// @notice Mock protocol handler for testing
contract MockProtocolHandler is IProtocolHandler {
    bool public creationCalled;
    bool public transferCalled;
    bytes32 public lastTxHash;
    address public lastFrom;
    address public lastTo;

    function wasCreationCalled() external view returns (bool) {
        return creationCalled;
    }

    function onTransfer(
        bytes32 txHash,
        address from,
        address to
    ) external override {
        transferCalled = true;
        lastTxHash = txHash;
        lastFrom = from;
        lastTo = to;
    }

    function protocolName() external pure override returns (string memory) {
        return "mock-protocol";
    }
}
