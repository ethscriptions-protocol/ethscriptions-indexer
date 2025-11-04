// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";
import "forge-std/console.sol";

contract PaginationGas1000SimpleTest is TestSetup {

    // Override to create more ethscriptions
    function setUp() public override {
        super.setUp();

        // Start from a higher ID range to avoid conflicts
        uint256 startId = 0x2000000;
        uint256 targetCount = 1000;
        uint256 existingCount = ethscriptions.totalSupply();
        uint256 toCreate = targetCount > existingCount ? targetCount - existingCount : 0;

        console.log("Existing ethscriptions:", existingCount);
        console.log("Creating additional:", toCreate);

        // Create enough ethscriptions to reach 1000
        for (uint256 i = 0; i < toCreate; i++) {
            bytes32 txHash = bytes32(uint256(startId + i));
            address creator = address(uint160(0x5000 + (i % 20)));
            address owner = address(uint160(0x6000 + (i % 10)));

            // Small content to minimize gas
            bytes memory content = new bytes(10);
            for (uint256 j = 0; j < 10; j++) {
                content[j] = bytes1(uint8(j));
            }

            vm.prank(creator);
            Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash,
                contentUriHash: keccak256(abi.encodePacked("uri", startId + i)),
                initialOwner: owner,
                content: content,
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "",
                    operation: "",
                    data: ""
                })
            });

            ethscriptions.createEthscription(params);

            // Log progress every 100
            if ((i + 1) % 100 == 0) {
                console.log("  Progress:", i + 1, "of", toCreate);
            }
        }

        uint256 finalCount = ethscriptions.totalSupply();
        console.log("Total ethscriptions now:", finalCount);
        console.log("");
    }

    function testGas_1000ItemsWithoutContent() public view {
        uint256 totalSupply = ethscriptions.totalSupply();
        console.log("=== Testing Maximum Pagination Limits ===");
        console.log("Total ethscriptions available:", totalSupply);
        console.log("");

        // Test increasing sizes
        uint256[] memory sizes = new uint256[](7);
        sizes[0] = 100;
        sizes[1] = 250;
        sizes[2] = 500;
        sizes[3] = 750;
        sizes[4] = 900;
        sizes[5] = 1000;
        sizes[6] = 1100; // Should clamp to 1000

        console.log("Testing WITHOUT content:");
        console.log("");

        for (uint256 i = 0; i < sizes.length; i++) {
            if (sizes[i] > totalSupply) {
                console.log("Skipping size", sizes[i], "- not enough ethscriptions");
                continue;
            }

            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(0, sizes[i], false);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Request size:", sizes[i]);
            console.log("  Items returned:", result.items.length);
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);

            // Check if we hit the limit
            if (sizes[i] > 1000 && result.items.length == 1000) {
                console.log("  (Clamped to max limit of 1000)");
            }
            console.log("");
        }
    }

    function testGas_50ItemsWithContent() public view {
        console.log("=== Testing WITH content limits ===");
        console.log("");

        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 20;
        sizes[1] = 30;
        sizes[2] = 40;
        sizes[3] = 50;
        sizes[4] = 60; // Should clamp to 50

        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(0, sizes[i], true);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Request size:", sizes[i]);
            console.log("  Items returned:", result.items.length);
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);

            if (sizes[i] > 50 && result.items.length == 50) {
                console.log("  (Clamped to max limit of 50)");
            }
            console.log("");
        }
    }

    function testGas_CheckLimitsWork() public view {
        console.log("=== Verifying Limit Clamping ===");
        console.log("");

        // Test that requesting more than limit gets clamped
        Ethscriptions.PaginatedEthscriptionsResponse memory result;

        // Test without content - should clamp at 1000
        result = ethscriptions.getEthscriptions(0, 5000, false);
        console.log("Requested 5000 without content, got:", result.items.length);
        require(result.items.length <= 1000, "Should clamp to 1000");

        // Test with content - should clamp at 50
        result = ethscriptions.getEthscriptions(0, 500, true);
        console.log("Requested 500 with content, got:", result.items.length);
        require(result.items.length <= 50, "Should clamp to 50");

        console.log("");
        console.log("Limit clamping verified!");
    }
}