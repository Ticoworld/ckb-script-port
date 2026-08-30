# D2-RP1 — REAL-UPSTREAM REPROOF PLAN

Status: design only. No RP2 implementation, PB1 repair, production package schema, or Pocket Node integration is included here.

## 1. RP1 verdict

### Decisive reproof is feasible, but the experiment should proceed with a small upstream seam

The current `ckb-light-client` architecture exposes enough real behavior to make a decisive experiment possible:

* the storage abstraction has genuine RocksDB and SQLite implementations;
* Script registration is represented as a packed Script plus a Script role;
* filtering, matched-block retrieval, transaction/cell indexing, progress updates, chain proofs, and rollback are implemented in the real protocol paths;
* the existing upstream test utilities can construct valid CKB dev-chain blocks and proof material.

The architecture does not, however, expose a clean production handoff boundary. A raw database copy or raw `FILTER_SCRIPTS` cursor would couple the experiment to internal keys and would not establish coverage evidence. The first reproof can use test-only tracing and a temporary typed test seam. A positive result intended to support D2 as infrastructure should use a small upstream seam that atomically imports typed Script-derived state plus typed Script progress while validating the destination's independently established chain facts.

Therefore this plan recommends:

**PROCEED TO RP2 WITH UPSTREAM SEAM**

The seam is not a license to redesign the light client. It should expose the smallest existing boundary needed to make the import atomic, chain-bound, observable, and rollback-compatible. If the reproof shows that the cursor cannot safely represent imported coverage or that imported rows cannot participate in rollback, the result is **D2 NEEDS REFORMULATION** or **KILL D2 CORE**, not a larger importer.

This plan deliberately does not treat the previous `PROVEN PRE-BUILD INFRASTRUCTURE CANDIDATE` label as evidence. The source archaeology audit classified the prior work as **AUDIT C — MATERIAL REPROOF REQUIRED**. That remains the starting point.

## 2. Pinned system under test

### Selected revision

RP2 should target this exact upstream revision:

* Repository: `nervosnetwork/ckb-light-client`
* Branch observed: `develop`
* Revision: `12e29522ab7e078ada704d4ac04cbc0498009b7b`
* `light-client-lib` version: `0.5.5`
* Cargo lockfile: the lockfile committed at that revision, used with `cargo ... --locked`
* Rust toolchain: the repository's pinned toolchain, if present; otherwise record the exact toolchain selected for the run

The live remote check made for this plan reports the same `develop` HEAD. The exact revision, rather than the branch name, must be recorded in every RP2 result.

Current release context:

* stable release: `v0.5.4`, revision `778590aa3ad7f71ee80b2d4c54af02c42e2dfa25`;
* prerelease: `v0.5.5-rc1`, revision `e4f62a9c046ac4824a685d8e3ea9623559aaabcc`;
* selected RP1 target: `12e29522ab7e078ada704d4ac04cbc0498009b7b`.

The selected revision is appropriate because the current question explicitly concerns the unified storage abstraction, SQLite support, current Script filtering, and current RFC44/RFC45 proof behavior. Stable `v0.5.4` is a useful compatibility control, but it is not the primary target. `v0.5.5-rc1` is a release checkpoint, but `develop` is the live implementation whose exact behavior must be re-proven. RP2 should run the same fixture against the release or prerelease only as a follow-up compatibility comparison, never as a silent substitution for the pinned target.

Relevant upstream sources at the selected revision:

* [storage module](https://github.com/nervosnetwork/ckb-light-client/tree/12e29522ab7e078ada704d4ac04cbc0498009b7b/light-client-lib/src/storage)
* [storage trait](https://github.com/nervosnetwork/ckb-light-client/blob/12e29522ab7e078ada704d4ac04cbc0498009b7b/light-client-lib/src/storage/storage_trait.rs)
* [light-client protocol](https://github.com/nervosnetwork/ckb-light-client/blob/12e29522ab7e078ada704d4ac04cbc0498009b7b/light-client-lib/src/protocols/light_client/mod.rs)
* [block-filter processing](https://github.com/nervosnetwork/ckb-light-client/blob/12e29522ab7e078ada704d4ac04cbc0498009b7b/light-client-lib/src/protocols/filter/components/block_filters_process.rs)
* [release history](https://github.com/nervosnetwork/ckb-light-client/releases)

### Dependency facts that must be frozen

The selected lockfile currently resolves the core CKB crates at `1.0.0`, including `ckb-types`, `ckb-chain-spec`, `ckb-verification`, `ckb-network`, `ckb-resource`, `ckb-jsonrpc-types`, `ckb-hash`, and related crates. It uses:

* `ckb-rocksdb` `0.21.1` for the native backend;
* `rusqlite` `0.32` with the bundled SQLite feature for the SQLite backend;
* `ckb-merkle-mountain-range` `0.5.2` in the locked dependency graph;
* `light-client-lib` `0.5.5`.

RP2 must preserve the full lockfile rather than recording only these highlights. It must also record the two feature builds separately because the current `Storage` alias selects one native backend at compile time. A single unqualified binary must not be presented as a true RocksDB/SQLite cross-backend test.

### Backend build constraint

`light-client-lib/src/storage/db/mod.rs` selects the native RocksDB implementation by default and the SQLite implementation when the `sqlite` feature is enabled. RP2 therefore needs separate processes and feature-specific builds for the two backends. A Rust generic parameter alone is not enough to claim that one running client exercised both storage implementations.

## 3. Normal upstream Script-sync path

The RP2 driver must exercise this path through actual upstream protocol handlers. It may provide deterministic peer messages through a test network context, but it must not replace the path with a local loop that calls `filter_block`, `update_block_number`, or a database writer directly.

### Registration

The public service path is `LightClientService::set_scripts` in `light-client-lib/src/service/impls.rs`. It passes Script registrations to `StorageWithChainData::update_filter_scripts`, which delegates to `LightClientStorage::update_filter_scripts` in `storage/storage_trait.rs`.

The registration key is the packed Script bytes followed by a role byte. The role is the upstream `ScriptType` distinction, principally lock versus type. A registration also carries a block cursor. Registration updates the per-Script cursor, clears matched-block state, and recomputes `MIN_FILTERED_NUMBER` from all registered Script cursors. Genesis has special initialization behavior.

### Filter range selection

`FilterProtocol::try_send_get_block_filters` reads `get_min_filtered_block_number`, selects the next range beginning at minimum plus one, consults peer/checkpoint state, and sends a real `GetBlockFilters` request. `get_scripts_hash` selects the Script hashes whose cursor is behind the requested range. The range is therefore controlled by persistent Script progress plus runtime peer/protocol state.

### Filter acceptance and matching

The peer response is processed by `FilterProtocol` and `BlockFiltersProcess::execute` in `protocols/filter/components/block_filters_process.rs`. The process checks that the response begins at the expected persisted minimum, validates filter counts and range shape, calls the upstream filter matching code, and records matched blocks or advances Script progress when no blocks match.

The experiment must observe both the request and the accepted response. A response manually injected into a storage helper is not enough.

### Matched block retrieval

For matches, the filter protocol records matched block hashes and asks for a block proof. `LightClientProtocol` receives and verifies `SendBlocksProof` material. The proof path checks headers, MMR proof data, the current chain state, and the applicable proof/PoW conditions before requesting the matched blocks.

The scripted peer must answer the actual requests with packed upstream message types. It must not mark a block proved by writing a matched-block row or a header directly.

### Block processing and Script indexing

`SyncProtocol` receives the proved blocks, checks their relationship to the verified headers, and calls `storage.filter_block(block)` for each matched block. `filter_block` scans real transactions and updates the Script-indexed rows:

* transaction facts keyed by transaction hash;
* cell-lock and cell-type indexes keyed by packed Script;
* transaction-lock and transaction-type indexes keyed by packed Script;
* removal of spent cell references.

`filter_block` is where Script-derived query state is materially produced. RP2 must reach it through `SyncProtocol`, after the actual filter/proof path has selected the block.

After processing, `SyncProtocol` calls `update_block_number` with the processed range. That updates registered Script cursors and the global minimum. The resulting state is then exposed by `get_scripts`, `get_cells`, and `get_transactions` through `LightClientService`.

### Chain and consensus processing

`LightClientProtocol::process_last_state` validates the peer's last-state material against the consensus engine and chain roots. `commit_prove_state` handles the accepted state, chain selection, last-header history, and rollback. The proof process stores chain/header data and updates the light-client last state. These paths are separate from Script rows and must run in every client, including the import destination.

### Rollback

`LightClientStorage::rollback_to_block` iterates registered Script state, deletes Script-derived rows at or after the rollback point, rewrites each affected Script cursor, and adjusts the global minimum. `LightClientProtocol::commit_prove_state` invokes this when a new verified chain state exposes a fork. Matched-block state is also cleared as part of the reorg path.

The decisive reorg test is therefore not a call to `rollback_to_block` in isolation. It is a real new chain-state proof that causes the actual protocol to invoke rollback, followed by ordinary filter and block processing on the winning fork.

### Boundary inventory

| Area | Current upstream representation | RP2 treatment |
|---|---|---|
| Storage | `LightClientStorage`, `StorageBackend`, `BatchWriter`, backend-specific `Storage` | Use genuine RocksDB/SQLite instances; no PB1 schema |
| Script registrations | `FILTER_SCRIPTS` metadata: packed Script plus role and block cursor | Import only through a typed seam or a test-only equivalent with invariants |
| Script-derived rows | KV prefixes for cells, transactions, and transaction/script indexes | Compare through services; import only selected typed closure |
| Filter progress | per-Script cursors plus `MIN_FILTERED_NUMBER` | Observe transitions; recompute global minimum at import |
| Matched blocks | `MATCHED_BLOCKS` metadata | Never transport as authority; clear/require empty at handoff |
| Filter protocol | `FilterProtocol` and `BlockFiltersProcess` | Drive through real messages and record events |
| Proof/chain processing | `LightClientProtocol`, proof processors, consensus engine, MMR/header checks | Independently execute in every client |
| Block synchronization | `SyncProtocol` | Drive matched bodies through the real path |
| Networking | protocol context, peers, pending requests | Deterministic scripted peer; never import it |
| Runtime state | peers, in-flight requests, pending transactions, timers | Recreate; never transport |

The minimum upstream execution boundary that justifies the statement “the real client decided this historical range no longer required filtering” is:

1. the client has an independently verified chain state;
2. the client sends or accepts a real `GetBlockFilters`/`BlockFilters` exchange through `FilterProtocol`;
3. `BlockFiltersProcess::execute` accepts the range and advances the actual Script progress path, or a typed handoff seam restores an equivalent progress state with an event recorded as an import, not a filter result;
4. the next real filter request begins after the imported or normally processed range;
5. no test helper directly sets the tip or global minimum to suppress work.

## 4. State authority taxonomy

The taxonomy below is the boundary RP2 must enforce. It reflects the selected upstream representation, not a proposed final package schema.

| Category | Upstream representation | Persistent/runtime and scope | Who may establish it | Rollback | D2 treatment |
|---|---|---|---|---|---|
| C — chain/consensus authority | `GENESIS_BLOCK`, block-hash/number and header rows, `LAST_STATE`, `LAST_N_HEADERS`, checkpoints and filter-hash-chain metadata, total difficulty/peer proof state | Mostly persistent; global to the client/network; some proof authority is runtime | Destination's normal proof, header, PoW, MMR, chain-selection, and consensus paths | Yes for chain/header state through `commit_prove_state`; checkpoint/proof details follow upstream rules | Must be independently established in destination; never trusted from source payload |
| S — Script-derived view | cell-lock/type rows, transaction-lock/type rows, transaction facts needed by Script queries, spent-cell removal results | Persistent; keyed by one or more packed Scripts and their roles, with shared transaction closure | Normal filter/block processing or a validated typed handoff | Yes, if stored in the same upstream rows and associated with registered Script cursor | Candidate payload, but only selected Script closure and only after identity/chain validation |
| P — Script coverage/progress | `FILTER_SCRIPTS` entries: packed Script, role, block cursor; global `MIN_FILTERED_NUMBER` derived from them | Persistent; per Script cursor plus global aggregate | Normal filter processing, registration, or a carefully constrained handoff | Yes; rollback rewrites Script cursors and recomputes/adjusts minimum | Candidate only as typed progress bound; raw metadata copy is unsafe |
| H — shared historical fact | transaction bodies, block/header references, transaction inclusion facts, filter data/proof facts used to interpret S | Persistent in several upstream KV rows, but not semantically owned by one Script | Destination proof/block path, or source payload only when independently checked against destination chain | Chain-dependent; must be removed/rebuilt if fork invalidates it | Carry only the minimum needed for S, with hash/inclusion validation; never use it to establish C |
| R — runtime only | peers, pending requests, timers, in-flight matched blocks, network connection state, pending transaction state | Runtime; global/process state | Destination runtime | Recreated or discarded | Exclude completely |
| U — unclear/coupled | `MATCHED_BLOCKS` and checkpoint/filter-hash interactions; last-state and Script progress timing; transaction facts whose validity depends on a chain row not independently present | Mixed; some persistent metadata has protocol meaning that is not Script-local | Must be established or reconciled by upstream code | Yes, but exact coupling must be tested | Do not transport in RP2 payload unless the seam gives it an explicit non-authority interpretation |

### Details and limits

`FILTER_SCRIPTS` is Script-scoped in key identity, but `MIN_FILTERED_NUMBER` is a global aggregate. An importer that replaces all Script registrations, copies a global minimum, or clears chain metadata is crossing the C/S boundary. RP2 must preserve unrelated destination Script registrations and recompute the minimum from the destination's complete registration set.

The transaction value rows are shared historical facts in one sense and Script closure in another. They may be needed to answer a Script query, but the same transaction can be indexed under another Script or role. The test must therefore compare both the imported A view and the absence of unintended B/type indexes. It must not assume that every transaction row in a package is “owned by A”.

The current storage code does not offer a persisted per-range proof that a Script was completely covered. A cursor says where upstream believes that Script is filtered; it does not independently prove how the cursor was reached. This is the central U/P limitation.

## 5. Progress and cursor analysis

### Current semantics

`get_filter_scripts` reads `FILTER_SCRIPTS` metadata. `update_filter_scripts` supports replacing or partially changing registrations, writes a cursor per packed Script plus role, clears matched blocks, and recomputes `MIN_FILTERED_NUMBER`. `update_block_number` advances registered Script cursors to a supplied block number. `get_min_filtered_block_number` reads the global minimum. `get_scripts_hash` selects Script hashes that still need filtering for a requested end range.

The global minimum is not an independent progress ledger. It is an optimization/scheduler boundary derived from all registered Scripts. It must be recomputed in the destination after any Script registration or import.

`rollback_to_block` uses the Script cursor and Script-indexed row keys to remove state at and beyond a fork boundary. This is promising for D2, but only if imported rows and progress are written in the same upstream representation and the cursor has a well-defined relationship to those rows.

### Strategy A — transport typed Script progress

This strategy carries a typed statement equivalent to:

* exact packed Script bytes;
* exact Script role;
* source-derived coverage cursor;
* handoff block number and hash;
* chain/genesis binding that the destination validates independently;
* the Script-derived rows and shared closure associated with that cursor.

It does not carry `MIN_FILTERED_NUMBER` as authority. The destination reconstructs that value from all its registrations. It does not carry `LAST_STATE`, `LAST_N_HEADERS`, peer state, checkpoints, or matched-block progress as a source assertion.

Advantages:

* maps most closely to existing upstream rollback semantics;
* can make the next real filter request begin at cursor plus one;
* can preserve a useful handoff without replaying the already covered interval;
* can be tested against current query APIs and current rollback code.

Required conditions:

* the destination has independently verified the handoff chain fact before accepting the cursor;
* the cursor cannot exceed the destination's verified chain/proof boundary;
* exact Script and role identity is validated;
* S rows, necessary H closure, registration, and progress are imported atomically;
* imported rows participate in the same rollback keys and paths as normally derived rows;
* stale, fork-mismatched, and forged handoffs fail closed or take the explicitly defined bounded-rescan path;
* the import is not allowed to replace unrelated Scripts or global chain metadata.

Risk: a cursor is a statement of upstream progress, not a cryptographic coverage proof. This is acceptable only if D2 treats the source as the owner of its own derived view and the chain binding is independently checked. It is not acceptable as a trustless proof that an arbitrary third party scanned every interval.

### Strategy B — reconstruct progress from coverage evidence

This strategy would avoid trusting a raw cursor by carrying evidence from which the destination derives coverage. The evidence would need to identify, at minimum, the exact Script/role, every covered interval or a cryptographically committed equivalent, the authoritative filter-hash-chain context, the destination chain identity, the matching decision or sufficient filter evidence for each interval, and the relationship between each derived row and its source block.

Current upstream storage does not appear to retain that evidence. RFC44/RFC45 proof and filter structures protect chain/filter protocol data, but they are not a persisted per-Script coverage ledger. A set of current Script rows cannot prove that an unmatched historical interval was examined; absence of rows is not coverage evidence.

Making B rigorous would require a new coverage journal or proof system, not merely a different serializer. That is outside a smallest v0.1 handoff and must not be smuggled into RP2 as an invented metadata field.

### Strategy C — exclude progress and rescan a bounded interval

This strategy imports the Script-derived view but deliberately does not trust the source cursor as complete. The destination registers the exact Script at a conservative anchor and replays a defined interval through the normal filter/block path. Imported rows may be reconciled by normal `filter_block` behavior, but this must be proven for spends, replacements, shared transactions, and duplicate keys.

The anchor must be explicit. Candidates include:

* the destination's independently verified finalized/checkpoint boundary;
* the earliest block needed to validate the imported rows;
* a conservative recent window before the handoff;
* the source Script start height, which is safe but can make the feature equivalent to replay.

C is safer than a raw cursor when the chain cannot independently validate the source coverage statement. It does not prove zero historical replay. It is useful only if the bounded interval is materially smaller than full Script history and if imported rows before the interval remain safe under rollback.

### Comparison and selection

| Strategy | Current semantic fit | Main unsolved issue | RP1 decision |
|---|---|---|---|
| A: typed progress | Best fit to existing rollback and scheduler state | Cursor is not coverage proof; import API and chain binding are absent | Primary RP2 arm, with small seam and adversarial tests |
| B: coverage evidence | Strongest trust model in theory | Current storage does not contain the evidence; would require new coverage machinery | Do not implement for RP2; treat as out of scope unless A fails for safety reasons |
| C: bounded rescan | Safest fallback with current information | May replay too much and has nontrivial merge/reorg semantics | Mandatory fallback arm and diagnostic control; not a full zero-replay pass |

### Recommended progress strategy

Use **Strategy A with a typed, chain-bound, atomic seam**, and run Strategy C as a control/fallback. The RP2 acceptance result for the original proposition must require A to skip the approved historical interval through the real upstream scheduler. If only C works, report a bounded derived-view handoff, not full D2 zero-replay portability.

The seam must not accept a bare integer. It must accept a typed Script/role progress statement tied to a specific handoff block hash and validated destination chain state. The destination must derive `MIN_FILTERED_NUMBER` from its own registrations and must leave C/R state untouched.

## 6. Real CKB fixture design

### Harness choice

Use a programmatically constructed deterministic CKB dev chain based on the selected upstream test utilities, especially `MockRunningChain`, `SnapshotExt`, `get_block_filter_data`, `get_verifiable_header_by_number`, and the existing proof builders in `light-client-lib/src/tests/prelude.rs` and `src/tests/utils/chain.rs`.

This is the lightest useful harness because it provides real packed CKB structures, real transaction and header serialization, real block-filter bytes, real CKB transaction hashes, real block roots/MMR material, and the same upstream proof/checking code used by the protocol tests. It is not a mainnet or testnet demonstration. It is a deterministic dev/dummy-PoW chain, and the report must label it that way.

Do not use PB1's synthetic string hashes, fake transaction values, or a parallel storage schema. Do not claim mainnet viability from this fixture.

### Chain shape

The minimum fixture should contain a primary branch through a handoff height H around 30, followed by post-handoff blocks, plus a short competing branch. Exact heights should be constants in the fixture manifest, not implicit test assumptions. A practical shape is:

* block 0: genuine CKB genesis constructed by the upstream chain utility;
* early blocks: create A and B cells using valid CKB transactions;
* an empty/unmatched interval, long enough that a range request visibly covers multiple blocks with no A match;
* a shared transaction that consumes an A cell and a B cell and creates A and B outputs;
* an A spend and replacement/change output;
* H: old-branch handoff tip, with Script A state live and queryable;
* H+1 through H+k: new A activity for continuation;
* reorg fork point F below H, with a winning branch that changes the relevant A history;
* a winning-branch continuation after the fork.

The fork should first be 3–4 blocks below H, within the retained last-header window, because that is the smallest useful case for current rollback logic. Add one deeper-fork control beyond the retained window and require explicit upstream behavior rather than silently assuming it is supported.

### Scripts and roles

Define packed Scripts from genuine `ckb_types::packed::Script` values:

* Script A lock: code hash from a valid always-success test lock, with A-specific args;
* Script B lock: same valid code hash with B-specific args;
* Script A type: deliberately use the same raw Script bytes as Script A lock in one registration/control, but a different role;
* optional distinct type Script for a negative role test.

The exact raw Script bytes and role must be recorded. The fixture must contain at least one output where the same raw bytes occur in the type role but not the lock role, so a lock-only A handoff cannot accidentally pass by matching role-insensitive bytes.

### Transactions

Use valid CKB transactions built with the upstream packed types and chain validation rules:

1. create a live A-lock cell;
2. create B activity in separate blocks;
3. create an output using the same raw Script bytes as A's type role;
4. spend A and B inputs in one transaction and create replacement/change outputs for both, exercising shared transaction closure;
5. spend or replace the A output before H;
6. leave a final A live/dead pattern that `get_cells` and cell status queries can distinguish;
7. create new A activity after H;
8. on the winning fork, alter the A outputs/spends so imported old-branch state cannot remain valid.

Every transaction must be accepted by the upstream chain utility. Cellbase/always-success dependencies may be used only as valid fixture dependencies; they must not be confused with arbitrary fake values.

### Fixture artifacts

The fixture generator should emit packed upstream artifacts and a human-readable manifest containing:

* genesis hash and chain identity;
* block number/hash/parent/hash relationships;
* transaction hashes and inclusion locations;
* Script bytes and roles;
* expected semantic events, such as A creation/spend/replacement;
* old and winning fork identifiers;
* exact handoff height H, fork point F, and continuation heights.

The manifest is an oracle for fixture construction and query selection, not a replacement for independent baseline derivation.

## 7. Source, baseline, and import topology

Each client is a separate process with a separate database directory, separate runtime state, and separate event log. The process boundary is required to catch accidental in-memory state sharing and to make feature-specific backend builds honest.

### SOURCE

The source client is a real selected-revision client using the source backend for the matrix case. It:

1. initializes genuine genesis/chain state through upstream initialization;
2. establishes chain authority through the normal proof path;
3. registers A lock, A type, and B lock as controls;
4. processes the history through real filter responses, proof responses, matched blocks, and Script indexing;
5. stops at H;
6. exports only the proposed typed A-lock handoff material through the RP2 seam/driver.

It must not export B, A-type, global last state, checkpoints, peers, matched blocks, or runtime state.

### BASELINE DESTINATION

The baseline is a fresh client using the destination backend. It independently establishes chain authority and independently processes A's complete history through H using the same fixture and real protocol path. It must not call the source exporter or importer. Its expected query results are recorded by an independent query driver that knows the fixture's semantic Script roles but does not reuse the export selection code.

### IMPORT DESTINATION

The import destination is a third fresh client using the destination backend. It:

1. initializes its own genuine genesis state;
2. independently processes the chain proof/header path to H without registering A or importing Script progress;
3. validates that the handoff block hash and chain context agree with its own verified chain;
4. imports the typed A-lock S/H/P material atomically;
5. starts ordinary filtering from the imported progress boundary for H+1 onward;
6. undergoes the same fork/reorg proof and continuation sequence as the baseline.

The destination must not accept a package merely because its source tip number equals H. The destination must establish the relevant block hash, parent/root/proof relationships, genesis identity, and current chain-selection state through its own path.

### Shared fixture provider

A deterministic peer/provider may serve the same packed chain artifacts to each process. This is not a shared database and does not make the baseline dependent on the source. The provider must answer actual protocol requests and log the requester's ranges. It must not tell the import destination that a range has already been processed merely because another client processed it.

### Directory layout

RP2 should use a disposable run root outside both repositories, for example:

* `run/fixture/` for packed fixture artifacts;
* `run/source-rocks/`, `run/source-sqlite/`;
* `run/baseline-rocks/`, `run/baseline-sqlite/`;
* `run/import-rocks/`, `run/import-sqlite/`;
* `run/events/<client>.jsonl` for structured traces;
* `run/results/<case>.json` for semantic comparisons.

Reset must delete only a validated run root owned by RP2. No build directory, cache, or source repository path may be used as a database directory.

## 8. True cross-backend matrix

At minimum run:

| Case | Source | Baseline destination | Import destination | Purpose |
|---|---|---|---|---|
| 1 | real RocksDB build/storage | fresh real SQLite | fresh real SQLite | RocksDB-derived view into SQLite |
| 2 | real SQLite build/storage | fresh real RocksDB | fresh real RocksDB | SQLite-derived view into RocksDB |

Add same-backend controls:

| Control | Source | Destination | Purpose |
|---|---|---|---|
| 3 | RocksDB | RocksDB | distinguish cross-backend errors from handoff errors |
| 4 | SQLite | SQLite | distinguish cross-backend errors from handoff errors |

For every case the baseline and import destination must use separate databases and separate processes, even when they use the same backend. Backend equality is not process equality.

The databases must be opened through the selected upstream `Storage::new` implementation. A directory containing PB1-owned tables or rows is not a valid test. The SQLite database must be the upstream `kv_store` implementation, and the RocksDB directory must be opened by upstream `ckb-rocksdb` code.

## 9. Replay-avoidance instrumentation

### Required event stream

Add a test-only structured event sink or equivalent protocol-context recorder to the pinned upstream worktree. The sink must emit, with client ID, backend, process run ID, and monotonic sequence:

* `chain_authority_accepted`: genesis, handoff block number/hash, verified proof/state identifiers;
* `get_block_filters_requested`: start, count, Script hashes/roles if visible;
* `block_filters_received`: start, count, source peer;
* `block_filters_accepted`: start, count, match count;
* `block_filters_rejected_or_ignored`: reason and range;
* `matched_blocks_requested` and `matched_blocks_received`;
* `filter_block_entered`: block number/hash and matched transaction count;
* `script_progress_before` and `script_progress_after`;
* `min_filtered_before` and `min_filtered_after`;
* `handoff_validated` and `handoff_committed`;
* `rollback_started` and `rollback_completed` with fork boundary;
* `destination_tip_changed` through the real proof path.

At minimum, request events can be captured by parsing the real messages sent through `MockNetworkContext`; accepted-range and storage transitions need a test-only hook at `BlockFiltersProcess`, `filter_block`, and the progress writers. The hook must not alter decisions.

### Truthful classification of historical work

RP2 must report separate counters for:

1. historical filter ranges requested from the peer;
2. historical filter responses accepted by `BlockFiltersProcess`;
3. historical blocks with no Script match;
4. historical matched blocks requested/downloaded;
5. historical blocks for which `filter_block` actually ran;
6. rows that existed after import without a corresponding post-import filter invocation;
7. progress transitions caused by normal filtering versus import.

The decisive observation is not “the destination contains rows” and not “13/13 were skipped”. It is a range transition such as:

* baseline: requested and accepted filter ranges X..H, with the expected `filter_block` calls;
* imported destination: independently accepted chain authority to H, atomically imported A state/progress, made no request or accepted processing for X..H, and first requested H+1;
* imported destination: processed H+1 onward through the normal path.

If the imported process has a tip equal to H because a test wrote the tip or supplied a fake header, the run fails the authority test even if its replay counter is zero. If a range was requested but had no match, it is not replay avoidance. If a row merely already existed, it is not evidence that filtering was skipped.

### Instrumentation constraints

The event log must make it impossible for an importer to hide direct calls to `update_min_filtered_block_number`, `update_block_number`, or raw metadata writes. Such calls may be used inside the approved seam, but they must be labeled as import transitions and checked against the seam's invariants. Any unlabelled progress write in the import destination is a test failure.

## 10. Semantic equivalence checks

Raw KV equality is secondary. The primary comparison is the behavior exposed by the real service/query surface.

### Before handoff

At H compare independently derived SOURCE and BASELINE results for:

* `get_cells` for A lock, with exact packed Script and role, ordering, pagination, outpoints, outputs, data, block number, and live/dead behavior;
* `get_transactions` for A lock, including transaction hashes, grouped/ungrouped results, input/output relationships, and inclusion metadata;
* `get_scripts` and per-Script progress;
* `get_transaction`/header association for every transaction needed by the A query;
* cell-provider status for known spent and live A outpoints;
* negative queries for B lock and A type.

The baseline result must be derived by an independent client run, not by applying the exporter to SOURCE and calling that output expected.

### Immediately after handoff

Compare BASELINE and IMPORT DESTINATION for A queries and negative B/A-type queries. Also compare the authority fingerprints separately. The imported destination may have a different physical KV layout, but it must return equivalent externally observable Script semantics.

### After continuation

Feed post-H filter data, proofs, and blocks through the normal path. Compare:

* new A cells and transactions;
* spent-cell consequences;
* updated Script progress;
* requested ranges and normal matching behavior;
* no accidental B/type state;
* chain/header query behavior.

### After reorg

Repeat all queries after rollback and winning-branch continuation. The imported destination must converge to a fresh baseline that derived the winning branch itself. If a low-level digest is recorded, it is only a diagnostic secondary result, and it must be computed by an independently implemented canonical comparison driver, not by serializing with the importer and comparing that same serialization.

Shared transactions require explicit closure checks. The same transaction may have A and B outputs or may consume both A and B. The test must prove that A queries include the correct transaction facts without causing B indexes to appear in an A-only handoff.

## 11. Consensus-separation tests

The destination must establish these facts independently before accepting Strategy A progress:

* expected genesis identity;
* destination-verified handoff block number and exact block hash;
* parent and header/root relationships required by the current proof path;
* proof/MMR/PoW and chain-selection acceptance through `LightClientProtocol`;
* the destination's current last-state/header-window condition;
* a verified destination tip that is not merely a copied source number.

The package/import path must be unable to change `GENESIS_BLOCK`, `LAST_STATE`, `LAST_N_HEADERS`, checkpoints, filter-hash-chain authority, peer proof state, matched-block authority, or network runtime state.

Run at least these deliberately hostile cases:

1. same handoff number, wrong block hash;
2. wrong genesis with otherwise convincing Script rows;
3. source package derived on a losing fork while the destination has verified the winning fork;
4. cursor greater than the destination's verified tip;
5. source tip newer than destination verified tip;
6. forged or malformed transaction/header closure;
7. wrong packed Script bytes;
8. correct raw Script bytes but wrong role;
9. altered metadata that claims source chain authority or a trusted checkpoint.

Expected behavior is rejection with no partial Script/progress state, or the explicitly documented Strategy C bounded-reconciliation path. It is never acceptable to accept a cursor solely because a number matches, or to advance the destination chain tip from package metadata.

Record before/after fingerprints for C state. A successful ordinary import must show that only the approved S/H/P rows changed; a failed import must show that no durable partial state remains.

## 12. Reorg test

### Scenario

1. SOURCE, BASELINE, and IMPORT DESTINATION independently establish the old branch through H.
2. SOURCE and BASELINE normally derive A state through H. IMPORT DESTINATION accepts the typed A handoff at H.
3. The producer fixture rolls back to F, three or four blocks below H, and mines a competing branch with different A spend/replacement behavior.
4. Each client receives the winning branch's real last-state/proof material through `LightClientProtocol`.
5. The protocol, not the test driver, must invoke the current rollback path.
6. The winning branch's filter responses, proofs, and matched blocks are then delivered through normal filter and synchronizer paths.
7. Queries and progress are compared with a fresh baseline derived on the winning branch.

### Required observations

* imported S rows at and after the fork are deleted or reconciled by ordinary rollback;
* the imported P cursor is rolled back with those rows;
* `MIN_FILTERED_NUMBER` is adjusted consistently;
* stale old-branch A cells/transactions are not returned as live;
* winning-branch A state appears after normal continuation;
* matched-block and in-flight state does not leak from the old branch;
* C state converges according to upstream chain-selection rules;
* import destination and independent baseline agree at query level.

Run a deeper-fork control beyond the retained header window. If current upstream rejects it or handles it only through a defined checkpoint rule, record that result. Do not turn a limitation into a silent pass by replacing the proof with a direct database rollback.

If imported rows cannot be identified and removed through the same rollback path as normally derived rows, the original D2 proposition fails.

## 13. Destination-state matrix

RP1 should use a conservative first import contract. It must not invent merge semantics simply to make every matrix cell pass.

| Destination condition | Required first RP2 behavior | Reason |
|---|---|---|
| Fresh destination, correct chain, exact Script/role | Accept | Primary handoff case |
| Identical repeated import | Idempotent accept with no semantic change | Required for safe retries |
| Pre-existing unrelated Script state | Merge A without deleting/replacing unrelated registrations or rows; recompute global minimum | Proves Script selectivity and global-min safety |
| Pre-existing same Script older than package | Reject in the first contract unless the seam proves monotonic replacement/reconciliation; no downgrade or silent merge | Snapshot merge semantics are not currently defined |
| Pre-existing same Script equal to package | Idempotent accept if all chain/identity facts match | Safe retry/control |
| Pre-existing same Script newer than package | Reject as stale, leaving newer state intact | Prevents rollback by stale source |
| Conflicting rows for same Script/key | Reject unless exact value identity is proven; no overwrite | Conflict policy must be fail-closed |
| Different chain/genesis | Reject with no state change | Consensus separation |
| Correct bytes, wrong Script role | Reject | Role is part of identity |
| Wrong packed Script | Reject | Exact identity |
| Partial previous import | Recover only if one atomic transaction/journal makes the state detectable; otherwise reject and leave no partial state | Crash safety |

The older/newer and conflict cases may later support a deliberate bounded reconciliation mode, but RP1 must not call that “merge” without observing query, progress, and rollback semantics. Fresh-only acceptance is an acceptable diagnostic phase; a production D2 claim needs the matrix behavior documented and tested.

## 14. Atomicity and crash boundary

### Lifecycle precondition

The first implementation should require the destination light-client service, filter scheduler, and network workers to be stopped. Importing into a live client risks races with `FILTER_SCRIPTS`, `MIN_FILTERED_NUMBER`, matched blocks, and query readers. A production seam may later make this a controlled offline operation, but RP2 must test the conservative boundary explicitly.

Pocket Node-style initialization currently constructs storage and network state early, so this lifecycle constraint matters to future consumers.

### Backend transactions

The native RocksDB backend uses an upstream batch writer backed by a RocksDB write batch and commits it with the database. The SQLite backend uses an upstream SQLite transaction and `INSERT OR REPLACE`/delete operations in its batch. Both can transactionally cover rows in their own KV database.

The required atomic unit is larger than “write the Script rows”: it must cover, in one backend transaction:

* exact Script identity registration;
* selected S rows;
* validated H closure;
* typed P cursor;
* removal of stale matched-block state relevant to the handoff;
* recomputation/write of `MIN_FILTERED_NUMBER`;
* an import completion marker or equivalent recoverable state if the package staging protocol needs one.

It must not include or overwrite C state merely to obtain atomicity.

### Failure points that RP2 must eventually inject

* process death before package validation: database unchanged;
* process death after validation but before transaction start: database unchanged;
* process death during backend commit: reopen must show either the old complete state or the new complete state;
* failure after rows but before progress: impossible within the approved transaction, or detectable and rejected/recovered;
* failure after progress but before completion marker: startup must detect the transaction/journal state and finish or roll back deterministically;
* duplicate retry after a committed import: idempotent;
* package file truncation or replacement during staging: rejected without database mutation.

Use backend-specific failpoints/test-only process termination. Do not infer crash safety from a happy-path `commit` return value.

If rows and progress cannot be changed atomically through current APIs, this is a serious kill risk and likely an upstream seam requirement. A package filesystem rename is not a substitute for a database transaction.

## 15. Likely upstream patch requirement

### Assessment: SMALL UPSTREAM SEAM, with TEST-ONLY INSTRUMENTATION

The first real behavioral proof can be built using test-only instrumentation and existing protocol test contexts. The selected upstream tree already exposes low-level `StorageBackend`, `BatchWriter`, and storage keys, so a temporary test harness could technically write rows. That would demonstrate behavior but would be tightly coupled to private/internal layout and would not make the positive result a durable D2 integration boundary.

A sound RP2 should therefore add, in a temporary pinned upstream branch or an explicitly reviewed test seam, the smallest typed operations needed for:

1. exporting the exact Script/role-derived view and its validated shared closure;
2. importing that view against an independently verified destination handoff block;
3. atomically updating S/P state and recomputing global progress without touching C/R state;
4. reporting a typed import result and progress transition;
5. exposing test-only observer callbacks/events around actual filter requests, accepted ranges, `filter_block`, progress updates, and rollback.

The seam should use current `LightClientStorage`/`BatchWriter` transaction capabilities rather than introduce another database schema. It should not expose a final public package format in RP2.

Current evidence does not yet require a material upstream redesign. Existing rollback and per-Script rows may be sufficient if the typed seam establishes the right invariants. If the reorg test shows that imported rows cannot be safely rolled back, or if current proof state cannot establish the handoff chain without importing authority, the classification changes to **MATERIAL UPSTREAM DESIGN CHANGE** or D2 reformulation.

The old “UPSTREAM PATCH REQUIRED: no” statement is therefore not accepted. The honest current status is: no production patch is needed to run a narrow exploratory trace, but a small upstream seam is likely required for a credible positive infrastructure result.

## 16. Pocket implication

The immediate RP1 experiment does not touch Pocket Node. If RP2 succeeds, the future consumer boundary is constrained:

* restore must occur while the light-client database is closed or through a controlled offline restore API, before filtering/network workers consume it;
* a Rust seam and JNI surface will be required; the current `nativeInit`/`nativeSetScripts` surface is not an import API;
* the app's Room wallet coverage/progress state must be reconciled with the imported light-client Script cursor;
* the current vendored `light-client-lib` is `0.5.4`-era material and is not proof of compatibility with selected `develop` `0.5.5` behavior;
* network-specific database paths help isolation, but do not substitute for genesis/chain validation;
* Android storage and restart/crash behavior make the atomic offline boundary a first-class requirement.

This is not a G3 design. It is a reason to keep the RP2 seam narrow and lifecycle-aware.

## 17. Exact implementation files and seams RP2 would touch

No files are to be changed by RP1. The following are the planned RP2 touch points in a disposable pinned upstream worktree and separate harness:

### Upstream paths to exercise or instrument

* `light-client-lib/src/storage/storage_trait.rs`
  * `get_filter_scripts`
  * `update_filter_scripts`
  * `update_block_number`
  * `get_min_filtered_block_number`
  * `update_min_filtered_block_number`
  * `rollback_to_block`
  * `filter_block`
* `light-client-lib/src/storage/backend.rs`
  * `StorageBackend`
  * `BatchWriter`
* `light-client-lib/src/storage/db/native.rs`
  * genuine RocksDB construction and transaction behavior
* `light-client-lib/src/storage/db/sqlite.rs`
  * genuine SQLite construction and transaction behavior
* `light-client-lib/src/protocols/filter/block_filter.rs`
  * real filter request scheduling and response handling
* `light-client-lib/src/protocols/filter/components/block_filters_process.rs`
  * accepted range, matching, and no-match progress path
* `light-client-lib/src/protocols/synchronizer.rs`
  * matched block download and real `filter_block` invocation
* `light-client-lib/src/protocols/light_client/mod.rs`
  * independently verified authority, proof processing, chain selection, and rollback
* `light-client-lib/src/service/impls.rs`
  * Script registration, `get_cells`, `get_transactions`, Script/progress queries
* `light-client-lib/src/tests/prelude.rs`
  * real chain/proof/filter fixture utilities
* `light-client-lib/src/tests/utils/chain.rs`
  * deterministic valid dev-chain construction and rollback

### New disposable harness components

* real packed-chain fixture generator and manifest;
* deterministic peer/provider that answers actual protocol requests;
* separate feature-specific source/baseline/import binaries or test processes;
* test-only event sink and request parser;
* typed handoff adapter/seam;
* independent semantic query comparator;
* authority fingerprint checker;
* adversarial package mutator;
* process-kill/failpoint runner;
* cross-backend matrix orchestrator.

No production package schema should be finalized as part of these components.

## 18. RP2 acceptance criteria

### REAL-UPSTREAM REPROOF PASS

RP2 passes only if one implementation demonstrates all of the following on the pinned upstream revision and both cross-backend cases:

1. genuine upstream RocksDB and SQLite storage on both sides;
2. exact typed Script identity including packed bytes and lock/type role;
3. Script-derived selection with no unrelated Script leakage;
4. destination chain/genesis/proof authority independently established;
5. safe typed progress handling, with either Strategy A proven or a separately labelled bounded Strategy C result;
6. actual historical replay avoidance observed at request, accepted-range, and processing boundaries;
7. query-level semantic equivalence with an independently derived baseline;
8. normal post-handoff filtering and continuation;
9. actual fork/reorg rollback and convergence;
10. fail-closed incompatible-chain, wrong-role, wrong-Script, stale, forged, and malformed handling;
11. atomic rows-plus-progress behavior under backend failure injection;
12. no source C/R authority or runtime state transferred.

The original D2 proposition passes only when the Strategy A arm proves zero replay of the approved covered interval. A Strategy C result must be reported separately as bounded-rescan portability and cannot be relabelled as the same proposition.

### CONDITIONAL PASS

A conditional pass is allowed only if the mechanism works through current protocol/storage semantics and the sole missing item is a small clean upstream seam. The seam must be precisely specified and limited to:

* typed Script/role state export/import;
* destination chain binding and validation;
* atomic S/H/P transaction;
* progress/rollback observer or lifecycle entry point.

It is not a conditional pass if the seam must add a new proof system, copy consensus state, redesign chain selection, or replay all history.

## 19. Explicit kill conditions

D2 core should be reconsidered or killed if any of these is observed:

* historical replay can be avoided only by importing source chain authority;
* a cursor cannot be safely bounded by destination-verified chain facts;
* no current or small-seam representation can preserve Script coverage/progress safely;
* imported rows cannot participate in ordinary upstream rollback;
* Script closure requires copying essentially the whole database or all historical facts;
* destination must redo essentially all history for a useful result;
* cross-backend query semantics diverge after a correct-looking import;
* backend transactions cannot atomically cover rows and progress;
* malformed, stale, wrong-chain, or wrong-role imports can leave durable partial state;
* the destination's next filter work is suppressed by manually advanced tip/minimum state rather than the real upstream path;
* the current upstream proof/filter architecture makes chain-bound handoff impossible without a material redesign;
* the fork test leaves old-branch A state live or makes the imported client diverge from an independently derived winning-fork baseline.

These are failure conditions, not implementation tasks to be worked around by weakening the observation.

## 20. Estimated experimental complexity

Expressed as components/steps rather than time:

1. pin and build the selected upstream revision in RocksDB and SQLite feature variants;
2. construct and validate the packed dev-chain fixture, including old and winning forks;
3. build a deterministic provider for real protocol messages and proof responses;
4. add no-op test instrumentation at filter, synchronizer, storage-progress, authority, and rollback boundaries;
5. implement independent source and baseline protocol drivers;
6. implement the typed test handoff seam and exact identity/chain validators;
7. implement the import driver with transaction and failure-injection controls;
8. implement independent service-level query comparison and negative-role checks;
9. execute same-backend controls and the two cross-backend matrices;
10. execute replay, continuation, authority-adversarial, destination-state, and reorg cases;
11. execute process-crash and concurrency/lifecycle checks;
12. preserve event logs, database fingerprints, fixture manifest, lockfiles, and reproducible result summaries.

The work is moderate research engineering, not a one-test patch. The complexity is justified because a simpler harness could pass while the actual proposition remains false.

## 21. Final recommendation

**PROCEED TO RP2 WITH UPSTREAM SEAM**

RP2 should start with the current `develop` pin and a test-only event sink, then add only the narrow typed handoff/atomicity seam needed to make Strategy A testable honestly. Strategy C must remain in the matrix as a bounded-rescan control. Strategy B should not be invented unless RP2 establishes that a raw typed cursor cannot be made safe.

The first RP2 milestone should be a negative-capable authority and replay harness: it must be able to demonstrate that a forged cursor, wrong hash, wrong genesis, losing fork, manually advanced tip, or direct storage shortcut does not produce a false pass. Only after those controls fail closed should semantic handoff results be interpreted.

## 22. What this plan deliberately does not claim

This plan does not claim:

* that current PB1 code is reusable;
* that current upstream already has a production import API;
* that a per-Script cursor is a cryptographic coverage proof;
* that a dev-chain result demonstrates testnet/mainnet scale;
* that Pocket Node can consume a handoff today;
* that cross-backend byte equality is expected or useful;
* that a final D2 package schema has been selected;
* that “no upstream patch” remains true.

Evidence from the real protocol path, independent baseline, authority adversaries, and reorg convergence must determine those conclusions.

