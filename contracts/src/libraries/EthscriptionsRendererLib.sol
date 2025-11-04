// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Ethscriptions} from "../Ethscriptions.sol";

/// @title EthscriptionsRendererLib
/// @notice Library for rendering Ethscription metadata and media URIs
/// @dev Contains all token URI generation, media handling, and metadata formatting logic
library EthscriptionsRendererLib {
    using LibString for *;

    /// @notice Build attributes JSON array from ethscription data
    /// @param etsc Storage pointer to the ethscription
    /// @param ethscriptionId The ethscription ID (L1 tx hash)
    /// @return JSON string of attributes array
    function buildAttributes(Ethscriptions.EthscriptionStorage storage etsc, bytes32 ethscriptionId)
        internal
        view
        returns (string memory)
    {
        // Build in chunks to avoid stack too deep
        string memory part1 = string.concat(
            '[{"trait_type":"Ethscription ID","value":"',
            uint256(ethscriptionId).toHexString(),
            '"},{"trait_type":"Ethscription Number","display_type":"number","value":',
            etsc.ethscriptionNumber.toString(),
            '},{"trait_type":"Creator","value":"',
            etsc.creator.toHexString(),
            '"},{"trait_type":"Initial Owner","value":"',
            etsc.initialOwner.toHexString()
        );

        string memory part2 = string.concat(
            '"},{"trait_type":"Content SHA","value":"',
            uint256(etsc.contentSha).toHexString(),
            '"},{"trait_type":"MIME Type","value":"',
            etsc.mimetype.escapeJSON(),
            '"},{"trait_type":"ESIP-6","value":"',
            etsc.esip6 ? "true" : "false",
            '"},{"trait_type":"L1 Block Number","display_type":"number","value":',
            uint256(etsc.l1BlockNumber).toString(),
            '},{"trait_type":"L2 Block Number","display_type":"number","value":',
            uint256(etsc.l2BlockNumber).toString(),
            '},{"trait_type":"Created At","display_type":"date","value":',
            etsc.createdAt.toString(),
            '}]'
        );

        return string.concat(part1, part2);
    }

    /// @notice Generate the media URI for an ethscription
    /// @param etsc Storage pointer to the ethscription
    /// @param content The content bytes
    /// @return mediaType Either "image" or "animation_url"
    /// @return mediaUri The data URI for the media
    function getMediaUri(Ethscriptions.EthscriptionStorage storage etsc, bytes memory content)
        internal
        view
        returns (string memory mediaType, string memory mediaUri)
    {
        if (etsc.mimetype.startsWith("image/")) {
            // Image content: wrap in SVG for pixel-perfect rendering
            string memory imageDataUri = constructDataURI(etsc.mimetype, content);
            string memory svg = wrapImageInSVG(imageDataUri);
            mediaUri = constructDataURI("image/svg+xml", bytes(svg));
            return ("image", mediaUri);
        } else {
            // Non-image content: use animation_url
            if (etsc.mimetype.startsWith("video/") ||
                etsc.mimetype.startsWith("audio/") ||
                etsc.mimetype.eq("text/html")) {
                // Video, audio, and HTML pass through directly as data URIs
                mediaUri = constructDataURI(etsc.mimetype, content);
            } else {
                // Everything else (text/plain, application/json, etc.) uses the HTML viewer
                mediaUri = createTextViewerDataURI(etsc.mimetype, content);
            }
            return ("animation_url", mediaUri);
        }
    }

    /// @notice Build complete token URI JSON
    /// @param etsc Storage pointer to the ethscription
    /// @param ethscriptionId The ethscription ID (L1 tx hash)
    /// @param content The content bytes
    /// @return The complete base64-encoded data URI
    function buildTokenURI(
        Ethscriptions.EthscriptionStorage storage etsc,
        bytes32 ethscriptionId,
        bytes memory content
    ) internal view returns (string memory) {
        // Get media URI
        (string memory mediaType, string memory mediaUri) = getMediaUri(etsc, content);

        // Build attributes
        string memory attributes = buildAttributes(etsc, ethscriptionId);

        // Build JSON
        string memory json = string.concat(
            '{"name":"Ethscription #',
            etsc.ethscriptionNumber.toString(),
            '","description":"Ethscription #',
            etsc.ethscriptionNumber.toString(),
            ' created by ',
            etsc.creator.toHexString(),
            '","',
            mediaType,
            '":"',
            mediaUri.escapeJSON(),
            '","attributes":',
            attributes,
            '}'
        );

        return string.concat(
            "data:application/json;base64,",
            Base64.encode(bytes(json))
        );
    }

    /// @notice Construct a base64-encoded data URI
    /// @param mimetype The MIME type
    /// @param content The content bytes
    /// @return The complete data URI
    function constructDataURI(string memory mimetype, bytes memory content)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "data:",
            mimetype,
            ";base64,",
            Base64.encode(content)
        );
    }

    /// @notice Wrap an image in SVG for pixel-perfect rendering
    /// @param imageDataUri The image data URI to wrap
    /// @return The SVG markup
    function wrapImageInSVG(string memory imageDataUri)
        internal
        pure
        returns (string memory)
    {
        // SVG wrapper that enforces pixelated/nearest-neighbor scaling for pixel art
        return string.concat(
            '<svg width="1200" height="1200" viewBox="0 0 1200 1200" version="1.2" xmlns="http://www.w3.org/2000/svg" style="background-image:url(',
            imageDataUri,
            ');background-repeat:no-repeat;background-size:contain;background-position:center;image-rendering:-webkit-optimize-contrast;image-rendering:-moz-crisp-edges;image-rendering:pixelated;"></svg>'
        );
    }

    /// @notice Create an HTML viewer data URI for text content
    /// @param mimetype The MIME type of the content
    /// @param content The content bytes
    /// @return The HTML viewer data URI
    function createTextViewerDataURI(string memory mimetype, bytes memory content)
        internal
        pure
        returns (string memory)
    {
        // Base64 encode the content for embedding in HTML
        string memory encodedContent = Base64.encode(content);

        // Generate HTML with embedded content
        string memory html = generateTextViewerHTML(encodedContent, mimetype);

        // Return as base64-encoded HTML data URI
        return constructDataURI("text/html", bytes(html));
    }

    /// @notice Generate minimal HTML viewer for text content
    /// @param encodedPayload Base64-encoded content
    /// @param mimetype The MIME type
    /// @return The complete HTML string
    function generateTextViewerHTML(string memory encodedPayload, string memory mimetype)
        internal
        pure
        returns (string memory)
    {
        // Ultra-minimal HTML with inline styles optimized for iframe display
        return string.concat(
            '<!DOCTYPE html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>',
            '<style>*{box-sizing:border-box;margin:0;padding:0;border:0}body{padding:6dvw;background:#0b0b0c;color:#f5f5f5;font-family:monospace;display:flex;justify-content:center;align-items:center;min-height:100dvh;overflow:hidden}',
            'pre{white-space:pre-wrap;word-break:break-word;overflow-wrap:anywhere;line-height:1.4;font-size:14px}</style></head>',
            '<body><pre id="o"></pre><script>',
            'const p="', encodedPayload, '";',
            'const m="', mimetype.escapeJSON(), '";',
            'function d(b){try{return decodeURIComponent(atob(b).split("").map(c=>"%"+("00"+c.charCodeAt(0).toString(16)).slice(-2)).join(""))}catch{return null}}',
            'const r=d(p);let t="";',
            'if(r!==null){t=r;try{const j=JSON.parse(r);t=JSON.stringify(j,null,2)}catch{}}',
            'else{t="data:"+m+";base64,"+p}',
            'document.getElementById("o").textContent=t||"(empty)";',
            '</script></body></html>'
        );
    }
}
