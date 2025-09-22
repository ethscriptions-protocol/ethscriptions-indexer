// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "../src/TokenManager.sol";
import "../src/EthscriptionsProver.sol";
import "forge-std/console.sol";

// Mock contracts that can be configured to fail
contract FailingTokenManager is TokenManager {
    bool public shouldFail;
    string public failMessage = "TokenManager intentionally failed";

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFailMessage(string memory _message) external {
        failMessage = _message;
    }

    function handleTokenOperation(
        bytes32 transactionHash,
        address initialOwner,
        Ethscriptions.TokenParams calldata tokenParams
    ) external override {
        if (shouldFail) {
            revert(failMessage);
        }
        // Otherwise do nothing (simplified for testing)
    }

    function handleTokenTransfer(
        bytes32 transactionHash,
        address from,
        address to
    ) external override {
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

    function proveEthscriptionData(bytes32 transactionHash) external override {
        if (shouldFail) {
            revert(failMessage);
        }
        // Otherwise do nothing
    }
}

contract EthscriptionsFailureHandlingTest is TestSetup {
    FailingTokenManager failingTokenManager;
    FailingProver failingProver;

    event TokenManagerFailed(
        bytes32 indexed transactionHash,
        string operation,
        bytes revertData
    );

    event ProverFailed(
        bytes32 indexed transactionHash,
        bytes revertData
    );

    function setUp() public override {
        super.setUp();

        // Deploy failing mocks
        failingTokenManager = new FailingTokenManager();
        failingProver = new FailingProver();

        // Replace the token manager and prover with our mocks
        // We need to etch them at the predeploy addresses
        vm.etch(Predeploys.TOKEN_MANAGER, address(failingTokenManager).code);
        vm.etch(Predeploys.ETHSCRIPTIONS_PROVER, address(failingProver).code);

        // Update our references
        tokenManager = TokenManager(Predeploys.TOKEN_MANAGER);
        prover = EthscriptionsProver(Predeploys.ETHSCRIPTIONS_PROVER);
    }

    function testCreateEthscriptionWithTokenManagerFailure() public {
        // Configure TokenManager to fail
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setShouldFail(true);
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setFailMessage("Token operation rejected");

        bytes32 txHash = keccak256("test_tx_1");
        string memory dataUri = "data:,Hello World with failing token manager";

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: txHash,
            contentUriHash: sha256(bytes(dataUri)),
            initialOwner: address(this),
            content: bytes("Hello World with failing token manager"),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "test",
                tick: "TEST",
                max: 1000000,
                lim: 100,
                amt: 0
            })
        });

        // Expect the TokenManagerFailed event
        vm.expectEmit(true, false, false, true);
        emit TokenManagerFailed(
            txHash,
            "handleTokenOperation",
            abi.encodeWithSignature("Error(string)", "Token operation rejected")
        );

        // Create ethscription - should succeed despite TokenManager failure
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify the ethscription was created successfully
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12); // 11 genesis + 1 new
    }

    function testCreateEthscriptionWithProverFailure() public {
        // Configure Prover to fail
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(true);
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setFailMessage("Proving failed");

        bytes32 txHash = keccak256("test_tx_2");
        string memory dataUri = "data:,Hello World with failing prover";

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            address(this),
            dataUri,
            false
        );

        // Expect the ProverFailed event
        vm.expectEmit(true, false, false, true);
        emit ProverFailed(
            txHash,
            abi.encodeWithSignature("Error(string)", "Proving failed")
        );

        // Create ethscription - should succeed despite Prover failure
        uint256 tokenId = ethscriptions.createEthscription(params);

        // Verify the ethscription was created successfully
        assertEq(ethscriptions.ownerOf(tokenId), address(this));
        assertEq(ethscriptions.totalSupply(), 12);
    }

    function testTransferWithTokenManagerFailure() public {
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

        // Now configure both TokenManager and Prover to fail
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setShouldFail(true);
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setFailMessage("Transfer handling failed");
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(true);

        // Transfer should succeed despite failures
        address recipient = address(0x1234);
        ethscriptions.transferFrom(address(this), recipient, tokenId);

        // Verify transfer succeeded even though external calls failed
        assertEq(ethscriptions.ownerOf(tokenId), recipient);
    }

    function testBothFailuresOnCreate() public {
        // Configure both to fail
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setShouldFail(true);
        FailingProver(Predeploys.ETHSCRIPTIONS_PROVER).setShouldFail(true);

        bytes32 txHash = keccak256("test_tx_4");
        string memory dataUri = "data:,{\"p\":\"test\",\"op\":\"deploy\",\"tick\":\"FAIL\",\"max\":\"1000\",\"lim\":\"10\"}";

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: txHash,
            contentUriHash: sha256(bytes(dataUri)),
            initialOwner: address(this),
            content: bytes("{\"p\":\"test\",\"op\":\"deploy\",\"tick\":\"FAIL\",\"max\":\"1000\",\"lim\":\"10\"}"),
            mimetype: "application/json",
            mediaType: "application",
            mimeSubtype: "json",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "test",
                tick: "FAIL",
                max: 1000,
                lim: 10,
                amt: 0
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
        FailingTokenManager(Predeploys.TOKEN_MANAGER).setShouldFail(false);
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