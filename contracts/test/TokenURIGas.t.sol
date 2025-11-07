// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";
import "forge-std/console.sol";

contract TokenURIGasTest is TestSetup {
    address alice = address(0x1);

    function setUp() public override {
        super.setUp();
    }

    function testGas_TokenURI_Scaling() public {
        console.log("=== TokenURI Gas Cost vs Content Size ===");
        console.log("");

        // Test 1KB
        // measureGasForSize(1_000, "1KB");

        // Test 10KB
        // measureGasForSize(10_000, "10KB");

        // Test 100KB only to see detailed gas breakdown
        measureGasForSize(100_000, "100KB");
    }

    function measureGasForSize(uint256 contentSize, string memory label) internal {
        // Create content of specified size
        bytes memory content = new bytes(contentSize);
        for (uint256 i = 0; i < contentSize; i++) {
            content[i] = bytes1(uint8((i * 7) % 256)); // Pseudo-random pattern
        }

        bytes32 txHash = keccak256(bytes(label));

        // Create the ethscription
        vm.prank(alice);
        ethscriptions.createEthscription(Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriSha: keccak256(bytes(string.concat("data:image/png;base64,", label))),
            initialOwner: alice,
            content: content,
            mimetype: "image/png",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "",
                operation: "",
                data: ""
            })
        }));

        uint256 tokenId = ethscriptions.getTokenId(txHash);

        // Measure gas for tokenURI call
        uint256 gasStart = gasleft();
        string memory uri = ethscriptions.tokenURI(tokenId);
        uint256 gasUsed = gasStart - gasleft();

        console.log(string.concat(label, ":"));
        console.log("  Gas used:", gasUsed);
        console.log("  Gas per byte:", gasUsed / contentSize);
        console.log("  URI length:", bytes(uri).length);
        console.log("");
    }
}