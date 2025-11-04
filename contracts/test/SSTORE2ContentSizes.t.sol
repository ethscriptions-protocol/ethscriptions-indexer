// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "./EthscriptionsWithTestFunctions.sol";
import "forge-std/console2.sol";

/// @title SSTORE2ContentSizesTest
/// @notice Comprehensive tests for SSTORE2Unlimited with various content sizes
/// @dev Tests small, medium, and large content to ensure proper storage and retrieval
contract SSTORE2ContentSizesTest is TestSetup {
    EthscriptionsWithTestFunctions internal eth;

    function setUp() public override {
        super.setUp();

        // Deploy the test version of Ethscriptions with additional test functions
        EthscriptionsWithTestFunctions testEthscriptions = new EthscriptionsWithTestFunctions();
        vm.etch(Predeploys.ETHSCRIPTIONS, address(testEthscriptions).code);
        eth = EthscriptionsWithTestFunctions(Predeploys.ETHSCRIPTIONS);
    }

    /// @notice Test with small content (100 bytes)
    function test_SmallContent_100Bytes() public {
        _testContentSize(100, "Small (100 bytes)");
    }

    /// @notice Test with small content (512 bytes)
    function test_SmallContent_512Bytes() public {
        _testContentSize(512, "Small (512 bytes)");
    }

    /// @notice Test with 1KB content
    function test_SmallContent_1KB() public {
        _testContentSize(1024, "1KB");
    }

    /// @notice Test with 10KB content
    function test_MediumContent_10KB() public {
        _testContentSize(10 * 1024, "10KB");
    }

    /// @notice Test with 24KB content (just under old contract size limit)
    function test_MediumContent_24KB() public {
        _testContentSize(24 * 1024, "24KB");
    }

    /// @notice Test with 50KB content (exceeds old single contract limit)
    function test_MediumContent_50KB() public {
        _testContentSize(50 * 1024, "50KB");
    }

    /// @notice Test with 100KB content
    function test_MediumContent_100KB() public {
        _testContentSize(100 * 1024, "100KB");
    }

    /// @notice Test with 250KB content
    function test_LargeContent_250KB() public {
        _testContentSize(250 * 1024, "250KB");
    }

    /// @notice Test with 500KB content
    function test_LargeContent_500KB() public {
        _testContentSize(500 * 1024, "500KB");
    }

    /// @notice Test with 750KB content
    function test_LargeContent_750KB() public {
        _testContentSize(750 * 1024, "750KB");
    }

    /// @notice Test with 1MB content (already exists but let's make it part of the suite)
    function test_LargeContent_1MB() public {
        _testContentSize(1024 * 1024, "1MB");
    }

    /// @notice Test with 2MB content
    function test_VeryLargeContent_2MB() public {
        _testContentSize(2 * 1024 * 1024, "2MB");
    }

    /// @notice Test edge case: empty content
    function test_EdgeCase_EmptyContent() public {
        _testContentSize(0, "Empty");
    }

    /// @notice Test edge case: single byte
    function test_EdgeCase_SingleByte() public {
        _testContentSize(1, "Single byte");
    }

    /// @notice Helper function to test content of a specific size
    function _testContentSize(uint256 size, string memory label) private {
        vm.pauseGasMetering();

        // Create content of specified size with a deterministic pattern
        bytes memory content = _generateContent(size);

        // Create data URI
        string memory contentUri = string(abi.encodePacked("data:text/plain,", content));

        // Create ethscription parameters
        bytes32 txHash = keccak256(abi.encodePacked(label, size));
        address creator = address(0x1234);
        address initialOwner = address(0x5678);

        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            txHash,
            initialOwner,
            contentUri,
            false
        );

        // Measure gas for creation
        vm.startPrank(creator);
        uint256 g0 = gasleft();
        vm.resumeGasMetering();
        uint256 tokenId = eth.createEthscription(params);
        vm.pauseGasMetering();
        uint256 createGas = g0 - gasleft();
        vm.stopPrank();

        console2.log(string.concat(label, " - Create gas: "), createGas);
        console2.log(string.concat(label, " - Content size: "), size);

        // Verify ownership
        assertEq(eth.ownerOf(tokenId), initialOwner, "Owner mismatch");

        // Test content retrieval via getEthscriptionContent
        g0 = gasleft();
        vm.resumeGasMetering();
        bytes memory retrievedContent = eth.getEthscriptionContent(txHash);
        vm.pauseGasMetering();
        uint256 retrievalGas = g0 - gasleft();

        console2.log(string.concat(label, " - Retrieval gas: "), retrievalGas);

        // Verify content matches exactly
        assertEq(retrievedContent.length, content.length, "Content length mismatch");

        if (size > 0) {
            // Verify the content matches
            _verifyContent(retrievedContent, content, size, label);
        }

        // Verify storage details
        _verifyStorage(txHash, content, label);

        console2.log(string.concat(label, " - Test passed!"));
        console2.log("---");
    }

    /// @notice Verify content matches
    function _verifyContent(
        bytes memory retrievedContent,
        bytes memory originalContent,
        uint256 size,
        string memory label
    ) private pure {
        // For non-empty content, verify the actual bytes match
        assertEq(
            keccak256(retrievedContent),
            keccak256(originalContent),
            "Content hash mismatch"
        );

        // Sample check: verify first and last bytes
        assertEq(retrievedContent[0], originalContent[0], "First byte mismatch");
        assertEq(
            retrievedContent[retrievedContent.length - 1],
            originalContent[originalContent.length - 1],
            "Last byte mismatch"
        );

        // For smaller content, check byte-by-byte
        if (size <= 1024) {
            for (uint i = 0; i < size; i++) {
                assertEq(retrievedContent[i], originalContent[i], "Byte mismatch");
            }
        }
    }

    /// @notice Verify storage details
    function _verifyStorage(
        bytes32 txHash,
        bytes memory content,
        string memory label
    ) private view {
        // Test that content is stored (either inline or via SSTORE2)
        assertTrue(eth.hasContent(txHash), "Content not stored");

        // For small content (<32 bytes), it's stored inline and there's no pointer
        // For large content (>=32 bytes), it's stored via SSTORE2 with a pointer
        address pointer = eth.getContentPointer(txHash);
        if (content.length >= 32) {
            assertTrue(pointer != address(0), "Should have SSTORE2 pointer for large content");
        } else {
            // Small content is stored inline, no SSTORE2 pointer
            assertEq(pointer, address(0), "Should not have pointer for inline content");
        }

        // Test direct read from test functions
        bytes memory directRead = eth.readContent(txHash);
        assertEq(keccak256(directRead), keccak256(content), "Direct read mismatch");
    }

    /// @notice Generate deterministic content of specified size
    function _generateContent(uint256 size) private pure returns (bytes memory) {
        if (size == 0) return new bytes(0);

        bytes memory content = new bytes(size);
        for (uint256 i = 0; i < size;) {
            // Create a pattern that's easy to verify:
            // - Alternating uppercase letters A-Z
            // - With position markers every 256 bytes
            if (i % 256 == 0 && i > 0) {
                // Position marker: use numbers 0-9
                content[i] = bytes1(uint8(48 + ((i / 256) % 10)));
            } else {
                // Regular pattern: A-Z cycling
                content[i] = bytes1(uint8(65 + (i % 26)));
            }
            
            unchecked {
                ++i;
            }
        }
        return content;
    }

    /// @notice Test content deduplication across different sizes
    function test_ContentDeduplication_VariousSizes() public {
        vm.pauseGasMetering();

        // Test deduplication with different content sizes
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 100;      // Small
        sizes[1] = 1024;     // 1KB
        sizes[2] = 10240;    // 10KB
        sizes[3] = 102400;   // 100KB
        sizes[4] = 524288;   // 512KB

        for (uint256 i = 0; i < sizes.length; i++) {
            _testDeduplication(sizes[i], string.concat("Size: ", vm.toString(sizes[i])));
        }
    }

    /// @notice Helper to test deduplication for a specific size
    function _testDeduplication(uint256 size, string memory label) private {
        bytes memory content = _generateContent(size);
        string memory contentUri = string(abi.encodePacked("data:text/plain,", content));

        // Create first ethscription
        bytes32 txHash1 = keccak256(abi.encodePacked(label, "first"));
        bytes32 txHash2 = keccak256(abi.encodePacked(label, "second"));
        address creator = address(0x1234);

        vm.startPrank(creator);

        // First creation
        uint256 g0 = gasleft();
        vm.resumeGasMetering();
        eth.createEthscription(createTestParams(txHash1, address(0x1111), contentUri, true));
        vm.pauseGasMetering();
        uint256 firstGas = g0 - gasleft();

        // Second creation with same content (should deduplicate)
        g0 = gasleft();
        vm.resumeGasMetering();
        eth.createEthscription(createTestParams(txHash2, address(0x2222), contentUri, true));
        vm.pauseGasMetering();
        uint256 secondGas = g0 - gasleft();

        vm.stopPrank();

        console2.log(string.concat(label, " - First creation gas: "), firstGas);
        console2.log(string.concat(label, " - Second creation gas (deduplicated): "), secondGas);
        console2.log(string.concat(label, " - Gas saved: "), firstGas - secondGas);

        // Verify both use the same content pointer
        address pointer1 = eth.getContentPointer(txHash1);
        address pointer2 = eth.getContentPointer(txHash2);
        assertEq(pointer1, pointer2, "Pointers should be identical");

        // Verify content retrieval works for both
        bytes memory content1 = eth.getEthscriptionContent(txHash1);
        bytes memory content2 = eth.getEthscriptionContent(txHash2);
        assertEq(keccak256(content1), keccak256(content2), "Content should be identical");
        assertEq(keccak256(content1), keccak256(content), "Retrieved content should match original");

        // Second creation should be significantly cheaper (saved SSTORE2 deployment)
        assertTrue(secondGas < firstGas, "Deduplication should save gas");

        console2.log("---");
    }
}