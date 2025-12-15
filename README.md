# Ethscriptions L2 Derivation Node

This repo houses the Ruby app and Solidity predeploys that build the Ethscriptions chain on top of Ethereum. It started life as a Postgres-backed indexer; it now runs the derivation pipeline that turns L1 activity into canonical L2 blocks. You run it alongside an [ethscriptions-geth](https://github.com/ethscriptions-protocol/ethscriptions-geth) execution client.

## Table of Contents

- [Overview](#overview)
- [Run with Docker Compose](#run-with-docker-compose)
- [How Ethscriptions Work](#how-ethscriptions-work)
- [Protocol System](#protocol-system)
- [ERC-721 Collections Protocol](#erc-721-collections-protocol)
- [ERC-20 Fixed Denomination Tokens](#erc-20-fixed-denomination-tokens)
- [Technical Architecture](#technical-architecture)
- [Validator](#validator-optional)
- [Local Development](#local-development-optional)
- [Directory Structure](#directory-structure)
- [Testing](#testing)

---

## Overview

### How the Pipeline Works

1. **Observe** Ethereum L1 via JSON-RPC. The importer follows L1 blocks, receipts, and logs to find Ethscriptions intents (Data URIs plus ESIP events).
2. **Translate** matching intents into deposit-style EVM transactions that call Ethscriptions predeploy contracts (storage, transfers, collections tooling).
3. **Send** those transactions to geth through the Engine API, producing new L2 payloads. Geth seals the block, the predeploys mutate state, and the chain advances with the Ethscriptions rules baked in.

The result is an OP-style Stage-2 "app chain" that keeps Ethscriptions UX unchanged while providing Merkle-state, receipts, and compatibility with standard EVM tooling.

### What Lives Here

- **Ruby derivation app** — importer loop and Engine API driver; it is meant to stay stateless across runs.
- **Solidity contracts** — the Ethscriptions and token/collection predeploys plus Foundry scripts for generating the L2 genesis allocations. The Ethscriptions contract stores content with SSTORE2 chunked pointers and routes protocol calls through on-chain handlers.
- **Genesis + tooling** — scripts in `lib/` and `contracts/script/` to produce the genesis file consumed by geth.
- **Reference validator** — optional job queue that compares L2 receipts/storage against a reference Ethscriptions API to make sure derivation matches expectations.

Anything that executes L2 transactions (the `ethscriptions-geth` client) runs out-of-repo. This project focuses on deriving state and providing reference contracts.

### What Stays the Same for Users

Ethscriptions behavior and APIs remain identical to the pre-chain era: inscribe and transfer as before, and existing clients can keep using the public API. The difference is that the data now lives in an L2 with cryptographic state, receipts, and interoperability with EVM tooling.

---

## Run with Docker Compose

### Prerequisites

- Docker Desktop (includes the Compose plugin)
- Access to an Ethereum L1 RPC endpoint (archive-quality recommended for historical sync)

### Quick Start

```bash
# 1. Copy the environment template
cp docker-compose/.env.example docker-compose/.env

# 2. Edit .env with your settings (see Environment Reference below)
#    At minimum, set L1_RPC_URL to your L1 endpoint

# 3. Bring up the stack
cd docker-compose
docker compose --env-file .env up -d

# 4. Follow logs while it syncs
docker compose logs -f node

# 5. Query the L2 RPC (default port 8545)
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# 6. Shut down when done
docker compose down
```

### Services

The stack runs two containers:

| Service | Description |
|---------|-------------|
| `geth` | Ethscriptions-customized Ethereum execution client (L2) |
| `node` | Ruby derivation app that processes L1 data into L2 blocks |

The node waits for geth to be healthy before starting. Both services communicate via a shared IPC socket.

### Environment Reference

Key variables in `docker-compose/.env`:

#### Core Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `COMPOSE_PROJECT_NAME` | Docker resource naming prefix | `ethscriptions-evm` |
| `JWT_SECRET` | 32-byte hex for Engine API auth (must match geth) | — |
| `L1_NETWORK` | Ethereum network (mainnet, sepolia, etc.) | `mainnet` |
| `L1_RPC_URL` | Archive-quality L1 RPC endpoint | — |
| `L1_GENESIS_BLOCK` | L1 block where the rollup anchors | `17478949` |
| `GENESIS_FILE` | Genesis snapshot filename | `ethscriptions-mainnet.json` |
| `GETH_EXTERNAL_PORT` | Host port for L2 RPC | `8545` |

#### Performance Tuning

| Variable | Description | Default |
|----------|-------------|---------|
| `L1_PREFETCH_FORWARD` | Blocks to prefetch ahead | `200` |
| `L1_PREFETCH_THREADS` | Prefetch worker threads | `10` |
| `JOB_CONCURRENCY` | SolidQueue worker concurrency | `6` |
| `JOB_THREADS` | Job worker threads | `3` |

#### Geth Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `GC_MODE` | `full` (pruned) or `archive` (full history) | `full` |
| `STATE_HISTORY` | State trie history depth | `100000` |
| `TX_HISTORY` | Transaction history depth | `100000` |
| `ENABLE_PREIMAGES` | Retain preimages | `true` |
| `CACHE_SIZE` | State cache size | `25000` |

#### Validation (Optional)

| Variable | Description | Default |
|----------|-------------|---------|
| `VALIDATION_ENABLED` | Enable validator against reference API | `false` |
| `ETHSCRIPTIONS_API_BASE_URL` | Reference API endpoint | — |
| `ETHSCRIPTIONS_API_KEY` | API authentication key | — |

---

## How Ethscriptions Work

Ethscriptions are digital artifacts created by encoding data in Ethereum transaction calldata or emitting specific events. This section explains how to create and transfer them.

### Creating Ethscriptions

#### Method 1: Calldata (Direct)

Send a transaction to any address with hex-encoded Data URI as calldata:

```
To: 0xAnyAddress
Value: 0 ETH
Data: 0x646174613a2c48656c6c6f  (hex of "data:,Hello")
```

The derivation node recognizes the Data URI pattern and creates an ethscription:
- **Creator**: The transaction sender (`msg.sender`)
- **Initial Owner**: The transaction recipient (`to` address)
- **Content**: Decoded payload from the Data URI

#### Method 2: Events (ESIP-3)

Smart contracts can create ethscriptions by emitting:

```solidity
event ethscriptions_protocol_CreateEthscription(
    address indexed initialOwner,
    string contentUri
);
```

This allows contracts to programmatically create ethscriptions on behalf of users.

### Data URI Format

The basic format:
```
data:[<mediatype>][;base64],<data>
```

Examples:
```
data:,Hello World                          # Plain text
data:text/plain,Hello World                # Explicit MIME type
data:image/png;base64,iVBORw0KGgo...       # Base64-encoded image
data:application/json,{"name":"test"}      # JSON data
```

Extended format with protocol parameters:
```
data:<mediatype>;rule=esip6;p=<protocol>;op=<operation>;d=<base64-params>;base64,<content>
```

| Parameter | Description |
|-----------|-------------|
| `rule=esip6` | Allow duplicate content URIs |
| `p=<protocol>` | Protocol handler name |
| `op=<operation>` | Operation to invoke on handler |
| `d=<base64>` | Base64-encoded operation parameters |

### Transferring Ethscriptions

#### Method 1: Calldata Transfer

Send a transaction with the ethscription ID (L1 tx hash) as calldata:

**Single transfer** (32 bytes):
```
To: 0xRecipient
Value: 0 ETH
Data: 0xa1654c9db8847e197bbc72c880d1c269d974b15a2e606e4f5b1be2c5da81ba86
```

**Batch transfer** (multiple of 32 bytes, ESIP-5):
```
To: 0xRecipient
Value: 0 ETH
Data: 0x<txhash1><txhash2><txhash3>  (concatenated 32-byte hashes)
```

#### Method 2: Event Transfer

Contracts can transfer by emitting:

**ESIP-1** (basic transfer):
```solidity
event ethscriptions_protocol_TransferEthscription(
    address indexed recipient,
    bytes32 indexed ethscriptionId
);
```

**ESIP-2** (with previous owner validation):
```solidity
event ethscriptions_protocol_TransferEthscriptionForPreviousOwner(
    address indexed previousOwner,
    address indexed recipient,
    bytes32 indexed ethscriptionId
);
```

### ESIP Standards Reference

| ESIP | Name | Description |
|------|------|-------------|
| ESIP-1 | Event Transfers | Transfer via `TransferEthscription` event |
| ESIP-2 | Previous Owner Validation | Transfer with chain-of-custody check |
| ESIP-3 | Event Creation | Create via `CreateEthscription` event |
| ESIP-5 | Batch Transfers | Multiple 32-byte transfers in one tx |
| ESIP-6 | Duplicate Content | Allow same content URI to be inscribed multiple times |
| ESIP-7 | Gzip Compression | Support for gzip-compressed content |

### Example: Creating an Ethscription

Consider mainnet transaction [`0xa165...ba86`](https://etherscan.io/tx/0xa1654c9db8847e197bbc72c880d1c269d974b15a2e606e4f5b1be2c5da81ba86):

- **From**: `0x42e8...d67d`
- **To**: `0xC217...a97`
- **Calldata**: `0x646174613a2c6d6964646c656d61726368`
- **Decoded**: `data:,middlemarch`

The derivation node:
1. Recognizes the Data URI pattern
2. Builds creation parameters:
   - `ethscriptionId`: The L1 tx hash
   - `contentUriHash`: SHA256 of the raw Data URI
   - `initialOwner`: `0xC217...a97` (the recipient)
   - `content`: `middlemarch` (decoded bytes)
   - `mimetype`: `text/plain;charset=utf-8`
3. Creates a deposit transaction calling `Ethscriptions.createEthscription()`
4. The L2 contract stores content via SSTORE2, mints an NFT to the initial owner

---

## Protocol System

Ethscriptions supports pluggable protocol handlers that extend functionality. When an ethscription includes protocol parameters, the main contract routes the call to a registered handler.

### How It Works

1. **Registration**: Handlers register with the main contract:
   ```solidity
   Ethscriptions.registerProtocol("my-protocol", handlerAddress);
   ```

2. **Invocation**: When creating an ethscription with protocol params:
   ```
   data:image/png;p=my-protocol;op=mint;d=<base64-params>;base64,<image>
   ```

3. **Handler Call**: The contract calls `handler.op_mint(params)` after storing the ethscription.

### Built-in Protocols

| Protocol | Purpose |
|----------|---------|
| `erc-721-ethscriptions-collection` | Curated NFT collections with merkle enforcement |
| `erc-20-fixed-denomination` | Fungible tokens with fixed-denomination notes |

### Protocol Data URI Format

Two encoding styles are supported:

**Header-based** (for binary content like images):
```
data:image/png;p=erc-721-ethscriptions-collection;op=add_self_to_collection;d=<base64-json>;base64,<image-bytes>
```

**JSON body** (for text-based operations):
```
data:application/json,{"p":"erc-20-fixed-denomination","op":"deploy","tick":"mytoken","max":"1000000","lim":"1000"}
```

---

## ERC-721 Collections Protocol

The collections protocol allows creators to build curated NFT collections with optional merkle proof enforcement.

### Overview

- **Collection**: A named set of ethscriptions with metadata (name, symbol, description, max supply)
- **Items**: Individual ethscriptions added to a collection
- **Merkle Enforcement**: Optional cryptographic restriction on which items can be added

### Creating a Collection

Use the `create_collection_and_add_self` operation:

```
data:image/png;rule=esip6;p=erc-721-ethscriptions-collection;op=create_collection_and_add_self;d=<base64-json>;base64,<image>
```

Where the base64-decoded JSON contains:
```json
{
  "name": "My Collection",
  "symbol": "MYC",
  "maxSupply": 100,
  "description": "A curated collection of...",
  "logoImageUri": "data:image/png;base64,...",
  "bannerImageUri": "data:image/png;base64,...",
  "website": "https://example.com",
  "twitterHandle": "myhandle",
  "discordUrl": "https://discord.gg/...",
  "backgroundColor": "#000000",
  "merkleRoot": "0x06fbc22a...",
  "itemIndex": 0,
  "itemName": "Item #1",
  "itemBackgroundColor": "#FF0000",
  "itemDescription": "The first item",
  "itemAttributes": [["Rarity", "Legendary"], ["Color", "Red"]]
}
```

### Merkle Proof Enforcement

When a collection has a non-zero `merkleRoot`, non-owners must provide a merkle proof to add items. This ensures only pre-approved items with exact metadata can be added.

**How it works:**

1. Creator generates a merkle tree from approved items
2. Each leaf is computed as:
   ```solidity
   keccak256(abi.encode(
       contentHash,      // keccak256 of content bytes
       itemIndex,        // uint256
       name,             // string
       backgroundColor,  // string
       description,      // string
       attributes        // (string,string)[]
   ))
   ```
3. Creator sets the merkle root when creating the collection
4. Non-owners provide proofs when adding items:
   ```json
   {
     "collectionId": "0x...",
     "itemIndex": 1,
     "itemName": "Item #2",
     "merkleProof": ["0xaab5a305...", "0x58672b0c..."]
   }
   ```

**Owner bypass**: Collection owners can always add items without proofs.

### Operations Reference

| Operation | Description |
|-----------|-------------|
| `create_collection_and_add_self` | Create collection and add first item |
| `add_self_to_collection` | Add item to existing collection |
| `edit_collection` | Update collection metadata |
| `edit_collection_item` | Update item metadata |
| `transfer_ownership` | Transfer collection ownership |
| `renounce_ownership` | Surrender ownership |
| `remove_items` | Delete items from collection |
| `lock_collection` | Prevent further additions |

For a complete walkthrough with code, see [`docs/merkle-collection-demo.md`](docs/merkle-collection-demo.md).

---

## ERC-20 Fixed Denomination Tokens

The fixed-denomination protocol creates fungible tokens where balances move in fixed batches (denominations) tied to NFT notes.

### How It Differs from Standard ERC-20

- **No direct transfers**: ERC-20 `transfer()` is disabled
- **Note-based**: Each mint creates an NFT "note" representing a fixed token amount
- **Coupled movement**: Transferring the note automatically moves the ERC-20 balance
- **Inscription-driven**: All operations flow through ethscription creation/transfer

### Deploy a Token

Create an ethscription with JSON content:
```json
{
  "p": "erc-20-fixed-denomination",
  "op": "deploy",
  "tick": "mytoken",
  "max": "1000000",
  "lim": "1000"
}
```

| Field | Description |
|-------|-------------|
| `tick` | Token symbol (lowercase alphanumeric, max 28 chars) |
| `max` | Maximum total supply |
| `lim` | Amount per mint note (the denomination) |

### Mint Notes

After deployment, mint notes with:
```json
{
  "p": "erc-20-fixed-denomination",
  "op": "mint",
  "tick": "mytoken",
  "id": "0",
  "amt": "1000"
}
```

| Field | Description |
|-------|-------------|
| `tick` | Token symbol |
| `id` | Unique note identifier |
| `amt` | Token amount (typically equals `lim`) |

### Transfer Mechanics

When you transfer the mint inscription (the NFT note):
1. The inscription moves to the new owner
2. The ERC-20 balance automatically moves with it
3. Both the ERC-721 note and ERC-20 balance are synchronized

This ensures tokens can only move in fixed denominations and are always tied to their note NFTs.

---

## Technical Architecture

### Pipeline Flow

```
L1 Block
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  L1 RPC Prefetcher (threaded)                           │
│  - Fetches blocks, receipts, logs ahead of import       │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  EthBlockImporter                                       │
│  - Parses calldata for Data URIs                        │
│  - Extracts ESIP events from receipts                   │
│  - Builds EthscriptionTransaction objects               │
└─────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  GethDriver (Engine API)                                │
│  - Creates L1Attributes system transaction              │
│  - Combines with ethscription transactions              │
│  - engine_forkchoiceUpdatedV3                           │
│  - engine_getPayloadV3                                  │
│  - engine_newPayloadV3                                  │
└─────────────────────────────────────────────────────────┘
    │
    ▼
L2 Block Sealed
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│  Ethscriptions Contract (L2)                            │
│  - createEthscription() → SSTORE2 storage               │
│  - transferEthscription() → NFT transfer                │
│  - Protocol handler invocations                         │
│  - Events emitted                                       │
└─────────────────────────────────────────────────────────┘
```

### Deposit Transactions

The derivation node creates EIP-2718 type `0x7d` deposit transactions:

```
Type: 0x7d (Deposit)
Fields:
  - sourceHash: Unique identifier derived from L1 tx
  - from: Original L1 sender (spoofed via deposit semantics)
  - to: Ethscriptions contract address
  - mint: 0 (no ETH minted)
  - value: 0
  - gasLimit: Allocated gas for execution
  - isSystemTx: false
  - data: ABI-encoded contract call
```

Deposit semantics allow the derivation process to set `msg.sender` to the original L1 transaction sender, even though the payload is submitted by the node.

### Content Storage (SSTORE2)

Large content is stored using SSTORE2:
- Content is split into chunks
- Each chunk is deployed as contract bytecode
- Pointers are stored in the main contract
- Retrieval concatenates chunks

Benefits:
- Cheaper than SSTORE for large content
- Content is immutable
- Gas-efficient reads

### Source Hashing

Each deposit transaction gets a unique `sourceHash` following Optimism conventions:
```
sourceHash = keccak256(
    domain (0) ||
    keccak256(blockHash || sourceTypeHash || selector || sourceIndex)
)
```

This ensures deterministic, reproducible derivation.

---

## Validator (Optional)

The validator reads expected creations/transfers from your Ethscriptions API and compares them with receipts and storage pulled from geth. It pauses the importer when discrepancies appear so you can investigate mismatches or RPC issues.

### Enable Validation

```bash
VALIDATION_ENABLED=true
ETHSCRIPTIONS_API_BASE_URL=https://your-api-endpoint.com
ETHSCRIPTIONS_API_KEY=your-api-key
```

The temporary SQLite databases in `storage/` and the SolidQueue worker pool exist only to support this reconciliation. Once historical import is verified, the goal is to remove that persistence and keep the derivation app stateless.

---

## Local Development (Optional)

If you want to modify the Ruby code outside of Docker:

```bash
# Install Ruby 3.4.x (via rbenv, rvm, or asdf)
ruby --version  # Should show 3.4.x

# Install dependencies
bundle install

# Initialize local SQLite files
bin/setup

# Run the derivation (requires running ethscriptions-geth and L1 RPC)
# See bin/jobs and config/derive_ethscriptions_blocks.rb
```

The Compose stack is the recommended path for production-like runs.

---

## Directory Structure

```
ethscriptions-indexer/
├── app/
│   ├── models/           # Ethscription transaction models, protocol parsers
│   └── services/         # Derivation logic, Engine API driver
├── contracts/
│   ├── src/              # Solidity predeploys
│   │   ├── Ethscriptions.sol
│   │   ├── ERC721EthscriptionsCollectionManager.sol
│   │   └── ERC20FixedDenominationManager.sol
│   ├── script/           # Genesis allocation scripts
│   └── test/             # Foundry tests
├── docker-compose/
│   ├── docker-compose.yml
│   ├── .env.example
│   └── docs/             # Protocol documentation
├── docs/                 # Additional documentation
├── lib/                  # Genesis builders, utilities
├── spec/                 # RSpec tests
└── storage/              # SQLite databases (validation)
```

---

## Testing

### Ruby Tests

```bash
bundle exec rspec
```

### Solidity Tests

```bash
cd contracts
forge test
```

### With Verbose Output

```bash
bundle exec rspec --format documentation
forge test -vvv
```

---

## Questions or Contributions

Open an issue or reach out in the Ethscriptions community channels.
