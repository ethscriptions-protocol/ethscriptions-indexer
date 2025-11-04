// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";
import {Predeploys} from "../src/libraries/Predeploys.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}

contract Multicall3Test is TestSetup {
    IMulticall3 multicall;

    function setUp() public override {
        super.setUp();
        multicall = IMulticall3(Predeploys.MultiCall3);
    }

    function testMulticall3Deployed() public view {
        // Check that Multicall3 is deployed
        uint256 codeSize;
        address multicall3Addr = Predeploys.MultiCall3;
        assembly {
            codeSize := extcodesize(multicall3Addr)
        }
        assertGt(codeSize, 0, "Multicall3 should be deployed");
    }

    function testMulticall3BatchGetEthscriptions() public {
        // Create some test ethscriptions first
        bytes32[] memory txHashes = new bytes32[](3);
        uint256[] memory tokenIds = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            bytes32 txHash = bytes32(uint256(1000 + i));
            address creator = address(uint160(100 + i));
            address initialOwner = address(uint160(200 + i));

            vm.prank(creator);
            Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash,
                contentUriHash: keccak256(abi.encodePacked("data:text/plain,Test", i)),
                initialOwner: initialOwner,
                content: bytes(string(abi.encodePacked("Test content ", Strings.toString(i)))),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "",
                    operation: "",
                    data: ""
                })
            });

            tokenIds[i] = ethscriptions.createEthscription(params);
            txHashes[i] = txHash;
        }

        // Now use Multicall3 to batch query all three ethscriptions
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](3);

        for (uint256 i = 0; i < 3; i++) {
            // Call getEthscription(bytes32, bool) with includeContent = true
            calls[i] = IMulticall3.Call3({
                target: address(ethscriptions),
                allowFailure: false,
                callData: abi.encodeWithSignature("getEthscription(bytes32,bool)", txHashes[i], true)
            });
        }

        // Execute multicall
        IMulticall3.Result[] memory results = multicall.aggregate3(calls);

        // Verify results
        assertEq(results.length, 3, "Should return 3 results");

        for (uint256 i = 0; i < 3; i++) {
            assertTrue(results[i].success, "Call should succeed");

            // Decode the result
            Ethscriptions.Ethscription memory ethscription = abi.decode(
                results[i].returnData,
                (Ethscriptions.Ethscription)
            );

            // Verify data
            assertEq(ethscription.ethscriptionId, txHashes[i], "Ethscription ID should match");
            assertEq(ethscription.ethscriptionNumber, tokenIds[i], "Token ID should match");
            assertEq(ethscription.creator, address(uint160(100 + i)), "Creator should match");
            assertEq(ethscription.currentOwner, address(uint160(200 + i)), "Owner should match");
            assertEq(ethscription.mimetype, "text/plain", "Mimetype should match");
            assertEq(string(ethscription.content), string(abi.encodePacked("Test content ", Strings.toString(i))), "Content should match");
        }
    }

    function testMulticall3MixedCalls() public {
        // Create an ethscription
        bytes32 txHash = bytes32(uint256(5000));
        address creator = address(0x123);
        address initialOwner = address(0x456);

        vm.prank(creator);
        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256("data:text/plain,Mixed test"),
            initialOwner: initialOwner,
            content: bytes("Mixed test content"),
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        });

        uint256 tokenId = ethscriptions.createEthscription(params);

        // Prepare mixed calls
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](4);

        // Call 1: Get total supply
        calls[0] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: false,
            callData: abi.encodeWithSignature("totalSupply()")
        });

        // Call 2: Get balance of owner
        calls[1] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: false,
            callData: abi.encodeWithSignature("balanceOf(address)", initialOwner)
        });

        // Call 3: Get ethscription with content
        calls[2] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: false,
            callData: abi.encodeWithSignature("getEthscription(bytes32,bool)", txHash, true)
        });

        // Call 4: Get ethscription without content
        calls[3] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: false,
            callData: abi.encodeWithSignature("getEthscription(bytes32,bool)", txHash, false)
        });

        // Execute multicall
        IMulticall3.Result[] memory results = multicall.aggregate3(calls);

        // Verify results
        assertEq(results.length, 4, "Should return 4 results");

        // Check total supply
        assertTrue(results[0].success, "Total supply call should succeed");
        uint256 totalSupply = abi.decode(results[0].returnData, (uint256));
        assertGt(totalSupply, 0, "Total supply should be > 0");

        // Check balance
        assertTrue(results[1].success, "Balance call should succeed");
        uint256 balance = abi.decode(results[1].returnData, (uint256));
        assertEq(balance, 1, "Balance should be 1");

        // Check ethscription with content
        assertTrue(results[2].success, "Get with content should succeed");
        Ethscriptions.Ethscription memory withContent = abi.decode(
            results[2].returnData,
            (Ethscriptions.Ethscription)
        );
        assertEq(withContent.content.length, 18, "Content should be present");

        // Check ethscription without content
        assertTrue(results[3].success, "Get without content should succeed");
        Ethscriptions.Ethscription memory withoutContent = abi.decode(
            results[3].returnData,
            (Ethscriptions.Ethscription)
        );
        assertEq(withoutContent.content.length, 0, "Content should be empty");
    }

    function testMulticall3WithFailure() public {
        // Test that allowFailure works correctly
        bytes32 nonExistentTxHash = bytes32(uint256(99999));

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](2);

        // Call 1: Valid call - get total supply
        calls[0] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: false,
            callData: abi.encodeWithSignature("totalSupply()")
        });

        // Call 2: Invalid call - get non-existent ethscription with allowFailure = true
        calls[1] = IMulticall3.Call3({
            target: address(ethscriptions),
            allowFailure: true,
            callData: abi.encodeWithSignature("getEthscription(bytes32)", nonExistentTxHash)
        });

        // Execute multicall - should not revert due to allowFailure
        IMulticall3.Result[] memory results = multicall.aggregate3(calls);

        // Verify results
        assertEq(results.length, 2, "Should return 2 results");
        assertTrue(results[0].success, "First call should succeed");
        assertFalse(results[1].success, "Second call should fail but be caught");
    }
}