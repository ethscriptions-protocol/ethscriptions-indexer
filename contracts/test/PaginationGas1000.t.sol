// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";
import "forge-std/console.sol";

contract PaginationGas1000Test is TestSetup {

    // Create 1200 ethscriptions for full testing
    function setUp() public override {
        super.setUp();

        console.log("Creating 1200 ethscriptions for full pagination testing...");

        // Create 1200 ethscriptions with small content (to minimize setup gas)
        for (uint256 i = 0; i < 1200; i++) {
            bytes32 txHash = bytes32(uint256(0x1000000 + i));
            address creator = address(uint160(0x100 + (i % 20))); // 20 different creators
            address owner = address(uint160(0x200 + (i % 10)));   // 10 different owners

            // Use small content to keep setup gas manageable
            bytes memory content = new bytes(10 + (i % 20)); // 10-30 bytes
            for (uint256 j = 0; j < content.length; j++) {
                content[j] = bytes1(uint8(j % 256));
            }

            vm.prank(creator);
            Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash,
                contentUriHash: keccak256(abi.encodePacked("uri", i)),
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

            // Log progress every 100 items
            if ((i + 1) % 100 == 0) {
                console.log("  Created:", i + 1);
            }
        }

        uint256 total = ethscriptions.totalSupply();
        console.log("Setup complete: Total ethscriptions =", total);
        console.log("");
    }

    function testGas_Full1000_WithoutContent() public view {
        console.log("=== Testing FULL 1000 items WITHOUT content ===");
        console.log("");

        // Test various large page sizes without content
        uint256[] memory pageSizes = new uint256[](8);
        pageSizes[0] = 100;
        pageSizes[1] = 200;
        pageSizes[2] = 300;
        pageSizes[3] = 500;
        pageSizes[4] = 750;
        pageSizes[5] = 900;
        pageSizes[6] = 1000;
        pageSizes[7] = 1100; // Should be clamped to 1000

        for (uint256 i = 0; i < pageSizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(0, pageSizes[i], false);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Requested:", pageSizes[i], "items");
            console.log("  Returned:", result.items.length, "items");
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);
            console.log("  Has more:", result.hasMore);
            console.log("");
        }
    }

    function testGas_Full50_WithContent() public view {
        console.log("=== Testing FULL 50 items WITH content ===");
        console.log("");

        // Test the maximum with content
        uint256[] memory pageSizes = new uint256[](4);
        pageSizes[0] = 30;
        pageSizes[1] = 40;
        pageSizes[2] = 50;
        pageSizes[3] = 60; // Should be clamped to 50

        for (uint256 i = 0; i < pageSizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(0, pageSizes[i], true);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Requested:", pageSizes[i], "items");
            console.log("  Returned:", result.items.length, "items");
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);
            console.log("");
        }
    }

    function testGas_PaginationFlow() public view {
        console.log("=== Testing Pagination Flow (multiple pages) ===");
        console.log("");

        // Test fetching multiple pages sequentially
        uint256 pageSize = 250;
        uint256 totalFetched = 0;
        uint256 totalGasUsed = 0;
        uint256 pageNum = 0;

        Ethscriptions.PaginatedEthscriptionsResponse memory page;
        uint256 start = 0;

        console.log("Fetching pages of", pageSize, "items without content:");
        console.log("");

        while (totalFetched < 1000 && pageNum < 10) { // Safety limit of 10 pages
            uint256 gasStart = gasleft();
            page = ethscriptions.getEthscriptions(start, pageSize, false);
            uint256 gasUsed = gasStart - gasleft();

            totalFetched += page.items.length;
            totalGasUsed += gasUsed;
            pageNum++;

            console.log("Page", pageNum);
            console.log("  Start index:", start);
            console.log("  Items returned:", page.items.length);
            console.log("  Gas used:", gasUsed);
            console.log("  Has more:", page.hasMore);

            if (!page.hasMore || page.items.length == 0) {
                break;
            }

            start = page.nextStart;
        }

        console.log("");
        console.log("Summary:");
        console.log("  Total pages:", pageNum);
        console.log("  Total items fetched:", totalFetched);
        console.log("  Total gas used:", totalGasUsed);
        console.log("  Average gas per item:", totalFetched > 0 ? totalGasUsed / totalFetched : 0);
    }

    function testGas_EdgeCaseLargePagination() public {
        console.log("=== Testing Edge Cases with Large Dataset ===");
        console.log("");

        // Test starting from middle of dataset
        console.log("Starting from index 500, requesting 600 items:");
        uint256 gasStart = gasleft();
        Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(500, 600, false);
        uint256 gasUsed = gasStart - gasleft();

        console.log("  Returned:", result.items.length, "items");
        console.log("  Gas used:", gasUsed);
        console.log("  Next start:", result.nextStart);
        console.log("  Has more:", result.hasMore);
        console.log("");

        // Test at the end of dataset
        console.log("Starting from index 1100, requesting 200 items:");
        gasStart = gasleft();
        result = ethscriptions.getEthscriptions(1100, 200, false);
        gasUsed = gasStart - gasleft();

        console.log("  Returned:", result.items.length, "items");
        console.log("  Gas used:", gasUsed);
        console.log("");

        // Try to break it with huge request
        console.log("Attempting to request 10000 items (should clamp to 1000):");
        gasStart = gasleft();
        result = ethscriptions.getEthscriptions(0, 10000, false);
        gasUsed = gasStart - gasleft();

        console.log("  SUCCESS - Returned:", result.items.length, "items");
        console.log("  Gas used:", gasUsed);
    }
}