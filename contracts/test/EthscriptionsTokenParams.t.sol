// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./TestSetup.sol";
import "forge-std/console.sol";

contract EthscriptionsTokenParamsTest is TestSetup {

    function testCreateWithTokenDeployParams() public {
        // Create a token deploy ethscription
        string memory tokenJson = '{"p":"erc-20","op":"deploy","tick":"eths","max":"21000000","lim":"1000"}';
        string memory dataUri = string.concat("data:,", tokenJson);
        bytes32 contentUriHash = sha256(bytes(dataUri));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: bytes32(uint256(1)),
            contentUriHash: contentUriHash,
            initialOwner: address(this),
            content: bytes(tokenJson),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "eths",
                max: 21000000,
                lim: 1000,
                amt: 0
            })
        });

        // Create the ethscription
        ethscriptions.createEthscription(params);

        // Verify it was created
        assertEq(ethscriptions.totalSupply(), 12, "Should have created new ethscription");

        // Get the ethscription data
        Ethscriptions.Ethscription memory eth = ethscriptions.getEthscription(params.transactionHash);
        assertEq(eth.creator, address(this), "Creator should match");
        assertEq(eth.initialOwner, address(this), "Initial owner should match");
    }

    function testCreateWithTokenMintParams() public {
        // Create a token mint ethscription
        string memory tokenJson = '{"p":"erc-20","op":"mint","tick":"eths","id":"1","amt":"1000"}';
        string memory dataUri = string.concat("data:,", tokenJson);
        bytes32 contentUriHash = sha256(bytes(dataUri));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: bytes32(uint256(2)),
            contentUriHash: contentUriHash,
            initialOwner: address(this),
            content: bytes(tokenJson),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "eths",
                max: 1,  // id stored in max field
                lim: 0,
                amt: 1000
            })
        });

        // Create the ethscription
        ethscriptions.createEthscription(params);

        // Verify it was created
        assertEq(ethscriptions.totalSupply(), 12, "Should have created new ethscription");
    }

    function testCreateWithoutTokenParams() public {
        // Create a regular non-token ethscription
        string memory content = "Hello, World!";
        string memory dataUri = string.concat("data:,", content);
        bytes32 contentUriHash = sha256(bytes(dataUri));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            transactionHash: bytes32(uint256(3)),
            contentUriHash: contentUriHash,
            initialOwner: address(this),
            content: bytes(content),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "",
                protocol: "",
                tick: "",
                max: 0,
                lim: 0,
                amt: 0
            })
        });

        // Create the ethscription
        ethscriptions.createEthscription(params);

        // Verify it was created
        assertEq(ethscriptions.totalSupply(), 12, "Should have created new ethscription");
    }

    function testTokenManagerIntegration() public {
        // First create a deploy operation
        string memory deployJson = '{"p":"erc-20","op":"deploy","tick":"test","max":"1000000","lim":"100"}';
        string memory deployUri = string.concat("data:,", deployJson);

        Ethscriptions.CreateEthscriptionParams memory deployParams = Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("deploy_tx"),
            contentUriHash: sha256(bytes(deployUri)),
            initialOwner: address(this),
            content: bytes(deployJson),
            mimetype: "application/json",
            mediaType: "application",
            mimeSubtype: "json",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "deploy",
                protocol: "erc-20",
                tick: "test",
                max: 1000000,
                lim: 100,
                amt: 0
            })
        });

        ethscriptions.createEthscription(deployParams);

        // Then create a mint operation
        string memory mintJson = '{"p":"erc-20","op":"mint","tick":"test","id":"1","amt":"100"}';
        string memory mintUri = string.concat("data:,", mintJson);

        Ethscriptions.CreateEthscriptionParams memory mintParams = Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("mint_tx"),
            contentUriHash: sha256(bytes(mintUri)),
            initialOwner: address(this),
            content: bytes(mintJson),
            mimetype: "application/json",
            mediaType: "application",
            mimeSubtype: "json",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams({
                op: "mint",
                protocol: "erc-20",
                tick: "test",
                max: 1,  // id
                lim: 0,
                amt: 100
            })
        });

        ethscriptions.createEthscription(mintParams);

        // Verify both were created
        assertEq(ethscriptions.totalSupply(), 13, "Should have 13 total (11 genesis + 2 new)");
    }
}