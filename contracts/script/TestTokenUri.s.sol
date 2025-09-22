// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/Ethscriptions.sol";
import "../script/L2Genesis.s.sol";
import {Base64} from "solady/utils/Base64.sol";

contract TestTokenUri is Script {
    function run() public {
        // Deploy system
        L2Genesis genesis = new L2Genesis();
        genesis.runWithoutDump();

        Ethscriptions eth = Ethscriptions(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        // Test case 1: Plain text (should use viewer)
        vm.prank(address(0x1111));
        eth.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("text1"),
            contentUriHash: keccak256("data:text/plain,Hello World!"),
            initialOwner: address(0x1111),
            content: bytes("Hello World!"),
            mimetype: "text/plain",
            mediaType: "text",
            mimeSubtype: "plain",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams("", "", "", 0, 0, 0)
        }));

        // Test case 2: JSON content (should use viewer with pretty print)
        vm.prank(address(0x2222));
        eth.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("json1"),
            contentUriHash: keccak256('data:application/json,{"p":"erc-20","op":"mint","tick":"test","amt":"1000"}'),
            initialOwner: address(0x2222),
            content: bytes('{"p":"erc-20","op":"mint","tick":"test","amt":"1000"}'),
            mimetype: "application/json",
            mediaType: "application",
            mimeSubtype: "json",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams("", "", "", 0, 0, 0)
        }));

        // Test case 3: HTML content (should pass through directly)
        vm.prank(address(0x3333));
        eth.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("html1"),
            contentUriHash: keccak256('data:text/html,<html><body style="background:linear-gradient(45deg,#ff006e,#8338ec);color:white;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0"><h1>Ethscriptions Rule!</h1></body></html>'),
            initialOwner: address(0x3333),
            content: bytes('<html><body style="background:linear-gradient(45deg,#ff006e,#8338ec);color:white;font-family:monospace;display:flex;align-items:center;justify-content:center;height:100vh;margin:0"><h1>Ethscriptions Rule!</h1></body></html>'),
            mimetype: "text/html",
            mediaType: "text",
            mimeSubtype: "html",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams("", "", "", 0, 0, 0)
        }));

        // Test case 4: Image (1x1 red pixel PNG, base64)
        bytes memory redPixelPng = Base64.decode("iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAm0lEQVR42mNgGITgPxTTxvBleTo0swBsOK0s+N8aJkczC1AMR7KAKpb8v72xAY5hFsD4lFoCN+j56ZUoliBbSoklGIZjwxRbQAjT1YK7d+82kGUBeuQii5FrAYYrL81NwCpGFQtoEUT/6RoHWAyknQV0S6ZI5RE6Jt8CZIOOHTuGgR9Fq5FkCf19QM3wx5rZKHEtsRZQt5qkhgUAR6cGaUehOD4AAAAASUVORK5CYII=");
        vm.prank(address(0x4444));
        eth.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("image1"),
            contentUriHash: keccak256("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAm0lEQVR42mNgGITgPxTTxvBleTo0swBsOK0s+N8aJkczC1AMR7KAKpb8v72xAY5hFsD4lFoCN+j56ZUoliBbSoklGIZjwxRbQAjT1YK7d+82kGUBeuQii5FrAYYrL81NwCpGFQtoEUT/6RoHWAyknQV0S6ZI5RE6Jt8CZIOOHTuGgR9Fq5FkCf19QM3wx5rZKHEtsRZQt5qkhgUAR6cGaUehOD4AAAAASUVORK5CYII="),
            initialOwner: address(0x4444),
            content: redPixelPng,
            mimetype: "image/png",
            mediaType: "image",
            mimeSubtype: "png",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams("", "", "", 0, 0, 0)
        }));

        // Test case 5: CSS content (should use viewer)
        vm.prank(address(0x5555));
        eth.createEthscription(Ethscriptions.CreateEthscriptionParams({
            transactionHash: keccak256("css1"),
            contentUriHash: keccak256("data:text/css,body { background: #000; color: #0f0; font-family: 'Courier New'; }"),
            initialOwner: address(0x5555),
            content: bytes("body { background: #000; color: #0f0; font-family: 'Courier New'; }"),
            mimetype: "text/css",
            mediaType: "text",
            mimeSubtype: "css",
            esip6: false,
            tokenParams: Ethscriptions.TokenParams("", "", "", 0, 0, 0)
        }));

        // Output all token URIs
        console.log("\n=== TOKEN URI TEST RESULTS ===\n");

        console.log("Test 1 - Plain Text (text/plain):");
        console.log("Should use HTML viewer with content displayed");
        string memory uri1 = eth.tokenURI(11);
        console.log(uri1);
        console.log("");

        console.log("Test 2 - JSON (application/json):");
        console.log("Should use HTML viewer with pretty-printed JSON");
        string memory uri2 = eth.tokenURI(12);
        console.log(uri2);
        console.log("");

        console.log("Test 3 - HTML (text/html):");
        console.log("Should pass through HTML directly in animation_url");
        string memory uri3 = eth.tokenURI(13);
        console.log(uri3);
        console.log("");

        console.log("Test 4 - Image (image/png):");
        console.log("Should use image field (not animation_url)");
        string memory uri4 = eth.tokenURI(14);
        console.log(uri4);
        console.log("");

        console.log("Test 5 - CSS (text/css):");
        console.log("Should use HTML viewer");
        string memory uri5 = eth.tokenURI(15);
        console.log(uri5);
        console.log("");

        console.log("=== PASTE ANY OF THE ABOVE data: URIs INTO YOUR BROWSER ===");
    }
}