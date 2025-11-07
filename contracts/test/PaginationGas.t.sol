// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./TestSetup.sol";
import "forge-std/console.sol";

contract PaginationGasTest is TestSetup {
    uint256 constant SMALL_CONTENT_SIZE = 10;      // 10 bytes
    uint256 constant MEDIUM_CONTENT_SIZE = 100;    // 100 bytes
    uint256 constant LARGE_CONTENT_SIZE = 1000;    // 1KB
    uint256 constant HUGE_CONTENT_SIZE = 10000;    // 10KB

    // Create ethscriptions with different content sizes for testing
    function setUp() public override {
        super.setUp();

        // Create ethscriptions with various content sizes
        // We'll create 100 ethscriptions to test pagination properly
        for (uint256 i = 0; i < 100; i++) {
            bytes32 txHash = bytes32(uint256(0x1000000 + i));
            address creator = address(uint160(0x100 + (i % 10))); // 10 different creators
            address owner = address(uint160(0x200 + (i % 5)));    // 5 different owners

            // Vary content size based on index
            bytes memory content;
            if (i % 4 == 0) {
                content = new bytes(SMALL_CONTENT_SIZE);
            } else if (i % 4 == 1) {
                content = new bytes(MEDIUM_CONTENT_SIZE);
            } else if (i % 4 == 2) {
                content = new bytes(LARGE_CONTENT_SIZE);
            } else {
                content = new bytes(HUGE_CONTENT_SIZE);
            }

            // Fill content with some data
            for (uint256 j = 0; j < content.length; j++) {
                content[j] = bytes1(uint8(j % 256));
            }

            vm.prank(creator);
            Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash,
                contentUriSha: keccak256(abi.encodePacked("uri", i)),
                initialOwner: owner,
                content: content,
                mimetype: "application/octet-stream",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "",
                    operation: "",
                    data: ""
                })
            });

            ethscriptions.createEthscription(params);
        }

        console.log("Setup complete: Created 100 ethscriptions");
        console.log("- 25 with small content (10 bytes)");
        console.log("- 25 with medium content (100 bytes)");
        console.log("- 25 with large content (1KB)");
        console.log("- 25 with huge content (10KB)");
        console.log("");
    }

    function testGas_GetEthscriptions_WithContent() public view {
        console.log("=== Testing getEthscriptions WITH content ===");
        console.log("");

        // Test various page sizes with content
        uint256[] memory pageSizes = new uint256[](7);
        pageSizes[0] = 1;
        pageSizes[1] = 10;
        pageSizes[2] = 20;
        pageSizes[3] = 30;
        pageSizes[4] = 40;
        pageSizes[5] = 50;
        pageSizes[6] = 60; // Should be clamped to 50

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

    function testGas_GetEthscriptions_WithoutContent() public view {
        console.log("=== Testing getEthscriptions WITHOUT content ===");
        console.log("");

        // Test various page sizes without content
        uint256[] memory pageSizes = new uint256[](10);
        pageSizes[0] = 1;
        pageSizes[1] = 10;
        pageSizes[2] = 50;
        pageSizes[3] = 100;
        pageSizes[4] = 200;
        pageSizes[5] = 300;
        pageSizes[6] = 500;
        pageSizes[7] = 750;
        pageSizes[8] = 1000;
        pageSizes[9] = 1500; // Should be clamped to 1000

        for (uint256 i = 0; i < pageSizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getEthscriptions(0, pageSizes[i], false);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Requested:", pageSizes[i], "items");
            console.log("  Returned:", result.items.length, "items");
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);
            console.log("");
        }
    }

    function testGas_GetOwnerEthscriptions_WithContent() public view {
        console.log("=== Testing getOwnerEthscriptions WITH content ===");
        console.log("");

        // Test with owner that has 20 ethscriptions (address(0x200))
        address targetOwner = address(0x200);
        uint256 ownerBalance = ethscriptions.balanceOf(targetOwner);
        console.log("Owner balance:", ownerBalance);
        console.log("");

        // Test various page sizes
        uint256[] memory pageSizes = new uint256[](5);
        pageSizes[0] = 5;
        pageSizes[1] = 10;
        pageSizes[2] = 15;
        pageSizes[3] = 20;
        pageSizes[4] = 30; // More than owner has

        for (uint256 i = 0; i < pageSizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getOwnerEthscriptions(targetOwner, 0, pageSizes[i], true);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Requested:", pageSizes[i], "items");
            console.log("  Returned:", result.items.length, "items");
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);
            console.log("");
        }
    }

    function testGas_GetOwnerEthscriptions_WithoutContent() public view {
        console.log("=== Testing getOwnerEthscriptions WITHOUT content ===");
        console.log("");

        // Test with owner that has 20 ethscriptions
        address targetOwner = address(0x200);
        uint256 ownerBalance = ethscriptions.balanceOf(targetOwner);
        console.log("Owner balance:", ownerBalance);
        console.log("");

        // Test various page sizes
        uint256[] memory pageSizes = new uint256[](5);
        pageSizes[0] = 5;
        pageSizes[1] = 10;
        pageSizes[2] = 15;
        pageSizes[3] = 20;
        pageSizes[4] = 30; // More than owner has

        for (uint256 i = 0; i < pageSizes.length; i++) {
            uint256 gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory result = ethscriptions.getOwnerEthscriptions(targetOwner, 0, pageSizes[i], false);
            uint256 gasUsed = gasStart - gasleft();

            console.log("Requested:", pageSizes[i], "items");
            console.log("  Returned:", result.items.length, "items");
            console.log("  Gas used:", gasUsed);
            console.log("  Gas per item:", result.items.length > 0 ? gasUsed / result.items.length : 0);
            console.log("");
        }
    }

    function testGas_EdgeCases() public view {
        console.log("=== Testing Edge Cases ===");
        console.log("");

        // Test with start beyond total supply
        uint256 gasStart = gasleft();
        Ethscriptions.PaginatedEthscriptionsResponse memory result1 = ethscriptions.getEthscriptions(200, 10, true);
        uint256 gasUsed = gasStart - gasleft();
        console.log("Start beyond total (200, 10):");
        console.log("  Returned:", result1.items.length, "items");
        console.log("  Gas used:", gasUsed);
        console.log("");

        // Test with limit = 0 (should revert)
        console.log("Limit = 0:");
        try ethscriptions.getEthscriptions(0, 0, true) returns (Ethscriptions.PaginatedEthscriptionsResponse memory) {
            console.log("  ERROR: Should have reverted!");
        } catch {
            console.log("  Correctly reverted with InvalidPaginationLimit");
        }
        console.log("");

        // Test pagination continuation
        gasStart = gasleft();
        Ethscriptions.PaginatedEthscriptionsResponse memory page1 = ethscriptions.getEthscriptions(0, 30, true);
        gasUsed = gasStart - gasleft();
        console.log("First page (0, 30):");
        console.log("  Returned:", page1.items.length, "items");
        console.log("  Has more:", page1.hasMore);
        console.log("  Next start:", page1.nextStart);
        console.log("  Gas used:", gasUsed);
        console.log("");

        if (page1.hasMore) {
            gasStart = gasleft();
            Ethscriptions.PaginatedEthscriptionsResponse memory page2 = ethscriptions.getEthscriptions(page1.nextStart, 30, true);
            gasUsed = gasStart - gasleft();
            console.log("Second page starting at:", page1.nextStart);
            console.log("  Returned:", page2.items.length, "items");
            console.log("  Has more:", page2.hasMore);
            console.log("  Gas used:", gasUsed);
            console.log("");
        }
    }

    function testGas_MaximumLimits() public {
        console.log("=== Testing Maximum Safe Limits ===");
        console.log("");

        // Test approaching gas limits with content
        console.log("Testing max with content (trying different sizes):");
        uint256[] memory testSizes = new uint256[](5);
        testSizes[0] = 40;
        testSizes[1] = 45;
        testSizes[2] = 50;
        testSizes[3] = 55;
        testSizes[4] = 60;

        for (uint256 i = 0; i < testSizes.length; i++) {
            try ethscriptions.getEthscriptions(0, testSizes[i], true) returns (Ethscriptions.PaginatedEthscriptionsResponse memory result) {
                uint256 gasStart = gasleft();
                ethscriptions.getEthscriptions(0, testSizes[i], true);
                uint256 gasUsed = gasStart - gasleft();
                console.log("  Size:", testSizes[i]);
                console.log("    Returned items:", result.items.length);
                console.log("    Gas used:", gasUsed);
            } catch {
                console.log("  Size FAILED:", testSizes[i]);
            }
        }
        console.log("");

        // Test approaching gas limits without content
        console.log("Testing max without content (trying different sizes):");
        uint256[] memory testSizesNoContent = new uint256[](5);
        testSizesNoContent[0] = 800;
        testSizesNoContent[1] = 900;
        testSizesNoContent[2] = 1000;
        testSizesNoContent[3] = 1100;
        testSizesNoContent[4] = 1200;

        // Need to create more ethscriptions for this test
        if (ethscriptions.totalSupply() < 1200) {
            console.log("  (Skipping - need more ethscriptions for full test)");
        } else {
            for (uint256 i = 0; i < testSizesNoContent.length; i++) {
                try ethscriptions.getEthscriptions(0, testSizesNoContent[i], false) returns (Ethscriptions.PaginatedEthscriptionsResponse memory result) {
                    uint256 gasStart = gasleft();
                    ethscriptions.getEthscriptions(0, testSizesNoContent[i], false);
                    uint256 gasUsed = gasStart - gasleft();
                    console.log("  Size:", testSizesNoContent[i]);
                    console.log("    Returned items:", result.items.length);
                    console.log("    Gas used:", gasUsed);
                } catch {
                    console.log("  Size FAILED:", testSizesNoContent[i]);
                }
            }
        }
    }
}