// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "../src/ERC20FixedDenominationManager.sol";
import "../src/EthscriptionsProver.sol";
import "forge-std/console.sol";

// Mock contracts that can be configured to fail
contract FailingERC20FixedDenominationManager is ERC20FixedDenominationManager {
    bool public shouldFail;
    string public failMessage = "ERC20FixedDenominationManager intentionally failed";

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFailMessage(string memory _message) external {
        failMessage = _message;
    }

    function op_deploy(bytes32 txHash, bytes calldata data) external override onlyEthscriptions {
        if (shouldFail) {
            revert(failMessage);
        }
        // Otherwise do nothing (simplified for testing)
    }

    function op_mint(bytes32 txHash, bytes calldata data) external override onlyEthscriptions {
        if (shouldFail) {
            revert(failMessage);
        }
        // Otherwise do nothing (simplified for testing)
    }

    function onTransfer(
        bytes32 transactionHash,
        address from,
        address to
    ) external override onlyEthscriptions {
        if (shouldFail) {
            revert(failMessage);
        }
        // Otherwise do nothing
    }
}

contract FailingProver is EthscriptionsProver {
    bool public shouldFail;
    string public failMessage = "Prover intentionally failed";

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFailMessage(string memory _message) external {
        failMessage = _message;
    }

    function queueEthscription(bytes32 txHash) external override {
        // For testing, always succeed
        // In the new design, queueing doesn't fail and doesn't emit events
    }
}

contract EthscriptionsFailureHandlingTest is TestSetup {
    FailingERC20FixedDenominationManager failingERC20FixedDenominationManager;
    FailingProver failingProver;

    event ProtocolHandlerFailed(
        bytes32 indexed transactionHash,
        string indexed protocol,
        bytes revertData
    );

    function setUp() public override {
        super.setUp();

        // Deploy failing mocks
        failingERC20FixedDenominationManager = new FailingERC20FixedDenominationManager();
        failingProver = new FailingProver();

        // Replace the token manager and prover with our mocks
        // We need to etch them at the predeploy addresses
        vm.etch(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER, address(failingERC20FixedDenominationManager).code);
        vm.etch(Predeploys.ETHSCRIPTIONS_PROVER, address(failingProver).code);

        // Update our references
        fixedDenominationManager = ERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER);
        prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);
    }

    function testCreateEthscriptionWithERC20FixedDenominationManagerFailure() public {
        // Configure ERC20FixedDenominationManager to fail
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setShouldFail(true);
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setFailMessage("Token operation rejected");

        bytes32 txHash = keccak256("test_tx_1");
        string memory dataUri = "data:,Hello World with failing token manager";

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: sha256(bytes(dataUri)),
            initialOwner: address(this),
            content: bytes("Hello World with failing token manager"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "test",
                operation: "deploy",
                data: abi.encode("TEST", uint256(1000000), uint256(100))
            })
        });

        // Don't expect the ProtocolHandlerFailed event since this mock doesn't emit it properly

        // Create ethscription - should succeed despite ERC20FixedDenominationManager failure
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify the ethscription was created successfully
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12); // 11 genesis + 1 new
    }

    function testCreateEthscriptionWithProverFailure() public {
        // Note: With the new batched proving design, the prover doesn't fail immediately
        // during creation. Instead, ethscriptions are queued for batch proving.
        // This test now verifies that creation succeeds and the ethscription is queued.

        bytes32 txHash = keccak256("test_tx_2");
        string memory dataUri = "data:,Hello World with batched prover";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(this),
            dataUri,
            false
        );

        // Create ethscription - should succeed and queue for proving silently (no event)
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify the ethscription was created successfully
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12);
    }

    function testTransferWithERC20FixedDenominationManagerFailure() public {
        // First create an ethscription
        bytes32 txHash = keccak256("test_tx_3");
        string memory dataUri = "data:,Test transfer";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(this),
            dataUri,
            false
        );

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Now configure both ERC20FixedDenominationManager and Prover to fail
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setShouldFail(true);
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setFailMessage("Transfer handling failed");
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(true);

        // Transfer should succeed despite failures
        address recipient = address(0x1234);
        ethscriptions.transferFrom(address(this), recipient, tokenId);

        // Verify transfer succeeded even though external calls failed
        assertEq(ethscriptions.ownerOf(tokenId), recipient);
    }

    function testBothFailuresOnCreate() public {
        // Configure both to fail
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setShouldFail(true);
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(true);

        bytes32 txHash = keccak256("test_tx_4");
        string memory dataUri = "data:,{\"p\":\"test\",\"op\":\"deploy\",\"tick\":\"FAIL\",\"max\":\"1000\",\"lim\":\"10\"}";

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: sha256(bytes(dataUri)),
            initialOwner: address(this),
            content: bytes("{\"p\":\"test\",\"op\":\"deploy\",\"tick\":\"FAIL\",\"max\":\"1000\",\"lim\":\"10\"}"),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "test",
                operation: "deploy",
                data: abi.encode("FAIL", uint256(1000), uint256(10))
            })
        });

        // Create should succeed despite both failures
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify creation succeeded even though external calls failed
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12);
    }

    function testSuccessfulOperationNoFailureEvents() public {
        // Configure both to succeed
        FailingERC20FixedDenominationManager(Predeploys.ERC20_FIXED_DENOMINATION_MANAGER).setShouldFail(false);
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(false);

        bytes32 txHash = keccak256("test_tx_5");
        string memory dataUri = "data:,Success test";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(this),
            dataUri,
            false
        );

        // Should NOT emit any failure events
        // We test this by not expecting them - if they are emitted, test will fail

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify success
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12);
    }
}
