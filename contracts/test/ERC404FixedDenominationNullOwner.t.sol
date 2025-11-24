// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "../src/ERC20FixedDenominationManager.sol";
import "../src/ERC20FixedDenomination.sol";
import {LibString} from "solady/utils/LibString.sol";

contract ERC404FixedDenominationNullOwnerTest is TestSetup {
    using LibString for uint256;

    string constant CANONICAL_PROTOCOL = "erc-20-fixed-denomination";
    address alice = address(0x1);
    address bob = address(0x2);

    error NotImplemented();

    function setUp() public override {
        super.setUp();
    }

    function createTokenParams(
        bytes32 transactionHash,
        address initialOwner,
        string memory contentUri,
        string memory protocol,
        string memory operation,
        bytes memory data
    ) internal pure returns (Ethscriptions.CreateEthscriptionParams memory) {
        bytes memory contentUriBytes = bytes(contentUri);
        bytes32 contentUriSha = sha256(contentUriBytes);
        bytes memory content;
        if (contentUriBytes.length > 6) {
            content = new bytes(contentUriBytes.length - 6);
            for (uint256 i = 0; i < content.length; i++) {
                content[i] = contentUriBytes[i + 6];
            }
        }
        return Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: transactionHash,
            contentUriSha: contentUriSha,
            initialOwner: initialOwner,
            content: content,
            mimetype: "text/plain",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: protocol,
                operation: operation,
                data: data
            })
        });
    }

    function deployToken(string memory tick, uint256 maxSupply, uint256 mintAmount, bytes32 deployId, address initialOwner)
        internal
        returns (address tokenAddr)
    {
        ERC20FixedDenominationManager.DeployOperation memory deployOp = ERC20FixedDenominationManager.DeployOperation({
            tick: tick,
            maxSupply: maxSupply,
            mintAmount: mintAmount
        });
        string memory deployContent =
            string(abi.encodePacked('data:,{"p":"erc-20","op":"deploy","tick":"', tick, '","max":"', maxSupply.toString(), '","lim":"', mintAmount.toString(), '"}'));

        vm.prank(initialOwner);
        ethscriptions.createEthscription(
            createTokenParams(
                deployId,
                initialOwner,
                deployContent,
                CANONICAL_PROTOCOL,
                "deploy",
                abi.encode(deployOp)
            )
        );
        tokenAddr = fixedDenominationManager.getTokenAddressByTick(tick);
    }

    function mintNote(address tokenAddr, string memory tick, uint256 id, uint256 amount, bytes32 mintTx, address initialOwner)
        internal
    {
        ERC20FixedDenominationManager.MintOperation memory mintOp = ERC20FixedDenominationManager.MintOperation({
            tick: tick,
            id: id,
            amount: amount
        });
        string memory mintContent =
            string(abi.encodePacked('data:,{"p":"erc-20","op":"mint","tick":"', tick, '","id":"', id.toString(), '","amt":"', amount.toString(), '"}'));

        vm.prank(alice);
        ethscriptions.createEthscription(
            createTokenParams(
                mintTx,
                initialOwner,
                mintContent,
                CANONICAL_PROTOCOL,
                "mint",
                abi.encode(mintOp)
            )
        );
    }

    function testMintToOwnerAndNullOwnerViaManager() public {
        address tokenAddr = deployToken("TNULL", 10000, 1000, bytes32(uint256(0x9999)), alice);
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);

        // Mint to bob
        mintNote(tokenAddr, "TNULL", 1, 1000, bytes32(uint256(0xAAAA)), bob);
        assertEq(token.balanceOf(bob), 1000 * 1e18);
        assertEq(token.ownerOf(1), bob);
        assertEq(token.totalSupply(), 1000 * 1e18);

        // Mint to null owner (initialOwner = 0) should end with 0x0 owning NFT and ERC20
        mintNote(tokenAddr, "TNULL", 2, 1000, bytes32(uint256(0xBBBB)), address(0));
        assertEq(token.balanceOf(address(0)), 1000 * 1e18);
        assertEq(token.ownerOf(2), address(0));
        assertEq(token.totalSupply(), 2000 * 1e18);
    }

    function testForceTransferToZeroKeepsSupply() public {
        address tokenAddr = deployToken("FORCE", 10000, 1000, bytes32(uint256(0x4242)), alice);
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);

        // Mint to bob
        mintNote(tokenAddr, "FORCE", 1, 1000, bytes32(uint256(0xCAFE)), bob);
        uint256 supplyBefore = token.totalSupply();

        // Manager forceTransfer to zero
        vm.prank(address(fixedDenominationManager));
        token.forceTransfer(bob, address(0), 1);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(address(0)), 1000 * 1e18);
        assertEq(token.ownerOf(1), address(0));
    }

    function testCapEnforcedOnMint() public {
        // cap: maxSupply 1000, mintAmount 1000 => only 1 note allowed
        address tokenAddr = deployToken("CAPX", 1000, 1000, bytes32(uint256(0xDEAD)), alice);
        ERC20FixedDenomination token = ERC20FixedDenomination(tokenAddr);

        // First mint succeeds
        mintNote(tokenAddr, "CAPX", 1, 1000, bytes32(uint256(0x1111)), bob);
        assertEq(token.totalSupply(), 1000 * 1e18);

        // Second mint should revert on cap (call mint directly via manager role)
        vm.prank(address(fixedDenominationManager));
        vm.expectRevert();
        token.mint(bob, 2);
        assertEq(token.totalSupply(), 1000 * 1e18);
    }
}
