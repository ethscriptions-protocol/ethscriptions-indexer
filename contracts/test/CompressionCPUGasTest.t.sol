// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "solady/utils/LibZip.sol";
import "forge-std/console.sol";

contract CompressionCPUGasTest is Test {
    using LibZip for bytes;
    
    function testIsolatedCompressionDecompressionGas() public {
        console.log("\n=== Isolated CPU Gas Cost for Compression/Decompression ===\n");
        
        // Load the actual example ethscription content
        string memory json = vm.readFile("test/example_ethscription.json");
        bytes memory contentUri = bytes(vm.parseJsonString(json, ".result.content_uri"));
        
        console.log("Testing with real content:", contentUri.length, "bytes");
        
        // Test compression CPU cost
        uint256 compressionGas = _measureCompressionGas(contentUri);
        
        // Compress once to get compressed data for decompression test
        bytes memory compressed = LibZip.flzCompress(contentUri);
        console.log("Compressed size:", compressed.length, "bytes");
        console.log("Compression ratio:", (compressed.length * 100) / contentUri.length, "%");
        
        // Test decompression CPU cost
        uint256 decompressionGas = _measureDecompressionGas(compressed, contentUri);
        
        // Test with different sizes to see scaling
        console.log("\n=== Gas Scaling Analysis ===\n");
        _testScaling(contentUri);
        
        // Summary
        console.log("\n=== Summary for Full Content ===");
        console.log("Compression CPU gas:", compressionGas);
        console.log("Decompression CPU gas:", decompressionGas);
        console.log("Gas per input KB (compression):", compressionGas / (contentUri.length / 1024));
        console.log("Gas per output KB (decompression):", decompressionGas / (contentUri.length / 1024));
        
        // Compare to storage costs
        uint256 storageGasPerByte = 640; // Approximate gas per byte for SSTORE2
        uint256 savedBytes = contentUri.length - compressed.length;
        uint256 storageSavings = savedBytes * storageGasPerByte;
        
        console.log("\n=== Compression Economics ===");
        console.log("Bytes saved:", savedBytes);
        console.log("Storage gas saved:", storageSavings);
        console.log("Compression gas cost:", compressionGas);
        
        if (storageSavings > compressionGas) {
            uint256 netSavings = storageSavings - compressionGas;
            console.log("Net savings on write:", netSavings);
            console.log("ROI on compression:", (netSavings * 100) / compressionGas, "%");
        } else {
            uint256 netCost = compressionGas - storageSavings;
            console.log("Net cost on write:", netCost);
            console.log("Compression is not economical for storage alone");
        }
    }
    
    function _measureCompressionGas(bytes memory data) internal returns (uint256) {
        // Warm up (first call might have different gas due to memory expansion)
        LibZip.flzCompress(data);
        
        // Measure actual compression gas
        uint256 gasBefore = gasleft();
        bytes memory compressed = LibZip.flzCompress(data);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify it worked
        require(compressed.length > 0, "Compression failed");
        
        console.log("Compression gas:", gasUsed);
        return gasUsed;
    }
    
    function _measureDecompressionGas(bytes memory compressed, bytes memory expected) internal returns (uint256) {
        // Warm up
        LibZip.flzDecompress(compressed);
        
        // Measure actual decompression gas
        uint256 gasBefore = gasleft();
        bytes memory decompressed = LibZip.flzDecompress(compressed);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Verify correctness
        assertEq(decompressed, expected, "Decompression mismatch");
        
        console.log("Decompression gas:", gasUsed);
        return gasUsed;
    }
    
    function _testScaling(bytes memory fullData) internal {
        uint256[] memory sizes = new uint256[](5);
        sizes[0] = 1024;   // 1 KB
        sizes[1] = 5120;   // 5 KB
        sizes[2] = 10240;  // 10 KB
        sizes[3] = 25600;  // 25 KB
        sizes[4] = 51200;  // 50 KB
        
        console.log("Size (KB) | Compress Gas | Decompress Gas | Gas/KB Compress | Gas/KB Decompress");
        console.log("----------|--------------|----------------|-----------------|------------------");
        
        for (uint i = 0; i < sizes.length; i++) {
            if (sizes[i] > fullData.length) continue;
            
            // Create test data of specific size
            bytes memory testData = new bytes(sizes[i]);
            for (uint j = 0; j < sizes[i]; j++) {
                testData[j] = fullData[j % fullData.length];
            }
            
            // Compress to get compressed version
            bytes memory compressed = LibZip.flzCompress(testData);
            
            // Measure compression
            uint256 compressGasBefore = gasleft();
            LibZip.flzCompress(testData);
            uint256 compressGas = compressGasBefore - gasleft();
            
            // Measure decompression
            uint256 decompressGasBefore = gasleft();
            LibZip.flzDecompress(compressed);
            uint256 decompressGas = decompressGasBefore - gasleft();
            
            uint256 sizeKB = sizes[i] / 1024;
            console.log(
                string.concat(
                    vm.toString(sizeKB), " KB      | ",
                    vm.toString(compressGas), " | ",
                    vm.toString(decompressGas), " | ",
                    vm.toString(compressGas / sizeKB), " | ",
                    vm.toString(decompressGas / sizeKB)
                )
            );
        }
    }
    
    function testCompressionWithDifferentDataTypes() public {
        console.log("\n=== Compression CPU Gas by Data Type ===\n");
        
        // Test different types of data
        bytes memory types = new bytes(5);
        
        // 1. Highly repetitive data (best case)
        bytes memory repetitive = new bytes(10240);
        for (uint i = 0; i < repetitive.length; i++) {
            repetitive[i] = bytes1(uint8(65)); // All 'A's
        }
        
        // 2. Base64 data (typical case)
        bytes memory base64 = new bytes(10240);
        bytes memory base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for (uint i = 0; i < base64.length; i++) {
            base64[i] = base64Chars[i % 64];
        }
        
        // 3. Random data (worst case)
        bytes memory random = new bytes(10240);
        for (uint i = 0; i < random.length; i++) {
            random[i] = bytes1(uint8(uint256(keccak256(abi.encode(i))) % 256));
        }
        
        console.log("Data Type    | Size | Compressed | Ratio | Compress Gas | Decompress Gas");
        console.log("-------------|------|------------|-------|--------------|---------------");
        
        _measureDataType("Repetitive", repetitive);
        _measureDataType("Base64", base64);
        _measureDataType("Random", random);
    }
    
    function _measureDataType(string memory label, bytes memory data) internal {
        bytes memory compressed = LibZip.flzCompress(data);
        
        // Measure compression
        uint256 compressGasBefore = gasleft();
        LibZip.flzCompress(data);
        uint256 compressGas = compressGasBefore - gasleft();
        
        // Measure decompression  
        uint256 decompressGasBefore = gasleft();
        LibZip.flzDecompress(compressed);
        uint256 decompressGas = decompressGasBefore - gasleft();
        
        console.log(
            string.concat(
                label, " | ",
                vm.toString(data.length), " | ",
                vm.toString(compressed.length), " | ",
                vm.toString((compressed.length * 100) / data.length), "% | ",
                vm.toString(compressGas), " | ",
                vm.toString(decompressGas)
            )
        );
    }
}