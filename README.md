# Ethscriptions L2 & Indexer (Derivation Stage)

> **Status**: We are actively developing the Optimism-style derivation pipeline. Expect breaking changes, but this README is kept up to date and is the canonical reference for contributors.
>
> **Audience**: Engineers familiar with the legacy Ethscriptions Rails indexer who need to get up to speed on the new L2 contracts, importer, and validation workflow.

---

## 1. TL;DR

- **Vision**: Shift Ethscriptions from a Postgres-backed indexer to an Optimism-style L2 where an ERC-721 contract is the source of truth. Rails now detects protocol intent and forwards it; the chain enforces the rules and stores data.
- **Pipeline**: Fetch L1 blocks → detect creates/transfers (Data URI + ESIP events) → encode deposit transactions → propose L2 blocks through Engine API → contracts mint/transfer via SSTORE2 storage → optional validator cross-checks events and storage.
- **Current Capability**: Create flows work end-to-end. ESIP-1/2/5 transfers are wired but still hardening. Token protocol hooks exist in Solidity; Ruby parsing of token params is pending. Validation tooling works after removing debug breakpoints.
- **Start Here**: Follow [Section 4](#4-from-zero-to-running-setup--operations) to set up your environment, run `./script/run_importer.sh --validate`, and confirm the validator summary.

---

## 2. Background & Design Principles

### 2.1 Why an L2 + On-Chain Storage?

| Goal | Legacy Indexer | New L2 Approach |
|------|----------------|-----------------|
| Canonical data | Rails/Postgres snapshots | Solidity contract state + events |
| User-visible failures | Silent skips | On-chain reverts/logs |
| Content storage cost | Not applicable | SSTORE2 chunking (~14× cheaper than storage) |
| Protocol enforcement | Hard to keep in sync | Contracts enforce ESIPs |
| Scalability | Rebuild DB for every node | Stateless importer forwards intent |

Key principles:
- **Detect vs. Validate**: Ruby detects protocol signals (valid Data URIs, ESIP events) and forwards them. All validation (uniqueness, ownership, previous-owner checks) happens in Solidity.
- **Optimistic Rollup Model**: We reuse Optimism’s deposit transaction pipeline. Each L1 block yields deposit transactions that produce an L2 block proposed to op-geth.
- **Gas-Aware Storage**: SSTORE2 stores content in code chunks (≤24 575 bytes each), dramatically reducing gas vs. standard storage writes.

### 2.2 Architecture Overview

```
          ┌────────────┐          ┌─────────────────┐          ┌────────────┐          ┌───────────────┐
L1 RPC  ─▶│ EthRpcClient│──blocks▶│ EthBlockImporter │──deposits▶│ op-geth L2 │──events/states──▶│ Rails API & Tools │
          └────────────┘          │ + Clockwork loop │          └────────────┘          └───────────────┘
                                   │ detection+encoding│                 ▲
                                   └───────────────────┘                 │
                                                     │ validation (optional)
                                                     ▼
                                              BlockValidator
```

| Layer | Key Code | Responsibilities |
|-------|----------|------------------|
| Contracts | `contracts/src/Ethscriptions.sol`, `ERC721EthscriptionsUpgradeable.sol`, `TokenManager.sol`, `EthscriptionsProver.sol` | Mint/transfer Ethscriptions, SSTORE2 content storage, token protocol hooks, attestations |
| Genesis tooling | `contracts/script/L2Genesis.s.sol`, `lib/genesis_generator.rb` | Produce OP Stack genesis with Ethscriptions predeploys |
| Importer | `app/services/eth_block_importer.rb`, `app/services/geth_driver.rb`, `app/models/ethscription_detector.rb`, `app/models/ethscription_transaction_builder.rb`, `app/models/eth_transaction.rb` | Schedule blocks, detect create/transfer intent, encode deposit txs, call Engine API |
| Validation | `lib/block_validator.rb`, `lib/event_decoder.rb`, `lib/storage_reader.rb`, `lib/ethscriptions_api_client.rb` | Decode L2 receipts, read contract storage, compare with reference API |
| Tooling | `script/*.rb`, `spec/`, `contracts/test/` | One-off imports, debugging, RSpec coverage, Foundry tests |

---

## 3. On-Chain Design Deep Dive

### 3.1 Contracts

- **Ethscriptions.sol**: ERC-721 implementation tailored for null ownership, SSTORE2 content storage, protocol-level events, token manager & prover hooks.
- **ERC721EthscriptionsUpgradeable.sol**: Minimal ERC-721 core that supports address(0) ownership, removes approvals, and exposes `_update` for better control.
- **TokenManager.sol**: Receives callbacks (`handleTokenOperation`, `handleTokenTransfer`) for token protocols. Logic still needs Ruby-side parameter parsing.
- **EthscriptionsProver.sol**: Emits proofs for downstream verification.
- **Predeploy Addresses**: Located in `contracts/genesis-allocs.json` (Ethscriptions contract at `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`).

### 3.2 Identity & Storage

| Concept | Implementation |
|---------|----------------|
| Token identity | `tokenId = uint256(bytes32(transactionHash))` |
| Reverse lookup | `mapping(uint256 => bytes32) tokenIdToTransactionHash` |
| Metadata | `mapping(bytes32 => Ethscription)` with creator, owners, mimetype, ESIP flags, timestamps, L1/L2 provenance |
| Content storage | `contentBySha[bytes32]` → `address[]` of SSTORE2 pointers |

### 3.3 SSTORE2 Strategy & Gas

- **Chunking**: `_storeContent` slices calldata into ≤24 575-byte pieces (max minus one byte for `STOP`). Each chunk is deployed via `SSTORE2.write` and pointer stored.
- **Deduplication**: SHA-256 computed on the *decompressed* content. Without ESIP-6 flag, duplicate SHA reverts with `DuplicateContent`.
- **Retrieval**: `_getContentDataURI` concatenates pointer code using `extcodecopy`. If `isCompressed`, decompress with `LibZip.flzDecompress` before returning string.

Indicative gas costs:

| Payload Size | # Chunks | `createEthscription` Gas | Notes |
|--------------|---------|--------------------------|-------|
| 2 KB | 1 | ~2.3M | dominated by pointer deployment |
| 24 KB | 1 | ~6.8M | single chunk |
| 96 KB | 4 | ~20M | roughly linear with chunk count |
| 192 KB | 8 | ~38M | close to block gas limit |

### 3.4 Events & Hooks

| Event | Purpose |
|-------|---------|
| `EthscriptionCreated` | Canonical mint event (tx hash, creator, initial owner, SHA, number, pointer count) |
| `EthscriptionTransferred` | Protocol-level transfer semantics (from=initiator, even on mint) |
| `Transfer` | Standard ERC-721 compliance |

Hooks executed on state changes:
- `tokenManager.handleTokenOperation` on create.
- `tokenManager.handleTokenTransfer` on every transfer (including burns to address(0)).
- `prover.proveEthscriptionData` after `_update`.

### 3.5 Errors & Parameter Layouts

| Error | Trigger |
|-------|---------|
| `DuplicateContent()` | Duplicate SHA without ESIP-6 |
| `InvalidCreator()` | `msg.sender == address(0)` |
| `EmptyContentUri()` | Zero-length content |
| `EthscriptionAlreadyExists()` | Reused tx hash |
| `EthscriptionDoesNotExist()` | Transfer/query preceding mint |

Token parameter structs:

```
struct TokenParams {
  string op;
  string protocol;
  string tick;
  uint256 max;
  uint256 lim;
  uint256 amt;
}

struct CreateEthscriptionParams {
  bytes32 transactionHash;
  address initialOwner;
  bytes contentUri;
  string mimetype;
  string mediaType;
  string mimeSubtype;
  bool esip6;
  bool isCompressed;
  TokenParams tokenParams;
}
```

`EthscriptionTransactionBuilder` ABI-encodes these tuples when constructing deposit transactions.

---

## 4. From Zero to Running: Setup & Operations

### 4.1 Prerequisites

| Tool | Notes |
|------|-------|
| Ruby 3.2.2 | `rvm install 3.2.2` (or rbenv). Use `--with-openssl-dir=$(brew --prefix openssl@1.1)` on macOS if necessary. |
| Bundler & Gems | `bundle install` in repo. |
| PostgreSQL | Required for API reads. |
| Redis/Memcached | Rails caching (`dalli`). |
| Node.js (optional) | For helper scripts (`script/verify_with_l1block.js`). |
| Foundry | `curl -L https://foundry.paradigm.xyz | bash`. |
| op-geth | Optimism fork with Engine API (`make geth`). |
| L1 RPC | Archive-capable endpoint recommended (Alchemy/Infura/etc.). |

Initial setup:
```bash
git clone https://github.com/ethscriptions-protocol/ethscriptions-indexer
cd ethscriptions-indexer
bundle install
cp .sample.env .env
cp .sample.env.development .env.development
cp .sample.env.test .env.test
rails db:create
rails db:migrate
```

### 4.2 Environment Variables

Example `.env` configuration:
```bash
L1_NETWORK=mainnet
L1_GENESIS_BLOCK=17478951
L1_RPC_URL=https://mainnet.example
GETH_RPC_URL=http://127.0.0.1:8551
NON_AUTH_GETH_RPC_URL=http://127.0.0.1:8545
JWT_SECRET=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BLOCK_IMPORT_BATCH_SIZE=2
IMPORT_INTERVAL=6
VALIDATE_IMPORT=false
VALIDATE_STRICT=false
ETHSCRIPTIONS_API_BASE_URL=http://127.0.0.1:3000
LOCAL_GETH_DIR=/path/to/op-geth
GETH_DISCOVERY_PORT=30303
```
`JWT_SECRET` must be a 32-byte hex string (no `0x`).

### 4.3 Generate Genesis & Boot op-geth

1. **Produce allocations**
   ```bash
   cd contracts
   forge script script/L2Genesis.s.sol:L2Genesis --sig "run()" --fork-url $L1_RPC_URL
   ```
   Outputs `genesis-allocs.json` and `genesis/ethscriptions-${L1_NETWORK}.json`.

2. **Initialize op-geth**
   ```bash
   cd $LOCAL_GETH_DIR
   make geth
   ./build/bin/geth init \
     --cache.preimages \
     --state.scheme=hash \
     --datadir ./datadir \
     /path/to/ethscriptions-indexer/contracts/genesis/ethscriptions-${L1_NETWORK}.json
   ```

3. **Start the node**
   ```bash
   ./build/bin/geth \
     --datadir ./datadir \
     --http --http.api "eth,net,web3,debug" --http.vhosts "*" \
     --http.port 8545 --authrpc.port 8551 --authrpc.jwtsecret /tmp/jwtsecret \
     --rollup.enabletxpooladmission=false --rollup.disabletxpoolgossip \
     --nodiscover --maxpeers 0 --syncmode full --gcmode archive \
     --override.canyon 0
   ```
   Put your JWT secret hex in `/tmp/jwtsecret` (or point to it with `--authrpc.jwtsecret`).

**Smoke test**: `curl http://127.0.0.1:8545 -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'` should return `0xeeee` (default chain ID).

### 4.4 Run the Importer

```bash
source .env
./script/run_importer.sh --validate
```

Expected behavior:
- Script confirms required env vars and prints configuration.
- Clockwork loop (`config/derive_ethscriptions_blocks.rb`) schedules imports.
- For each cycle: fetch L1 blocks, build deposits, propose L2 blocks, optionally validate.
- Logs show throughput, gas metrics, validation summary, e.g. `✅ Block 17480871 validated successfully: 1 creations, 0 transfers, 2 storage checks`.

Use `--strict` to halt on validation errors or warnings.

### 4.5 Start the Rails API (Optional)

```bash
rails s -p 4000
```

Helpful endpoints:
- `http://localhost:4000/ethscriptions/0/data`
- `http://localhost:4000/blocks/<l1_block_number>`

---

## 5. Importer & Data Flow Details

### 5.1 Step-by-Step Pipeline

1. **Scheduling**: `EthBlockImporter` tracks recent L2 blocks (head/safe/finalized) and decides which L1 numbers to process.
2. **Fetching**: Blocks and receipts fetched concurrently via `Concurrent::Promise`.
3. **Normalization**: `EthTransaction.from_rpc_result` produces typed structs with status, input, logs.
4. **Detection**: `EthscriptionDetector` identifies creates (Data URI inputs or ESIP-3 events) and transfers (input hashes, ESIP-1/2 events), normalizes addresses, deduplicates create operations per tx.
5. **Deposit construction**: `EthscriptionTransactionBuilder` ABI-encodes operations and wraps them as deposit txs (type `0x7d`). System L1 attributes tx is prepended.
6. **Block proposal**: `GethDriver.propose_block` handles filler blocks, Engine API calls, and cache updates for head/safe/finalized.
7. **Validation (optional)**: `BlockValidator` groups L2 blocks per L1 block, fetches expected data from API, decodes events, checks storage, and logs results via `ValidationResult`.

### 5.2 SysConfig Feature Flags

Ensure ESIP enablement thresholds match protocol history:
- ESIP-1 – Event-based transfers.
- ESIP-2 – Previous-owner transfers.
- ESIP-3 – Event-based creates.
- ESIP-5 – Multi-transfer payloads.
- ESIP-6 – Duplicate content reuse.
- ESIP-7 – Gzip compression support.

### 5.3 Token Operations (Future Work)

Solidity hooks expect `TokenParams`. Importer currently sends empty values. TODO: parse protocol metadata from input/event payloads and populate these fields so `TokenManager` can enforce deploy/mint rules.

---

## 6. Validation Philosophy & Workflow

### 6.1 Guiding Principle

> **Detect intent in Ruby; validate rules on-chain.**

Ruby should:
- Recognize Ethscription attempts (valid Data URI, 32-byte hashes, protocol events).
- Ensure parameters are structurally sound (non-nil addresses, proper lengths).
- Forward all protocol-relevant attempts, even if contract revert is expected.

Ruby should **not**:
- Query contract state to short-circuit duplicates or ownership checks.
- Enforce previous-owner or token protocol rules.

### 6.2 Validator Responsibilities

`BlockValidator.validate_l1_block`:
1. Fetches expected creations/transfers from `EthscriptionsApiClient` (typically the local Rails API).
2. Decodes L2 receipts via `EventDecoder` (`EthscriptionCreated`, `EthscriptionTransferred`, ERC-721 `Transfer`).
3. Compares expected vs. actual events (counts, creator/owner addresses). Uses protocol-level transfer events to avoid ERC-721 mint `from=0x0` quirks.
4. Reads contract storage via `StorageReader` with EIP-1898 block hash tags to confirm metadata and final owner.
5. Aggregates stats/errors/warnings in `ValidationResult`. Remove any `binding.irb` calls before running in production.

### 6.3 Typical Validation Messages

- `Missing creation event: 0x...` – contract never emitted event for expected tx.
- `Ownership mismatch for token 0x...` – storage owner differs from expected `to` address.
- `Token 0x... not found in storage` – deposit call reverted or create skipped.

---

## 7. Configuration & Frequently Used Commands

### 7.1 Environment Variable Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `L1_NETWORK` | Network name for genesis helper | — |
| `L1_GENESIS_BLOCK` | Starting L1 block number | — |
| `L1_RPC_URL` | L1 JSON-RPC endpoint | — |
| `GETH_RPC_URL` | Engine API URL (auth required) | — |
| `NON_AUTH_GETH_RPC_URL` | Public HTTP RPC URL | — |
| `JWT_SECRET` | Engine API JWT secret (hex) | — |
| `BLOCK_IMPORT_BATCH_SIZE` | L1 blocks per import batch | `2` |
| `IMPORT_INTERVAL` | Seconds between importer iterations | `6` |
| `VALIDATE_IMPORT` | Enable validator | `false` |
| `VALIDATE_STRICT` | Halt on validation failure/warning | `false` |
| `VALIDATION_THREADS` | Thread count for validator | `50` |
| `ETHSCRIPTIONS_API_BASE_URL` | API used as validation reference | `http://127.0.0.1:3000` |
| `LOCAL_GETH_DIR` | Path for genesis helper | — |
| `GETH_DISCOVERY_PORT` | Port used by helper scripts | — |

### 7.2 Command Cheat Sheet

```bash
# Start Rails API
rails s -p 4000

# Run importer (no validation)
./script/run_importer.sh

# Run importer with validation
./script/run_importer.sh --validate

# Import a single L1 block
ruby script/import_single_block.rb 17480873

# Import a batch of blocks
ruby script/import_blocks_batch.rb 17480870 17480880

# Debug detection for a block
ruby script/debug_single_block.rb 17480873

# Validate a specific L1 block
ruby script/test_validation.rb 17480873

# Foundry tests
cd contracts && forge test -vvv --gas-report

# Generate genesis via Rails helper
bundle exec rails runner 'GenesisGenerator.new.run!'
```

---

## 8. Troubleshooting & FAQ

| Symptom | Diagnosis / Fix |
|---------|-----------------|
| `Fork choice update failed` | Check op-geth logs; ensure genesis matches deployed contracts, JWT secret is correct, system clock synced. |
| Importer prints “Block not ready” repeatedly | Normal when caught up. Confirm L1 RPC is progressing. |
| Validation halts inside debugger | Remove `binding.irb` from `BlockValidator` / `ValidationResult`. |
| `Could not verify owner` warnings | `StorageReader.get_owner` returned nil (burned tokens). Confirm the contract’s `ownerOf(bytes32)` overload works; rerun Foundry tests. |
| High create gas causing payload rejection | Large payloads require many SSTORE2 chunks. Consider off-chain chunking or smaller content. |
| Geth won’t start | Ensure ports 8545/8551/30303 free, genesis path correct, JWT secret file exists, `make geth` succeeded. |
| No Ethscriptions detected | Verify the L1 block actually contains protocol txs; check SysConfig ESIP thresholds; use `script/debug_creation.rb`. |
| Unexpected duplicate errors | Ensure importer sets `esip6` properly when duplicate content is expected (ESIP-6). |

---

## 9. Testing Strategy

### 9.1 Ruby / Rails

- `bundle exec rspec` – detector specs (`spec/models/ethscription_detector_spec.rb`), importer integration, API coverage.
- `bundle exec rake test` – additional Minitest coverage (`test/models/ethscription_detector_test.rb`).
- Add regression tests when modifying detection logic, SysConfig, or importer behavior.

### 9.2 Solidity (Foundry)

- `forge test -vvv --gas-report` under `contracts/`.
- Key suites: `EthscriptionsBurn.t.sol`, `EthscriptionsMultiTransfer.t.sol`, `EthscriptionsCompression.t.sol`, `EthscriptionsNullOwnership.t.sol`.

### 9.3 Integration Smoke Tests

1. Run importer over a known active block range.
2. Inspect `Ethscriptions` contract storage via `StorageReader` or `cast call`.
3. Compare with Rails API responses.
4. Optionally run `script/verify_with_l1block.js` to map L1→L2 blocks.

---

## 10. Example Walkthroughs

### 10.1 Successful Create

1. L1 tx input carries `data:application/json,...` (optionally gzip via ESIP-7).
2. Detector records a `:create` operation, flags `esip6`/`esip7_compressed` as appropriate.
3. Builder encodes `createEthscription` deposit with spoofed `from` address = L1 sender.
4. GethDriver proposes block; Engine API accepts payload.
5. Contract stores SSTORE2 chunks, emits `EthscriptionCreated`, `Transfer` (0x0→owner), and `EthscriptionTransferred` (creator→owner).
6. Validator confirms creation and storage metadata (creator, initial owner, L1 block number).

### 10.2 Transfer via ESIP-1 Event

1. L1 tx interacts with legacy contract that emits `ethscriptions_protocol_TransferEthscription` event.
2. Detector identifies event (signature + topics) and enqueues `:transfer` with `from = contract address`, `to = decoded topic`.
3. Deposit executes `transferEthscription(to, txHash)` with `msg.sender` spoofed as contract.
4. Contract checks ownership, updates state, emits both protocol and ERC-721 transfer events.
5. Validator uses protocol event semantics to verify expected `from`/`to`.

### 10.3 Duplicate Rejection (ESIP-6 Disabled)

1. Detector sees valid Data URI without ESIP-6 flag.
2. Builder forwards create attempt (no on-chain preflight).
3. Contract computes SHA, detects existing content, reverts with `DuplicateContent()`.
4. Deposit tx fails; validator later flags missing creation so you can investigate.

---

## 11. Current Status & Roadmap

| Area | State | Next Steps |
|------|-------|------------|
| Create path | End-to-end working | Improve compression detection, populate token params |
| Transfers (ESIP-1/2/5) | Detection + contracts wired | Harden previous-owner path, add negative tests |
| Token protocols | Solidity hooks ready | Parse protocol metadata, enforce via `TokenManager` |
| Validation tooling | Functional (debug hooks need cleanup) | Remove `binding.irb`, surface warnings cleanly |
| Documentation | Consolidated in this README | Keep updated as code evolves |
| Performance | Defaults: batch=2, interval=6s | Benchmark larger batches, optimize caching, explore async proposals |
| Developer ergonomics | Scripts cover main flows | Add `make` targets / binstubs for common tasks |

---

## 12. Glossary

| Term | Meaning |
|------|---------|
| Ethscription | Data URI–encoded artifact created via L1 Ethereum tx |
| ESIP | Ethscriptions Improvement Proposal |
| Deposit transaction | Optimism mechanism for injecting L1 intent into L2 |
| Engine API | Execution-layer API (`engine_forkchoiceUpdated`, `engine_newPayload`) |
| SSTORE2 | Library storing bytes as contract code |
| L1 Attributes Tx | System transaction with L1 metadata |
| Head/Safe/Finalized | L2 block designations mirroring OP Stack |

---

## 13. Keep This README Fresh

- Update sections whenever importer logic, contract behavior, or setup steps change.
- Link PRs to relevant sections when you touch the pipeline.
- New scripts or tools should be documented in [Section 7](#7-configuration--frequently-used-commands) or [Section 9](#9-testing-strategy).

Happy hacking—and when in doubt, run the importer against a known block, inspect events with `cast`, and read contract storage via `StorageReader` to verify behavior.
