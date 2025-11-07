// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/Ethscriptions.sol";
import "./TestSetup.sol";

contract ERC721EnumerableTest is TestSetup {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function _createEthscription(
        address creator,
        address owner,
        bytes32 txHash,
        string memory content
    ) internal returns (uint256) {
        vm.prank(creator);
        return ethscriptions.createEthscription(
            Ethscriptions.CreateEthscriptionParams({
                ethscriptionId: txHash,
                contentUriSha: keccak256(bytes(content)),
                initialOwner: owner,
                content: bytes(content),
                mimetype: "text/plain",
                esip6: false,
                protocolParams: Ethscriptions.ProtocolParams({
                    protocolName: "",
                    operation: "",
                    data: ""
                })
            })
        );
    }

    function testTotalSupplyStartsWithGenesis() public {
        // Genesis creates some initial ethscriptions
        uint256 initialSupply = ethscriptions.totalSupply();
        assertTrue(initialSupply > 0, "Should have genesis ethscriptions");
    }

    function testTotalSupplyIncrementsOnMint() public {
        uint256 initialSupply = ethscriptions.totalSupply();

        // Create ethscription for alice
        _createEthscription(alice, alice, keccak256("tx1"), "hello1");
        assertEq(ethscriptions.totalSupply(), initialSupply + 1);

        // Create another for bob
        _createEthscription(bob, bob, keccak256("tx2"), "hello2");
        assertEq(ethscriptions.totalSupply(), initialSupply + 2);
    }

    function testTokenByIndex() public {
        // Create multiple ethscriptions
        _createEthscription(alice, alice, keccak256("tx1"), "hello1");
        _createEthscription(bob, bob, keccak256("tx2"), "hello2");

        // Check tokenByIndex
        assertEq(ethscriptions.tokenByIndex(0), 0); // First token has ID 0
        assertEq(ethscriptions.tokenByIndex(1), 1); // Second token has ID 1
    }

    function testTokenOfOwnerByIndex() public {
        uint256 aliceInitialBalance = ethscriptions.balanceOf(alice);
        uint256 bobInitialBalance = ethscriptions.balanceOf(bob);

        // Create multiple ethscriptions
        uint256 token1 = _createEthscription(alice, alice, keccak256("tx1"), "hello1");
        uint256 token2 = _createEthscription(alice, alice, keccak256("tx2"), "hello2");
        uint256 token3 = _createEthscription(bob, bob, keccak256("tx3"), "hello3");

        // Alice owns 2 more tokens
        assertEq(ethscriptions.balanceOf(alice), aliceInitialBalance + 2);
        assertEq(ethscriptions.tokenOfOwnerByIndex(alice, aliceInitialBalance), token1);
        assertEq(ethscriptions.tokenOfOwnerByIndex(alice, aliceInitialBalance + 1), token2);

        // Bob owns 1 more token
        assertEq(ethscriptions.balanceOf(bob), bobInitialBalance + 1);
        assertEq(ethscriptions.tokenOfOwnerByIndex(bob, bobInitialBalance), token3);
    }

    function testTransferUpdatesEnumeration() public {
        uint256 aliceInitialBalance = ethscriptions.balanceOf(alice);
        uint256 bobInitialBalance = ethscriptions.balanceOf(bob);

        // Create ethscription owned by alice
        uint256 tokenId = _createEthscription(alice, alice, keccak256("tx1"), "hello");

        // Transfer from alice to bob
        vm.prank(alice);
        ethscriptions.transferFrom(alice, bob, tokenId);

        // Check alice's balance decreased
        assertEq(ethscriptions.balanceOf(alice), aliceInitialBalance);

        // Check bob's balance increased
        assertEq(ethscriptions.balanceOf(bob), bobInitialBalance + 1);
        assertEq(ethscriptions.tokenOfOwnerByIndex(bob, bobInitialBalance), tokenId);
    }

    function testSupportsIERC721Enumerable() public {
        // Check that it supports IERC721Enumerable interface
        bytes4 ierc721EnumerableInterfaceId = 0x780e9d63;
        assertTrue(ethscriptions.supportsInterface(ierc721EnumerableInterfaceId));
    }

    function testNullAddressOwnership() public {
        uint256 nullInitialBalance = ethscriptions.balanceOf(address(0));
        uint256 initialSupply = ethscriptions.totalSupply();

        // Create ethscription owned by alice
        uint256 tokenId = _createEthscription(alice, alice, keccak256("tx1"), "hello");

        // Transfer to address(0) - this should work in our implementation
        vm.prank(alice);
        ethscriptions.transferFrom(alice, address(0), tokenId);

        // Check that address(0) owns the token
        assertEq(ethscriptions.ownerOf(tokenId), address(0));
        assertEq(ethscriptions.balanceOf(address(0)), nullInitialBalance + 1);

        // Token should still be enumerable
        assertEq(ethscriptions.totalSupply(), initialSupply + 1);
        assertEq(ethscriptions.tokenOfOwnerByIndex(address(0), nullInitialBalance), tokenId);
    }

    function testRevertOnOutOfBoundsIndex() public {
        uint256 currentSupply = ethscriptions.totalSupply();

        // Test tokenByIndex out of bounds
        vm.expectRevert(abi.encodeWithSelector(ERC721EthscriptionsUpgradeable.ERC721OutOfBoundsIndex.selector, address(0), currentSupply));
        ethscriptions.tokenByIndex(currentSupply);

        // Test tokenOfOwnerByIndex out of bounds for alice
        uint256 aliceBalance = ethscriptions.balanceOf(alice);
        if (aliceBalance > 0) {
            vm.expectRevert(abi.encodeWithSelector(ERC721EthscriptionsUpgradeable.ERC721OutOfBoundsIndex.selector, alice, aliceBalance));
            ethscriptions.tokenOfOwnerByIndex(alice, aliceBalance);
        } else {
            // Create one token for alice if she has none
            _createEthscription(alice, alice, keccak256("tx1"), "hello");
            vm.expectRevert(abi.encodeWithSelector(ERC721EthscriptionsUpgradeable.ERC721OutOfBoundsIndex.selector, alice, 1));
            ethscriptions.tokenOfOwnerByIndex(alice, 1);
        }
    }
}
