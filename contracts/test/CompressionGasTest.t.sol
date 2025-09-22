// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "solady/utils/LibZip.sol";
import "solady/utils/SSTORE2.sol";

contract CompressionGasTest is Test {
    using LibZip for bytes;
    
    // Test different types of data
    bytes constant JSON_DATA = 'data:application/json,{"p":"erc-20","op":"mint","tick":"eths","amt":"1000"}';
    bytes constant TEXT_DATA = 'data:text/plain,Hello World! This is a longer text message that might benefit from compression. Lorem ipsum dolor sit amet, consectetur adipiscing elit.';
    bytes constant REPETITIVE_DATA = 'data:text/plain,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    bytes constant BASE64_IMAGE = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
    
    // Larger JSON for better compression ratio testing
    bytes constant LARGE_JSON = 'data:application/json,{"protocol":"ethscriptions","operation":"deploy","ticker":"TEST","maxSupply":"21000000","mintLimit":"1000","decimals":"18","metadata":{"name":"Test Token","description":"This is a test token for compression analysis","website":"https://example.com","twitter":"@example","discord":"https://discord.gg/example"}}';
    
    function testCompressionEfficiency() public {
        console.log("=== SSTORE2 Compression Gas Analysis ===\n");
        
        // Test JSON data
        _testDataType("JSON (small)", JSON_DATA);
        _testDataType("JSON (large)", LARGE_JSON);
        
        // Test text data
        _testDataType("Text", TEXT_DATA);
        
        // Test repetitive data (should compress well)
        _testDataType("Repetitive", REPETITIVE_DATA);
        
        // Test base64 image (may not compress well)
        _testDataType("Base64 Image", BASE64_IMAGE);
        
        // Test chunked storage scenarios
        console.log("\n=== Chunked Storage Analysis (24KB chunks) ===\n");
        _testChunkedStorage();
    }
    
    function _testDataType(string memory label, bytes memory data) internal {
        console.log(string.concat("Testing: ", label));
        console.log("Original size:", data.length, "bytes");
        
        // Compress the data
        bytes memory compressed = LibZip.flzCompress(data);
        console.log("Compressed size:", compressed.length, "bytes");
        
        uint256 compressionRatio = (compressed.length * 100) / data.length;
        console.log("Compression ratio:", compressionRatio, "%");
        
        // Test SSTORE2 write gas costs
        uint256 gasUncompressed = gasleft();
        address ptrUncompressed = SSTORE2.write(data);
        gasUncompressed = gasUncompressed - gasleft();
        
        uint256 gasCompressed = gasleft();
        address ptrCompressed = SSTORE2.write(compressed);
        gasCompressed = gasCompressed - gasleft();
        
        console.log("SSTORE2 write gas (uncompressed):", gasUncompressed);
        console.log("SSTORE2 write gas (compressed):", gasCompressed);
        
        int256 gasSavings = int256(gasUncompressed) - int256(gasCompressed);
        if (gasSavings > 0) {
            console.log("Gas saved by compression:", uint256(gasSavings));
        } else {
            console.log("Extra gas cost for compression:", uint256(-gasSavings));
        }
        
        // Test read + decompress gas costs
        uint256 gasReadUncompressed = gasleft();
        bytes memory readUncompressed = SSTORE2.read(ptrUncompressed);
        gasReadUncompressed = gasReadUncompressed - gasleft();
        
        uint256 gasReadCompressed = gasleft();
        bytes memory readCompressed = SSTORE2.read(ptrCompressed);
        bytes memory decompressed = LibZip.flzDecompress(readCompressed);
        gasReadCompressed = gasReadCompressed - gasleft();
        
        console.log("Read gas (uncompressed):", gasReadUncompressed);
        console.log("Read + decompress gas:", gasReadCompressed);
        
        // Verify decompression is correct
        assertEq(decompressed, data, "Decompression failed");
        
        console.log("---\n");
    }
    
    function _testChunkedStorage() internal {
        // Create a large dataset that would be split into chunks
        bytes memory largeData = new bytes(48000); // ~48KB
        
        // Fill with semi-realistic JSON data pattern
        bytes memory pattern = bytes('{"id":1234567890,"data":"');
        for (uint i = 0; i < largeData.length; i++) {
            largeData[i] = pattern[i % pattern.length];
        }
        
        console.log("Large dataset size:", largeData.length, "bytes");
        
        // Compress the entire dataset
        bytes memory compressed = LibZip.flzCompress(largeData);
        console.log("Compressed size:", compressed.length, "bytes");
        console.log("Compression ratio:", (compressed.length * 100) / largeData.length, "%");
        
        // Calculate chunks needed
        uint256 chunkSize = 24575; // Max SSTORE2 chunk size
        uint256 chunksUncompressed = (largeData.length + chunkSize - 1) / chunkSize;
        uint256 chunksCompressed = (compressed.length + chunkSize - 1) / chunkSize;
        
        console.log("Chunks needed (uncompressed):", chunksUncompressed);
        console.log("Chunks needed (compressed):", chunksCompressed);
        
        // Estimate total storage cost
        uint256 totalGasUncompressed = 0;
        uint256 totalGasCompressed = 0;
        
        // Store uncompressed chunks
        for (uint i = 0; i < chunksUncompressed; i++) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize;
            if (end > largeData.length) end = largeData.length;
            
            bytes memory chunk = new bytes(end - start);
            for (uint j = 0; j < chunk.length; j++) {
                chunk[j] = largeData[start + j];
            }
            
            uint256 gas = gasleft();
            SSTORE2.write(chunk);
            totalGasUncompressed += gas - gasleft();
        }
        
        // Store compressed as single chunk (if it fits) or multiple
        for (uint i = 0; i < chunksCompressed; i++) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize;
            if (end > compressed.length) end = compressed.length;
            
            bytes memory chunk = new bytes(end - start);
            for (uint j = 0; j < chunk.length; j++) {
                chunk[j] = compressed[start + j];
            }
            
            uint256 gas = gasleft();
            SSTORE2.write(chunk);
            totalGasCompressed += gas - gasleft();
        }
        
        console.log("Total storage gas (uncompressed):", totalGasUncompressed);
        console.log("Total storage gas (compressed):", totalGasCompressed);
        
        int256 totalSavings = int256(totalGasUncompressed) - int256(totalGasCompressed);
        if (totalSavings > 0) {
            console.log("Total gas saved:", uint256(totalSavings));
            console.log("Percentage saved:", (uint256(totalSavings) * 100) / totalGasUncompressed, "%");
        } else {
            console.log("Extra gas cost:", uint256(-totalSavings));
        }
    }
    
    function testDecompressionGasCost() public {
        console.log("=== Decompression Gas Cost Analysis ===\n");
        
        bytes memory testData = LARGE_JSON;
        bytes memory compressed = LibZip.flzCompress(testData);
        
        // Write compressed data
        address ptr = SSTORE2.write(compressed);
        
        // Measure decompression cost at different sizes
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 100;
        sizes[1] = 500;
        sizes[2] = 1000;
        sizes[3] = 5000;
        sizes[4] = 10000;
        
        for (uint i = 0; i < sizes.length; i++) {
            if (sizes[i] > testData.length) continue;
            
            bytes memory data = new bytes(sizes[i]);
            for (uint j = 0; j < sizes[i]; j++) {
                data[j] = testData[j % testData.length];
            }
            
            bytes memory compressedData = LibZip.flzCompress(data);
            address dataPtr = SSTORE2.write(compressedData);
            
            uint256 gas = gasleft();
            bytes memory read = SSTORE2.read(dataPtr);
            LibZip.flzDecompress(read);
            gas = gas - gasleft();
            
            console.log("Size:", sizes[i], "bytes - Decompression gas:", gas);
        }
    }
}