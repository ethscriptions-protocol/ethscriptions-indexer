// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {LibZip} from "solady/utils/LibZip.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import "forge-std/console.sol";

contract RealCompressionTest is Test {
    using LibZip for bytes;
    
    // Simulate the real ethscriptions storage pattern
    mapping(bytes32 => address[]) private contentBySha;
    mapping(bytes32 => address[]) private _compressedContentBySha;
    
    // function testRealEthscriptionCompressionWithAssembly() public {
    //     console.log("\n=== Real Ethscription Compression Test ===\n");
        
    //     // Load the actual example ethscription content
    //     string memory json = vm.readFile("test/example_ethscription.json");
    //     bytes memory contentUri = bytes(vm.parseJsonString(json, ".result.content_uri"));
        
    //     emit log_named_uint("Actual content URI size (bytes)", contentUri.length);
        
    //     // Test uncompressed storage and retrieval
    //     (uint256 writeGasUncompressed, uint256 readGasUncompressed, bytes32 shaUncompressed) = 
    //         _storeAndReadUncompressed(contentUri);
        
    //     // Test compressed storage and retrieval
    //     (uint256 writeGasCompressed, uint256 readGasCompressed, bytes32 shaCompressed) = 
    //         _storeAndReadCompressed(contentUri);
        
    //     // Compare results
    //     console.log("\n=== Gas Comparison ===");
    //     emit log_named_uint("Write Gas (uncompressed)", writeGasUncompressed);
    //     emit log_named_uint("Write Gas (compressed)", writeGasCompressed);
        
    //     if (writeGasCompressed < writeGasUncompressed) {
    //         uint256 writeSavings = writeGasUncompressed - writeGasCompressed;
    //         emit log_named_uint("Write gas saved", writeSavings);
    //         emit log_named_uint("Write savings %", (writeSavings * 100) / writeGasUncompressed);
    //     } else {
    //         uint256 writeExtra = writeGasCompressed - writeGasUncompressed;
    //         emit log_named_uint("Extra write gas", writeExtra);
    //     }
        
    //     emit log_named_uint("Read Gas (uncompressed)", readGasUncompressed);
    //     emit log_named_uint("Read Gas (compressed + decompress)", readGasCompressed);
        
    //     if (readGasCompressed < readGasUncompressed) {
    //         uint256 readSavings = readGasUncompressed - readGasCompressed;
    //         emit log_named_uint("Read gas saved", readSavings);
    //     } else {
    //         uint256 readExtra = readGasCompressed - readGasUncompressed;
    //         emit log_named_uint("Extra read gas", readExtra);
    //     }
        
    //     // Calculate break-even point
    //     if (writeGasCompressed < writeGasUncompressed && readGasCompressed > readGasUncompressed) {
    //         uint256 writeSavings = writeGasUncompressed - writeGasCompressed;
    //         uint256 readPenalty = readGasCompressed - readGasUncompressed;
    //         uint256 breakEvenReads = writeSavings / readPenalty;
    //         emit log_named_uint("Break-even reads (integer)", breakEvenReads);
    //     }
        
    //     // Total lifecycle cost (1 write + N reads)
    //     console.log("\n=== Total Lifecycle Cost ===");
    //     for (uint reads = 1; reads <= 10; reads *= 10) {
    //         uint256 totalUncompressed = writeGasUncompressed + (readGasUncompressed * reads);
    //         uint256 totalCompressed = writeGasCompressed + (readGasCompressed * reads);
            
    //         emit log_named_uint(string.concat("Total cost with ", vm.toString(reads), " reads (uncompressed)"), totalUncompressed);
    //         emit log_named_uint(string.concat("Total cost with ", vm.toString(reads), " reads (compressed)"), totalCompressed);
            
    //         if (totalCompressed < totalUncompressed) {
    //             uint256 savings = totalUncompressed - totalCompressed;
    //             emit log_named_uint("  Net savings", savings);
    //             emit log_named_uint("  Savings percentage", (savings * 100) / totalUncompressed);
    //         } else {
    //             uint256 extra = totalCompressed - totalUncompressed;
    //             emit log_named_uint("  Net extra cost", extra);
    //         }
    //     }
    // }
    
    function _storeAndReadUncompressed(bytes memory data) internal returns (uint256 writeGas, uint256 readGas, bytes32 sha) {
        sha = keccak256(data);
        uint256 chunkSize = 24575;
        
        // Write phase
        uint256 gasStart = gasleft();
        
        uint256 chunks = (data.length + chunkSize - 1) / chunkSize;
        for (uint i = 0; i < chunks; i++) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize;
            if (end > data.length) end = data.length;
            
            bytes memory chunk = new bytes(end - start);
            for (uint j = 0; j < chunk.length; j++) {
                chunk[j] = data[start + j];
            }
            
            address pointer = SSTORE2.write(chunk);
            contentBySha[sha].push(pointer);
        }
        
        writeGas = gasStart - gasleft();
        emit log_named_uint("Uncompressed chunks", chunks);
        
        // Read phase using assembly (mimicking real contract)
        gasStart = gasleft();
        bytes memory result = _readWithAssembly(contentBySha[sha]);
        readGas = gasStart - gasleft();
        
        // Verify
        assertEq(result, data, "Uncompressed read mismatch");
        
        return (writeGas, readGas, sha);
    }
    
    // function _storeAndReadCompressed(bytes memory data) internal returns (uint256 writeGas, uint256 readGas, bytes32 sha) {
    //     // Compress first and measure CPU
    //     uint256 g0 = gasleft();
    //     bytes memory compressed = LibZip.flzCompress(data);
    //     uint256 compGas = g0 - gasleft();
    //     emit log_named_uint("Compress gas", compGas);
    //     sha = keccak256(data); // Use original SHA for consistency
        
    //     emit log_named_uint("Compressed size (bytes)", compressed.length);
    //     emit log_named_uint("Compression ratio %", (compressed.length * 100) / data.length);
        
    //     uint256 chunkSize = 24575;
        
    //     // Write phase
    //     uint256 gasStart = gasleft();
        
    //     uint256 chunks = (compressed.length + chunkSize - 1) / chunkSize;
    //     for (uint i = 0; i < chunks; i++) {
    //         uint256 start = i * chunkSize;
    //         uint256 end = start + chunkSize;
    //         if (end > compressed.length) end = compressed.length;
            
    //         bytes memory chunk = new bytes(end - start);
    //         for (uint j = 0; j < chunk.length; j++) {
    //             chunk[j] = compressed[start + j];
    //         }
            
    //         address pointer = SSTORE2.write(chunk);
    //         _compressedContentBySha[sha].push(pointer);
    //     }
        
    //     writeGas = gasStart - gasleft();
    //     emit log_named_uint("Compressed chunks", chunks);
        
    //     // Read phase and measure read vs decompress separately
    //     gasStart = gasleft();
    //     bytes memory compressedRead = _readWithAssembly(_compressedContentBySha[sha]);
    //     uint256 readOnlyGas = gasStart - gasleft();

    //     uint256 g1 = gasleft();
    //     bytes memory result = LibZip.flzDecompress(compressedRead);
    //     uint256 decompGas = g1 - gasleft();
    //     readGas = readOnlyGas + decompGas;
    //     emit log_named_uint("Read Gas (compressed only)", readOnlyGas);
    //     emit log_named_uint("Decompress gas", decompGas);
        
    //     // Verify
    //     assertEq(result, data, "Compressed read mismatch");
        
    //     return (writeGas, readGas, sha);
    // }
    
    // Mimics the assembly read from Ethscriptions.sol
    function _readWithAssembly(address[] memory pointers) internal view returns (bytes memory result) {
        uint256 dataOffset = 1; // SSTORE2 data starts after a 1-byte STOP opcode
        assembly {
            // Calculate total size needed
            let totalSize := 0
            let pointersLength := mload(pointers)
            
            for { let i := 0 } lt(i, pointersLength) { i := add(i, 1) } {
                let pointer := mload(add(pointers, add(0x20, mul(i, 0x20))))
                let codeSize := extcodesize(pointer)
                totalSize := add(totalSize, sub(codeSize, dataOffset))
            }
            
            // Allocate result buffer
            result := mload(0x40)
            let resultPtr := add(result, 0x20)
            
            // Copy data from each pointer
            let currentOffset := 0
            for { let i := 0 } lt(i, pointersLength) { i := add(i, 1) } {
                let pointer := mload(add(pointers, add(0x20, mul(i, 0x20))))
                let codeSize := extcodesize(pointer)
                let chunkSize := sub(codeSize, dataOffset)
                extcodecopy(pointer, add(resultPtr, currentOffset), dataOffset, chunkSize)
                currentOffset := add(currentOffset, chunkSize)
            }
            
            // Update length and free memory pointer with proper alignment
            mstore(result, totalSize)
            mstore(0x40, and(add(add(resultPtr, totalSize), 0x1f), not(0x1f)))
        }
        
        return result;
    }
}
