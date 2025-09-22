// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./TestSetup.sol";
import "../script/L2Genesis.s.sol";
import "../src/libraries/Predeploys.sol";

contract GasDebugTest is TestSetup {
    address constant INITIAL_OWNER = 0xC2172a6315c1D7f6855768F843c420EbB36eDa97;

    function setUp() public override {
        super.setUp();
        // ethscriptions is already set up by TestSetup
    }

    function testExactMainnetInput() public {
        // Set up the exact input from mainnet block 17478950
        Ethscriptions.CreateEthscriptionParams memory params = createTestParams(
            0x05aac415994e0e01e66c4970133a51a4cdcea1f3a967743b87e6eb08f2f4d9f9,
            INITIAL_OWNER,
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAm0lEQVR42mNgGITgPxTTxvBleTo0swBsOK0s+N8aJkczC1AMR7KAKpb8v72xAY5hFsD4lFoCN+j56ZUoliAbSoklGIZjwxRbQAjT1YK7d+82kGUBeuQiiJ1rAYYrL81NwCpGFQtoEUT/6RoHWAyknQV0S6ZI5RE6Jt8CZIOOH TuGgR9Fq5FkCf19QM3wx5rZKHEtsRZQtJqkhgUARpCGaUehOD4AAAAAElFTkSuQmCC",
            false
        );

        // Prank as the creator address
        vm.prank(INITIAL_OWNER);

        // Measure gas before
        uint256 gasBefore = gasleft();
        console.log("Gas before createEthscription:", gasBefore);

        // Try to create the ethscription
        try ethscriptions.createEthscription(params) returns (uint256 tokenId) {
            uint256 gasAfter = gasleft();
            uint256 gasUsed = gasBefore - gasAfter;
            console.log("Gas after createEthscription:", gasAfter);
            console.log("Gas used:", gasUsed);
            console.log("Token ID created:", tokenId);

            // Verify it was created
            Ethscriptions.Ethscription memory etsc = ethscriptions.getEthscription(params.transactionHash);
            assertEq(etsc.creator, INITIAL_OWNER);
            assertEq(etsc.initialOwner, INITIAL_OWNER);
            assertEq(etsc.content.mimetype, "image/png");
        } catch Error(string memory reason) {
            console.log("Failed with reason:", reason);
            revert(reason);
        } catch (bytes memory lowLevelData) {
            console.log("Failed with low-level error");
            console.logBytes(lowLevelData);
            revert("Low-level error");
        }
    }

    function testStoreContentDirectly() public {
        // Test _storeContent in isolation by creating a minimal wrapper
        // First deploy a test contract that exposes _storeContent
        StoreContentTester tester = new StoreContentTester();

        bytes memory contentUri = bytes("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAm0lEQVR42mNgGITgPxTTxvBleTo0swBsOK0s+N8aJkczC1AMR7KAKpb8v72xAY5hFsD4lFoCN+j56ZUoliAbSoklGIZjwxRbQAjT1YK7d+82kGUBeuQiiJ1rAYYrL81NwCpGFQtoEUT/6RoHWAyknQV0S6ZI5RE6Jt8CZIOOH TuGgR9Fq5FkCf19QM3wx5rZKHEtsRZQtJqkhgUARpCGaUehOD4AAAAAElFTkSuQmCC");

        console.log("Content URI length:", contentUri.length);

        uint256 gasBefore = gasleft();
        bytes32 contentSha = tester.storeContentHelper(contentUri);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for _storeContent:", gasUsed);
        console.log("Content SHA:", uint256(contentSha));
    }

    // Add bounded test for fuzzing
    function testStoreContentBounded(bytes calldata contentUri) public {
        // Limit input size to avoid OOG in tests
        vm.assume(contentUri.length > 0 && contentUri.length <= 1000);

        StoreContentTester tester = new StoreContentTester();

        // Only test uncompressed content to avoid decompression gas costs
        tester.storeContentHelper(contentUri);
    }
}

// Helper contract to test _storeContent directly
contract StoreContentTester is Ethscriptions {
    // Not prefixed with 'test' to avoid fuzzing
    function storeContentHelper(
        bytes calldata content
    ) external returns (bytes32) {
        return _storeContent(content);
    }
}