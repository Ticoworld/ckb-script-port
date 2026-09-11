# D2-RP2A — Real-Upstream Authority + Replay Harness Report

## 1. Verdict

**RP2-A PASS — PROCEED TO RP2-B HANDOFF CORE**

This is a pass for the experimental instrument only. It does not mean that D2
handoff, zero-replay portability, semantic equivalence, rollback convergence,
or cross-backend import has passed. No handoff payload or importer was
implemented in RP2-A.

The harness now runs the pinned upstream light-client code with real RocksDB
and SQLite storage, observes the actual filter/proof/synchronizer path, and
independently classifies deliberately false shortcuts. The negative controls
cannot be counted as legitimate replay avoidance merely because rows, a
cursor, a minimum, or an apparent tip exist.

## 2. Project starting checkpoint

Project: this repository (machine-local path omitted)

At the beginning of RP2-A this directory was not a Git repository. Its
material tracked contents were the two completed audit documents. The project
was initialized on branch `master` and the clean document checkpoint was:

`36514fa chore: checkpoint D2 research documents`

The starting tree contained:

```text
docs/audits/D2_SOURCE_AUDIT.md
docs/audits/D2_RP1_REAL_UPSTREAM_REPROOF_PLAN.md
```

`.gitignore` now excludes `_work/`, Cargo targets, temporary databases,
event/process logs, crash directories, and generated fixture binaries. It
does not exclude source, patches, manifests, schemas, reports, or summarized
results that belong in the project.

The disposable upstream checkout is under `_work/upstream/`; it is not
vendored into project history. RP2-A source is experimental test infrastructure
under `experiments/rp2-real-upstream/`, not a production D2 library.

## 3. Upstream pin verification

System under test:

`https://github.com/nervosnetwork/ckb-light-client.git`

The live remote was checked with `git ls-remote` before using the checkout:

| Ref | Observed revision |
|---|---|
| `develop` | `12e29522ab7e078ada704d4ac04cbc0498009b7b` |
| `v0.5.4` | `778590aa3ad7f71ee80b2d4c54af02c42e2dfa25` |
| `v0.5.5-rc1` | `e4f62a9c046ac4824a685d8e3ea9623559aaabcc` |

RP2-A remains pinned to the requested `develop` revision:

`12e29522ab7e078ada704d4ac04cbc0498009b7b`

The disposable checkout is detached at that exact revision. Its pre-patch
origin is the URL above and its pre-patch tree was clean. The upstream commit
is dated 2026-08-06 and is `Validate downloaded block data before indexing
(#290)`. RP2-A did not silently move to a newer `develop` commit.

Pinned dependency/build facts:

* `light-client-lib` version: `0.5.5`.
* Cargo.lock SHA-256:
  `F3A18D999A89519024B44B702C1637C571217CEB8D06CD7E39126E8D22EAE890`.
* Upstream toolchain file: Rust `1.95.0`.
* Actual build toolchain used: `rustc 1.96.0 (ac68faa20 2026-05-25)`, Cargo
  `1.96.0 (30a34c682 2026-05-25)`.
* RocksDB feature: default `rocksdb`, using `ckb-rocksdb = 0.21.1` with
  `snappy` and upstream native implementation.
* SQLite feature: `--no-default-features --features sqlite`, using bundled
  `rusqlite = 0.32` and the upstream SQLite implementation.
* The SQLite test graph still compiles upstream `ckb-store` as a development
  dependency, so native RocksDB is compiled during the SQLite test build too.
  That does not change the runtime `Storage` selection: `storage/db/mod.rs`
  selects `sqlite` when the `sqlite` feature is enabled.

The Windows build also required the disposable `libclang.runtime.win-x64`
22.1.8 DLL and `CXXFLAGS=-D_WIN32_WINNT=0x0602` for the available MinGW clang
toolchain. This prerequisite is documented in the tracked build manifest and
runner.

## 4. Exact upstream modifications

The patch is preserved at:

`patches/rp2/0001-rp2a-observer-and-negative-controls.patch`

Final patch SHA-256:

`91D4E480A88267441A751F3E83032BEB6BA30DA25D63A07B0B222F786A6FB4AD`

Final diffstat: 10 files, 1,172 insertions, 2 deletions.

The patch contains only test-observation/test-harness work:

| Upstream path | Change | Production decision changed? |
|---|---|---|
| `light-client-lib/src/rp2_observer.rs` | Test-only JSONL observer, sequence numbers, run/client/backend identity, origin tags. | No; compiled only for tests. |
| `light-client-lib/src/lib.rs` | Makes the existing test module visible within the test crate and adds the test-only observer module. | No runtime export. |
| `protocols/filter/block_filter.rs` | Observes actual `GetBlockFilters` requests and rejected `BlockFilters`. | No. |
| `protocols/filter/components/block_filters_process.rs` | Observes received/accepted filter ranges and matched-block requests. | No. |
| `protocols/light_client/mod.rs` | Observes successful `commit_prove_state` authority acceptance. | No. |
| `protocols/synchronizer.rs` | Observes matched blocks entering the real synchronizer. | No. |
| `storage/storage_trait.rs` | Observes registration, cursor/min transitions, `filter_block`, and rollback hooks. | No. |
| `tests/rp2_authority_replay.rs` | Real upstream fixture, normal baseline, adversarial controls, authority fingerprint, dry-run validator. | Test-only. |
| `tests/mod.rs`, `tests/utils/mod.rs` | Registers the RP2-A test module and re-exports the upstream test utility needed by it. | No. |

The source checkout remains dirty only by these expected modifications. No
upstream commit was made.

## 5. Backend build evidence

The tracked build description is
`experiments/rp2-real-upstream/manifests/build-manifest.json`. The final
machine-specific artifact record is generated under the ignored
`run/build-evidence.json`.

The final entry point built both variants with `--locked`:

```text
cargo test --manifest-path light-client-lib/Cargo.toml --no-run --locked
cargo test --manifest-path light-client-lib/Cargo.toml --no-run \
  --no-default-features --features sqlite --locked
```

| Backend | Test artifact | Artifact SHA-256 | Result |
|---|---|---|---|
| RocksDB | `ckb_light_client_lib-3a1f157827394d94.exe` | `3E56CED79FB679A940BA36E8DEE83788713759660326B808438364DC6F644543` | Built and ran |
| SQLite | `ckb_light_client_lib-659deef4d0f22f1b.exe` | `E2FFD3F73A103ABFF9B81CB9D4C3E8EC66475B7B2D81C3ECD7C9F942996791E3` | Built and ran |

The backend implementations are not local wrappers and do not use PB1's
SQLite schema. Each RP2 test creates `Storage` through the pinned upstream
feature-selected implementation. RocksDB uses its `WriteBatch`; SQLite uses
the upstream `kv_store` schema and a SQLite transaction in its `Batch::commit`.

## 6. Real fixture description

RP2-A uses the upstream `MockRunningChain` and `MockChain::new_with_dummy_pow`,
not PB1-style string hashes or fake transaction bytes. The full-node-side
fixture generator processes genuine packed CKB blocks, headers, transactions,
and filter data through the upstream chain services. The light-client-side
storage is a separate upstream `Storage` instance.

Fixture facts:

* chain kind: upstream `MockRunningChain` dummy-PoW development fixture;
* heights: 0 through 36, 37 packed blocks;
* genesis:
  `0x50be56a206c3e8bc6ca3e4feb92bca834e3ac1c33ecb7bb3a7715f048f822337`;
* deterministic tip height: 36;
* deterministic tip hash:
  `0xcaa9f7e215701f8fe1af1a52a3c8be4ff53ad0911c853399998a1c0c1eb7e586`;
* Script-A-related block: 31;
* unmatched interval: 1..30;
* Script A is a genuine packed lock Script with code hash `[0x42; 32]`, empty
  args, the packed default hash type, and exact packed bytes recorded in
  `run/fixture/manifest-{rocksdb,sqlite}.json`;
* Script-A packed bytes:
  `0x3500000010000000300000003100000042424242424242424242424242424242424242424242424242424242424242420000000000`;
* Script-A script hash:
  `0x415982a22322a33de7f3806f2b6c09e89ad3b5c367b57d6c3122daae76f38eab`;
* the transaction consumes an upstream cellbase-derived input and creates an
  output locked by Script A; block 31 contains the cellbase and the real
  transaction.

The fixture's timestamps are explicitly set from the packed block number.
Repeating the baseline produced the same manifest hash for RocksDB
(`2994CDB1FC5D5176BE5CD9D16D39C637A72B8A8E9AFC72BA93BECC5B7B6C17E8`) and
SQLite (`5ACD9B5DD5152A055E20C81856A0F755D4B499953F72C6D5D91799B9F9E30517`).
After removing the backend field, the two manifests are byte-equivalent.

This is intentionally only the RP2-A foundation. It does not yet contain
Script B, role collisions, spend/change closure, post-handoff activity, or a
fork. It is therefore not evidence for the full RP1 fixture requirements.
The first attempt with non-empty Script args exposed an `InvalidDAO` in this
minimal construction; RP2-B must add non-empty args and richer transaction
closure rather than silently treating this reduced Script as full identity
coverage.

## 7. Protocol path actually exercised

The normal baseline reaches these real upstream boundaries:

1. `LightClientChainService::set_scripts` in
   `service/impls.rs:768-787` receives the Script and role through the service
   path and calls `StorageWithChainData`/`LightClientStorage::update_filter_scripts`.
2. Registration writes the upstream `FILTER_SCRIPTS` entry. Because the start
   is zero, upstream also filters the genuine genesis block.
3. `FilterProtocol::notify` reads the current global minimum and calls the
   actual `send_get_block_filters`, which emits a packed `GetBlockFilters`
   protocol message starting at block 1.
4. The harness feeds packed `BlockFilters` containing
   `SnapshotExt::get_block_filter_data` and the corresponding real block
   hashes. `FilterProtocol::received` invokes the real
   `BlockFiltersProcess::execute`, including filter-hash continuity checks and
   Script matching.
5. For range 1..30 there is no match. The real upstream process calls
   `update_block_number(30)` and then advances the global minimum.
6. For range 31..36 there is one match. Upstream stores a matched-block
   work item and emits a real blocks-proof request.
7. The harness feeds a genuine `SendBlocksProof` built by upstream proof
   utilities through `LightClientProtocol::received`, then feeds the genuine
   packed block through `SyncProtocol::received`.
8. The real synchronizer validates the matched block path and calls
   `LightClientStorage::filter_block`; that implementation scans the actual
   packed transaction, indexes Script-specific cell/transaction rows, and
   stores the matched header facts needed by the query layer.
9. The real synchronizer calls `update_block_number(36)`. Upstream then
   updates `MIN_FILTERED_NUMBER`.

`establish_authority` seeds only the peer's request bookkeeping so a
deterministic proof can be delivered. Authority acceptance itself is not
seeded: the actual `SendLastStateProof` contains upstream verifiable headers
and MMR proof material and is passed through `LightClientProtocol.received`.
The resulting `chain_authority_accepted` event is emitted after upstream
`commit_prove_state` accepts it.

The network context is a deterministic upstream `MockNetworkContext`, not a
live socket or mainnet process. The protocol messages and handlers are real;
the peer/provider is test-controlled.

## 8. Event schema

`experiments/rp2-real-upstream/event-schema.json` defines schema version 1.
Each JSONL record contains:

* `schema_version`;
* `run_id`, `client_id`, `backend`;
* contiguous `sequence` starting at 1;
* `event_type`;
* `origin`;
* structured `fields` containing ranges, heights, hashes, status, and relevant
  Script/progress data.

Observed event families include:

* `chain_authority_accepted`;
* `get_block_filters_requested`;
* `block_filters_received`, `block_filters_accepted`,
  `block_filters_rejected`;
* `matched_blocks_requested`, `matched_block_received`;
* `filter_block_entered`;
* `script_registration_started`, `script_registration_completed`;
* `script_progress_before`, `script_progress_after`;
* `min_filtered_before`, `min_filtered_after`;
* `rollback_started`, `rollback_completed`;
* `authority_fingerprint`, `authority_fingerprint_unchanged`;
* explicitly adversarial `direct_progress_mutation`,
  `direct_authority_mutation`, and `rows_only_shortcut`;
* `handoff_validation_rejected` for the dry-run guard.

Origin tags distinguish normal chain proof, normal scheduler/filtering,
normal synchronizer, registration, rollback, approved validation, and named
adversarial direct mutation. The observer is test-only and does not alter
protocol outcomes.

## 9. Authority fingerprint definition

The diagnostic fingerprint enumerates all upstream KV rows whose first key
prefix is in the conservative authority/shared boundary:

* 160: `BlockHash`;
* 192: `BlockNumber`;
* 208: `CheckPointIndex`;
* 224: `Meta`, including `GENESIS_BLOCK`, `LAST_STATE`,
  `LAST_N_HEADERS`, and `MIN_FILTERED_NUMBER`.

It records exact key and value bytes as a structured JSON object. This is
deliberately conservative: it catches a source-supplied header, block-number
mapping, checkpoint, or metadata write instead of declaring those bytes to be
harmless historical closure.

It is not a formal upstream authority type and does not prove that every
semantic authority dependency has been captured. In particular, the current
storage design has no first-class C/H type boundary. That limitation is
reported below and remains an RP2-B concern.

For rejected chain-binding claims, the before and after fingerprints were
exactly equal. The manual-tip adversary intentionally changes `LAST_STATE` and
is classified as an authority mutation; it is not accepted as a valid run.

## 10. Normal baseline results

The final reproducibility entry point ran the same seven-test RP2-A suite for
both backends. The baseline in each backend produced:

| Observation | Result |
|---|---|
| independently accepted authority | genesis through verified tip 36 |
| actual filter requests | starts 1 and 31 |
| accepted range 1 | 1..30, 30 filters, `match_count=0` |
| accepted range 2 | 31..36, 6 filters, `match_count=1` |
| matched block proof path | block 31 requested, proved, received by SyncProtocol |
| `filter_block_entered` | genesis registration plus matched block 31 |
| final Script cursor | 36 |
| final `MIN_FILTERED_NUMBER` | 36 |
| event trace | 29 events, contiguous sequence, no verifier errors |

The range 1..30 is the key negative measurement: it was requested, accepted,
hash-checked, and used to advance progress with no Script match. It is
historical filtering work, not skipped history. Existing rows and the later
cursor do not change that classification.

The two `filter_block_entered` events do not mean that every unmatched block
was downloaded. One is the expected genesis filter caused by registration at
zero; the other is the real matched block body. The unmatched interval was
processed as filter data without bodies.

## 11. Adversarial case results

The following controls ran independently against fresh upstream storage:

| Case | Shortcut | Expected and observed result |
|---|---|---|
| ADV-1 | Directly advance Script A's cursor to 36 via the storage route. | `DIRECT_PROGRESS_MUTATION`; no filter request. |
| ADV-2 | Directly set `MIN_FILTERED_NUMBER` to 36. | `DIRECT_PROGRESS_MUTATION`; no per-Script coverage. |
| ADV-3 | Write a convincing `LAST_STATE` tip without proof. | `AUTHORITY_INVALID`; fingerprint records the direct mutation and no authority receipt exists. |
| ADV-4 | Write Script-looking rows by calling `filter_block` directly without filter coverage. | `ROWS_ONLY`; rows exist but cursor remains 0 and no historical filter range was requested. |
| ADV-5 | Same height, wrong block hash. | Rejected before any handoff write. |
| ADV-6 | Wrong genesis. | Rejected before any handoff write. |
| ADV-7 | Cursor beyond independently verified height. | Rejected before any handoff write. |
| ADV-8 | Losing-fork handoff fact. | Deferred to RP2-B/reorg fixture; not faked in RP2-A. |
| ADV-9 | Exact-looking Script claim with no independently accepted authority. | `AUTHORITY_INVALID`; no write. |

The combined ADV-5..8 test rejected five claims: wrong hash, wrong genesis,
beyond verified height, wrong role, and wrong packed Script. The role and
packed-Script cases are identity guards rather than chain-fork tests.

## 12. Evidence-verifier classifications

`experiments/rp2-real-upstream/src/rp2a_verifier.py` is a separate standard
library Python program. It reads JSONL; it does not consume a future importer
success bit or use PB1 counters. It validates JSON, required fields, schema
version, backend, and contiguous event sequences before classification.

Final verifier output for each backend classified:

```text
baseline                  NORMAL_FILTERED
adv-1-direct-cursor      DIRECT_PROGRESS_MUTATION
adv-2-direct-minimum     DIRECT_PROGRESS_MUTATION
adv-3-manual-tip         AUTHORITY_INVALID
adv-4-rows-only          ROWS_ONLY
adv-5-8-chain-binding    AUTHORITY_INVALID
adv-9-dry-run-identity   AUTHORITY_INVALID
```

The verifier returned `passed: true` with no failures for the combined
RocksDB+SQLite event directory. It distinguishes requested/no-match work from
unrequested history by requiring a real request/accepted-range trace. The
verifier contains a fail-closed `GENUINELY_NOT_REQUESTED` branch for
RP2-B, but it is intentionally not exercised in RP2-A because there is no
import transition. That branch requires a specifically originated approved
transition with a coherent coverage interval, no normal filter request within
that interval, plus separate independent query-observer evidence for
`get_cells`, `get_transactions`, and Script status, and a separate authority
observer showing no C-state change. RP2-B must add those independently
verifiable observations; an importer cannot make it appear merely by emitting
`success=true`.

## 13. Dry-run chain-binding results

The test-only `HandoffClaim` contains:

* exact packed Script bytes;
* exact lock/type role;
* proposed height;
* exact block hash;
* expected genesis.

`validate_claim` performs no storage writes. It requires a receipt created by
the real accepted proof path, checks the claim genesis, requires the height to
be no greater than the independently verified height, requires exact height
and hash equality, and checks that persistent destination `LAST_STATE` agrees
with the receipt.

Results:

* wrong hash: rejected;
* wrong genesis: rejected;
* cursor beyond verified destination: rejected;
* wrong role: rejected;
* wrong packed Script: rejected;
* no proof receipt: rejected;
* authority fingerprint after all rejected claims: byte-for-byte unchanged.

This is a guard test, not an import API. It proves that the guard can reject
the listed claims; it does not yet prove that a valid payload can be applied.

## 14. C/H boundary findings

The current upstream storage model does not expose the boundary as types. The
RP2-A operational rule is therefore conservative: a dry-run handoff cannot
write any row in the fingerprinted prefix, and rejected claims perform no
writes.

The relevant current categories are:

| Category | Upstream representation | RP2-A classification |
|---|---|---|
| genesis identity | `Meta/GENESIS_BLOCK` | C — destination-established chain identity |
| current chain/tip and recent headers | `Meta/LAST_STATE`, `Meta/LAST_N_HEADERS` | C — must come from accepted proof/chain processing |
| block/header and number mappings | `BlockHash`, `BlockNumber` rows | U/C-H coupled; matched Script filtering writes them, but they can influence chain/query authority and must not be blindly imported |
| filter checkpoints/hashes | `CheckPointIndex`, related metadata | C — filter/chain verification authority |
| registered Script + role + cursor | `Meta/FILTER_SCRIPTS` key: packed Script bytes plus role byte; BE cursor value | P — per-Script coverage/progress, but stored in the same low-level KV space |
| global minimum | `Meta/MIN_FILTERED_NUMBER` | P — global derived minimum, never a portable A-only authority |
| Script cell indexes | `CellLockScript`, `CellTypeScript` | S — derived Script view candidate |
| Script transaction indexes | `TxLockScript`, `TxTypeScript` | S, with H dependencies |
| stored transactions | `TxHash` value containing block/tx indexes and packed transaction | H — shared historical closure, not semantically owned by one Script |
| matched filter work | `Meta/MATCHED_FILTER_BLOCKS` | R/U — in-flight scheduler/proof work, not a handoff payload |
| consensus parameters | `Arc<Consensus>` supplied to service/runtime | C — not established by Script state |
| peer/proof/in-flight state | `Peers`, `ProveState`, request maps, network context | R — runtime only |
| `StorageWithChainData` aggregate | storage + peers + pending transactions | U — current API couples persistent view with runtime data |

The central unresolved coupling is that `filter_block` needs prior stored
transactions to resolve spent outputs, then writes shared transaction/header
facts alongside Script indexes. A useful Script view is not automatically a
closed set of only Script-keyed rows.

## 15. RP1 assumptions contradicted or narrowed

RP1 and the earlier research narrative are not authoritative for the
following points:

* The original “no upstream patch required” claim is not established. RP2-A
  needed a test-only observer patch, and a real typed import seam is still
  likely required for production correctness and atomicity.
* A `13/13 skipped` counter would be inadequate. This harness records the
  actual request and accepted-range path and labels 1..30 as work despite
  having no matches.
* “Exact Script” must mean exact packed Script bytes plus role. A Script hash
  alone is not the identity key used by upstream. Genesis/network binding is
  separate from the Script key and must be validated independently.
* Current `FILTER_SCRIPTS` progress is a raw cursor and `MIN_FILTERED_NUMBER`
  is a global derived value. Neither is a persisted proof that every relevant
  historical filter was processed.
* The current upstream test utility is suitable for a real protocol control,
  but it is a dummy-PoW development chain, not testnet/mainnet evidence.
* The current SQLite feature is a real backend, but its upstream test graph
  still drags in native RocksDB through `ckb-store` development dependencies.
* A successful baseline does not establish any cross-client or
  cross-backend handoff property because RP2-A deliberately has no imported
  client.

## 16. Unresolved upstream coupling

The following remain open and are intentionally not hidden by the RP2-A pass:

1. There is no public typed export/import API for Script-derived state and
   progress.
2. The raw storage trait exposes low-level batch operations and business
   defaults, but not a transaction that semantically binds Script rows,
   cursor, global minimum, closure facts, and an import completion marker.
3. A source cursor does not prove historical filter coverage independently.
4. The global minimum is recomputed across all registered Scripts; an A-only
   import cannot simply transport a source global minimum into a destination
   containing other Scripts.
5. `TxHash`, `BlockHash`, and `BlockNumber` rows cross the proposed S/H/C
   boundary. Importing them may overwrite or add authority-relevant facts.
6. Current rollback behavior is coupled to Script cursor and shared indexed
   rows. RP2-A added observation hooks but did not prove imported rows
   participate in rollback.
7. RocksDB and SQLite have different low-level transaction and locking
   mechanisms even though both implement the same trait. Atomic cross-row
   handoff is untested.
8. No old/new upstream version compatibility, crash recovery, concurrent
   import, merge, or destination pre-existing-state behavior has been tested.
9. Non-empty Script args and lock/type role collisions remain absent from the
   minimal fixture.

### Likely upstream patch requirement

For RP2-A the answer is **TEST-ONLY INSTRUMENTATION**. The observer and
negative-control tests are disposable and do not change production protocol
decisions.

For the complete D2 experiment, **SMALL UPSTREAM SEAM** is the current most
likely answer. A sound seam must expose a typed, version-pinned operation that
validates destination chain authority, selects only an exact Script/role view,
updates Script rows and progress atomically, and participates in ordinary
rollback. Existing raw storage internals do not provide that contract.

**ZERO PATCH** is not currently justified. **MATERIAL UPSTREAM DESIGN CHANGE**
becomes necessary if the shared `TxHash`/header facts or rollback coupling
cannot be separated without transferring chain authority. RP2-A intentionally
does not choose between those outcomes by pretending the dry-run validator is
an importer.

## Progress strategy and RP2-B design choice

### Strategy A — typed Script progress

This is the first RP2-B target. Transport a typed statement for one exact
packed Script and role, with a progress height and exact block hash, but accept
it only after the destination has independently verified the same genesis and
chain boundary. Recompute destination `MIN_FILTERED_NUMBER` from all
destination registrations; never import a source global minimum as if it were
per-Script state.

A is useful only if the imported Script view and cursor are committed together
and the cursor is eligible for ordinary reorg rollback. The current raw
`FILTER_SCRIPTS` value does not itself prove that the source processed every
filter in the interval. That coverage contract must be a property of the
typed seam and RP2-B evidence, not a field accepted because it is numerically
plausible.

### Strategy B — reconstruct from coverage evidence

The current persisted view does not retain a per-block coverage proof. Filter
hash-chain material exists in the protocol/provider path, but importing enough
of it to establish historical non-omission would introduce a proof bundle and
new chain-fact dependencies. That is substantially larger than the intended
v0.1 boundary and is not demonstrated by RP2-A.

B remains the strongest trust model if A cannot safely bind a cursor to
coverage, but it should not be invented from the existing rows. RP2-B must
either identify actual sufficient upstream evidence or mark B infeasible for
the first version.

### Strategy C — bounded rescan

C is the safety fallback. Restore a Script view but deliberately rescan a
defined interval before treating the view as current. The interval must begin
early enough to reconstruct spends and closure facts, and imported rows must
coexist with replay without duplicate or conflicting index semantics. A
checkpoint/finality bound could make this useful, but it still needs an
explicit merge policy and rollback test.

Recommended order: test A through a small typed seam; if exact coverage and
rollback cannot be established, test C. Do not call a raw-cursor copy a
successful D2 handoff. Do not escalate to B without evidence that current
upstream data can support it.

## RP2-B topology, replay observation, and semantic comparison

RP2-A has a normal baseline and independent fresh adversarial clients, but no
SOURCE/BASELINE-DESTINATION/IMPORT-DESTINATION handoff topology yet. RP2-B
must add three separate upstream `Storage` instances and separate directories
for every run:

* SOURCE processes A normally and exports only through the approved seam;
* BASELINE DESTINATION starts fresh, establishes authority independently, and
  derives A normally;
* IMPORT DESTINATION starts fresh, independently establishes authority, then
  receives the handoff and resumes.

The RocksDB-to-SQLite and SQLite-to-RocksDB cases must use the same pinned
upstream feature-selected `Storage` implementations. A same-backend control is
useful for separating serialization errors from backend errors.

The replay measurement must compare actual `get_block_filters` request events,
accepted ranges, `filter_block` entries, matched-body requests, and cursor
transitions. A requested range with zero matches remains work. Existing rows,
a manually set tip, or a cursor write are not replay evidence. A future
`approved_import_seam` event is only an observation point; RP2-B must pair it
with destination query/state evidence so the verifier does not trust a
success marker.

Primary equivalence checks must exercise upstream query behavior, not raw KV
equality:

* `get_cells` for A;
* `get_transactions` for A;
* Script role and progress/status;
* live/dead cell consequences where exposed;
* new A activity after handoff;
* repeated queries after a restart.

The independent baseline must derive its expected result without exporter,
importer, or shared state-selection code. Raw KV snapshots are secondary
diagnostics only. Shared transactions must be compared by the externally
visible A closure and by the headers independently present in each destination.

## Consensus separation, reorg, destination state, and crash boundary

RP2-B must prove that a valid Script import does not replace the destination's
`GENESIS_BLOCK`, `LAST_STATE`, recent-header state, checkpoints, filter-hash
authority, or consensus parameters. It must include wrong genesis, same-height
wrong hash, losing-fork hash, and source progress beyond the destination tip.
The destination may accept a claim only when its own proof/chain path already
establishes the required fact, or it must reject/bounded-rescan.

The mandatory reorg sequence is: derive A through H, hand off, present a
competing branch below or at H, run normal light-client rollback, and compare
the imported destination with an ordinary baseline on the winning branch.
The fixture should use the shallowest fork that deletes or resurrects an A
cell and crosses the imported cursor. RP2-A only installed rollback observer
hooks; it did not claim this test.

The following destination matrix is required for RP2-B. Policy is still open
where shown; it must be decided before interpreting a pass.

| Destination condition | Required result |
|---|---|
| fresh, same genesis, compatible authority | accept if seam validates and commit is atomic |
| identical repeated import | idempotent accept, with no duplicate semantic rows |
| unrelated Script already present | merge only if global-min recomputation is correct |
| same Script older than package | explicit upgrade/merge policy; otherwise reject |
| same Script equal to package | idempotent accept |
| same Script newer than package | reject or explicit bounded reconciliation; never silently downgrade |
| conflicting rows | reject or deterministic reconciliation; policy currently unresolved |
| different chain/genesis | reject |
| wrong role or packed Script | reject |
| partial previous import | recover or reject using a journal/completion marker |

For crash testing, the seam must establish whether Script rows and progress can
share one atomic backend boundary. RocksDB `WriteBatch` and SQLite's upstream
transaction-backed `Batch::commit` make individual upstream batches atomic, but
RP2-A did not prove that a future cross-category import can use that boundary.
G1 must kill the process before validation, during import, after rows but before
progress, and after progress but before completion. If the transaction cannot
cover the relevant rows and progress together, a journal/recovery protocol or
an upstream change is required. Import should occur with the client stopped
unless a supported concurrency protocol is proven.

## Exact RP2-B implementation files and seams

The next experiment should touch the smallest possible surface:

* a new test-only/approved seam adjacent to `storage/storage_trait.rs` or a
  dedicated upstream storage handoff module;
* backend batch plumbing in `storage/backend.rs` and
  `storage/db/native.rs`/`storage/db/sqlite.rs` if the existing trait cannot
  atomically express the operation;
* `service/impls.rs` for a lifecycle-safe service entry point;
* `protocols/light_client/mod.rs` and `storage/storage_trait.rs` for rollback
  participation;
* the RP2 test module for SOURCE, independent baseline, import destination,
  query comparisons, and fork scenarios;
* the independent verifier for observed approved-import transitions and query
  evidence.

No production package schema should be defined until those seams are shown to
be sufficient. No Pocket Node files should be changed.

## RP2-A acceptance criteria and explicit kill conditions

The RP2-A acceptance criteria were met as follows:

1. genuine RocksDB and SQLite upstream instances ran: **PASS**;
2. real filter requests and processing were observable: **PASS**;
3. requested/no-match history was distinct from unrequested history: **PASS**;
4. direct cursor/minimum changes could not masquerade as replay avoidance:
   **PASS**;
5. direct chain-authority mutation could not masquerade as independent proof:
   **PASS**;
6. wrong hash/genesis/out-of-range claims failed closed: **PASS**;
7. rejected dry-run claims left authority and Script state unchanged:
   **PASS**;
8. the event model has a distinct future approved-import origin: **PASS as
   instrumentation readiness; no import was executed**;
9. no PB1/local replay counter was used: **PASS**.

RP2-B must be marked FAIL and D2 reconsidered if any of these occurs:

* historical replay cannot be avoided without importing foreign chain
  authority;
* safe progress cannot be represented or reconstructed;
* imported state cannot participate in ordinary rollback;
* Script closure requires copying effectively the entire database;
* destination must redo essentially all historical work;
* backend semantics cannot make rows/progress atomic or recoverable;
* imported query behavior does not converge with independently derived state;
* chain binding accepts same-height wrong-hash, wrong-genesis, losing-fork, or
  beyond-tip claims.

## Experimental complexity

RP2-B is not a single test. It consists of these components:

1. typed upstream seam and transaction boundary;
2. full valid A/B/role/closure fixture;
3. three-client lifecycle and two-backend matrix;
4. source export selection and independent baseline derivation;
5. destination authority and progress validation;
6. actual scheduler replay instrumentation after import;
7. query-level equivalence and continuation;
8. fork construction and rollback convergence;
9. destination-state merge/repeat/recovery cases;
10. crash, restart, and concurrency tests;
11. independent evidence verifier extensions;
12. performance/size measurements on a larger history.

RP2-A implements the observer, minimal valid control fixture, both backend
builds, baseline, negative controls, dry-run binding guard, and verifier. It
does not collapse the remaining components into a premature library design.

## POCKET IMPLICATION

No Pocket Node integration was attempted. The only immediate implication is
that a future consumer will likely need a lifecycle-safe restore API over JNI,
with the light-client database closed or otherwise synchronized during import.
If rollback-safe progress requires application-side reconciliation, that must
be identified in RP2-B before G3 is considered credible. Android filesystem
and storage limits are not measured by RP2-A.

## 17. Exact files/patches created

Tracked project artifacts created in RP2-A:

```text
experiments/rp2-real-upstream/README.md
experiments/rp2-real-upstream/event-schema.json
experiments/rp2-real-upstream/fixture/README.md
experiments/rp2-real-upstream/fixture/manifest.schema.json
experiments/rp2-real-upstream/manifests/build-manifest.json
experiments/rp2-real-upstream/scripts/apply-rp2a-upstream-patches.ps1
experiments/rp2-real-upstream/scripts/run-rp2a.ps1
experiments/rp2-real-upstream/src/rp2a_verifier.py
patches/rp2/0001-rp2a-observer-and-negative-controls.patch
docs/audits/D2_RP2A_AUTHORITY_REPLAY_HARNESS_REPORT.md
```

The corresponding disposable upstream source files are carried in the patch,
not copied into the production project:

```text
light-client-lib/src/rp2_observer.rs
light-client-lib/src/tests/rp2_authority_replay.rs
light-client-lib/src/protocols/filter/block_filter.rs
light-client-lib/src/protocols/filter/components/block_filters_process.rs
light-client-lib/src/protocols/light_client/mod.rs
light-client-lib/src/protocols/synchronizer.rs
light-client-lib/src/storage/storage_trait.rs
light-client-lib/src/lib.rs
light-client-lib/src/tests/mod.rs
light-client-lib/src/tests/utils/mod.rs
```

Ignored run outputs include backend databases, fixture manifests, JSONL event
traces, build evidence, and result summaries. They were generated only inside
the project-owned RP2 run root.

## 18. Test commands and results

Formatting check:

```text
cargo fmt --all -- --check                         PASS
```

Direct backend controls:

```text
cargo test --manifest-path light-client-lib/Cargo.toml \
  rp2a_ -- --test-threads=1 --nocapture              RocksDB: 7 passed

cargo test --manifest-path light-client-lib/Cargo.toml \
  --no-default-features --features sqlite rp2a_ \
  -- --test-threads=1 --nocapture                    SQLite: 7 passed
```

Independent verifier:

```text
python experiments/rp2-real-upstream/src/rp2a_verifier.py \
  --events-dir experiments/rp2-real-upstream/run/events \
  --output experiments/rp2-real-upstream/run/results/rp2a-verification.json
```

Result: `passed: true`, no failures, both backends represented.

Single documented entry point:

```powershell
.\experiments\rp2-real-upstream\scripts\run-rp2a.ps1
```

Final entrypoint result: exit code 0; both feature builds completed; 7 tests
passed for each backend; independent verifier passed. The runner verifies the
upstream HEAD, resets only the owned RP2 run root, applies/verifies the
reviewable patch, builds both variants, runs the tests serially, and invokes
the verifier.

Two runner defects were found and repaired during this milestone: the original
runner used a relative Cargo manifest path without changing to the upstream
checkout, and Windows PowerShell 5.1 treated redirected Cargo stderr as a
terminating error. The final runner uses an explicit upstream location,
restores the caller location, and checks Cargo exit codes separately from
normal stderr output.

## 19. Final project Git status

After this report and the RP2-A artifacts are committed, the expected final
project state is:

* branch: `master`;
* working tree: clean;
* `_work/` and generated RP2 run data remain ignored and disposable;
* no D2 production library, final package schema, or Pocket Node integration
  exists.

The final status is checked again immediately before handoff. Any status
deviation is a release error, not experimental evidence.

## 20. Final `grant_find` nested-repository status

`grant_find` itself was treated read-only throughout RP2-A. Its nested research
repository remains:

the separate `grant_find` research checkout (machine-local path omitted)

* branch: `main`;
* HEAD: `bec39d6764e2622139d4f0a93613126f64d4f5a5`;
* working tree: clean;
* configured origin: none.

No file, dependency, test, configuration, history, or tracked content in
`grant_find` was modified.

## 21. Recommendation

**RP2-A PASS — PROCEED TO RP2-B HANDOFF CORE**

RP2-B should target Strategy A first, but only through a small typed upstream
seam that validates the exact packed Script/role and the destination's
independent genesis + height/hash authority, writes only an approved Script
view, recomputes destination global progress, and binds Script rows and
progress atomically. If those conditions cannot be provided, fall back to a
bounded-rescan design rather than importing a raw cursor.

## 22. What RP2-A does and does not prove

RP2-A proves:

* real pinned upstream filter/proof/synchronizer execution is observable;
* real RocksDB and SQLite light-client storage can run the control path;
* requested/no-match ranges are distinguishable from genuinely unrequested
  ranges;
* direct cursor/minimum writes, rows-only shortcuts, and direct authority
  writes cannot masquerade as a normal pass;
* wrong hash, genesis, role, packed Script, and out-of-range claims fail the
  dry-run guard without changing the destination fingerprint.

RP2-A does not prove:

* a valid source-to-destination state handoff;
* imported query equality;
* cross-backend payload compatibility;
* zero replay after import;
* post-import continuation;
* fork/reorg rollback convergence;
* atomic crash-safe import;
* mainnet-scale package size or performance;
* Pocket Node viability.

Those are RP2-B and later gates. A positive RP2-B result is not admissible
unless it uses the negative-control machinery established here.
