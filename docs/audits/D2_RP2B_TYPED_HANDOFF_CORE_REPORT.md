# D2-RP2B - Typed Script Handoff Core Report

## 1. Verdict

**Original pre-repair verdict (preserved): RP2-B PARTIAL - SEAM REPAIR REQUIRED**

**Current R1 verdict: RP2-B PASS - PROCEED TO RP2-C CROSS-BACKEND**

The typed Strategy A seam works on both real upstream backends for the core
handoff: independently verified destination authority, exact Script/role
selection, atomic S/H/P installation, zero replay of the approved historical
interval, service-level query equivalence, ordinary post-H filtering, safe
reimport, and fail-closed adversarial inputs all pass.

The original strict matrix was incomplete because the pinned dummy-PoW fixture
could not spend the synthetic `[0x42; 32]` A lock. That blocker and the
original partial recommendation remain below. The dated R1 section records
the focused fixture repair and the resulting full lifecycle proof.

Sections 2–22 are the preserved R0 record; where their fixture counts or
recommendation differ, Section 23 is the dated R1 result that supersedes them.

This result is an experiment for trusted-source self-portability. It is not a
public package format, a completeness proof, a trustless snapshot, or a
reorg-safety result.

## 2. Checkpoints and scope

Project: `C:\Users\timot\Desktop\2026\CKB\ckb-script-port`

Pinned upstream system under test:

`nervosnetwork/ckb-light-client`

`12e29522ab7e078ada704d4ac04cbc0498009b7b`

The upstream checkout is disposable and remains detached at that revision.
Project HEAD at handoff is `f011722 feat: add RP2-A authority replay harness`;
the project worktree contains the report, patch, runner, and evidence-summary
changes described below. No upstream commit was made.

RP2-B does not integrate Pocket Node, benchmark G2 scale, define a public
serialization/package schema, or make a cryptographic completeness claim.

## 3. RP2-A reproducibility gate

The final runner first rebuilt and ran the RP2-A suite before RP2-B:

| Backend | RP2-A tests | Independent verifier |
|---|---:|---|
| RocksDB | 7 passed, 0 failed | pass |
| SQLite | 7 passed, 0 failed | pass |

The verifier classified every RP2-A baseline/control as expected, including
`NORMAL_FILTERED`, `DIRECT_PROGRESS_MUTATION`, `ROWS_ONLY`, and
`AUTHORITY_INVALID`. Its output also validates the RP2-B event files without
weakening the RP2-A controls. RP2-A therefore remained a valid measuring
instrument before this handoff implementation was accepted.

## 4. Fixture and authority facts

The real upstream `MockRunningChain`/dummy-PoW fixture has heights 0..36 at
the handoff boundary:

* genesis: `0x50be56a206c3e8bc6ca3e4feb92bca834e3ac1c33ecb7bb3a7715f048f822337`;
* handoff height: `H = 36`;
* handoff hash:
  `0xcaa9f7e215701f8fe1af1a52a3c8be4ff53ad0911c853399998a1c0c1eb7e586`;
* A-related block: 31;
* baseline requests: `1..30` (no match), then `31..36` (one match);
* source and baseline final A cursor: 36.

Script A is an exact packed lock Script with code hash `[0x42; 32]`, empty
args, and the default packed hash type. Its packed bytes are
`0x3500000010000000300000003100000042424242424242424242424242424242424242424242424242424242424242420000000000`.
Script B is a distinct packed lock
Script with code hash `[0x43; 32]`. The import destination already has a
legitimate B-lock registration at cursor 36 and the same packed A bytes under
the Type role at cursor 36. Those registrations are destination controls;
neither is exported as A-lock state. A Type has no Type index rows and B query
results remain empty after import.

The fixture manifest is generated from real packed blocks and is not used as
exported state. The tracked compact result is
[`rp2b-evidence-summary.json`](../../experiments/rp2-real-upstream/manifests/rp2b-evidence-summary.json).

## 5. Exact typed seam

The reviewable upstream change is
[`0002-rp2b-typed-script-handoff.patch`](../../patches/rp2/0002-rp2b-typed-script-handoff.patch)
(SHA-256
`D811E5F6E1941A262884DFE2D2C2013216D8BCFB22AB3AD05B30D5AAD08C4F5F`). It
applies cleanly after the RP2-A patch and changes only three upstream paths:

| Path | Added | Purpose |
|---|---:|---|
| `light-client-lib/src/lib.rs` | 3 lines | Test-only `rp2_handoff` module registration. |
| `light-client-lib/src/rp2_handoff.rs` | 369 lines | Typed export/import seam over upstream storage semantics. |
| `light-client-lib/src/tests/rp2_authority_replay.rs` | 562 lines | Same-backend core, continuation, query, control, fingerprint, and adversarial tests. |

There are no production exports: the module is under `cfg(test)` and the
trait is an internal test-build adapter. The patch adds 934 lines, including
the evidence harness; this is materially larger than a one-function seam and
is called out as an experiment-only implementation rather than hidden as a
library refactor.

The temporary API consists of `TypedScriptHandoffStorage::export_typed_script_handoff`
and `import_typed_script_handoff`, plus typed `HandoffRole`,
`ScriptDerivedState`, `HistoricalClosure`, `ScriptProgress`,
`DestinationAuthority`, and `ImportOutcome`. It does not expose arbitrary raw
KV import.

## 6. Exported S/H/P taxonomy

Export requires the exact registered packed Script and role and reads actual
upstream rows:

* **S - Script-derived state:** exact `CellLockScript`/`CellTypeScript` rows
  for the role and exact packed Script; exact `TxLockScript`/`TxTypeScript`
  rows for the same Script and role. The final fixture exported one cell-index
  row and one transaction-index row.
* **H - validated shared historical closure:** the `TxHash` rows referenced
  by those Script indexes, including the upstream row metadata and packed
  transaction. One closure row was exported. This is needed by
  `get_cells`, grouped/ungrouped `get_transactions`, and transaction lookup;
  it is not treated as Script ownership. A transaction containing unrelated
  material would not create unrelated Script indexes.
* **P - typed progress:** per-Script cursor 36, exact handoff height/hash,
  exact genesis hash, exact role, exact packed Script, and format version 1.

The source global `MIN_FILTERED_NUMBER` is not exported as authority. It is
recomputed from the complete destination Script registration set.

## 7. Excluded C/R state and destination rules

The importer rejects any handoff row whose key enters the conservative
authority boundary (prefixes 160, 192, 208, or 224): block-hash rows,
block-number rows, checkpoints, `GENESIS_BLOCK`, `LAST_STATE`,
`LAST_N_HEADERS`, matched-block work, and other chain metadata. Peer state,
proof state, request maps, and chain-selection state are not in the typed
payload. The destination's independently accepted authority is never copied.

Before a write, the importer requires:

1. format version 1;
2. handoff genesis equal to destination authority genesis;
3. exact handoff height and hash equal to the authority receipt;
4. cursor no greater than the verified boundary;
5. destination stored genesis and tip equal to that receipt;
6. unique rows, exact packed Script/role prefixes, valid TxHash closure, and
   complete index-to-closure references;
7. no conflicting destination row and no Script cursor regression.

The source cursor remains a trusted statement from the user's own source. The
destination binds it to independently verified chain facts; it is not a proof
that an arbitrary third party scanned every filter.

## 8. Atomic S/H/P commit

After validation, the seam constructs one real upstream backend batch. The
batch contains the exact A registration, all approved S rows, all validated H
rows, and the newly recomputed global minimum. It is committed once through
the backend's genuine `BatchWriter` implementation. No chain-authority row is
put. Errors occur before commit, so rejected claims leave no durable A rows,
progress, registration, unrelated Script changes, or authority changes.

This is a logical transaction boundary, not a process-kill durability claim;
power-loss recovery is explicitly deferred to RP2-D. Matched-block cleanup is
not transported in this fresh-destination experiment; a non-fresh in-flight
destination needs a separately specified cleanup protocol.

## 9. RocksDB same-backend result

RocksDB source and independent baseline both derived A through the real
authority proof, filter request, filter acceptance, matched-block proof, and
synchronizer path. The import destination independently accepted H=36 before
import and did not receive source `LAST_STATE`, checkpoints, headers, proof
state, peer state, or a copied tip.

The valid import exported/imported one index row and one transaction-index row
with one TxHash closure row. At H, service-level state was equal to the
independent baseline for `get_cells`, grouped and ungrouped
`get_transactions`, and A progress. B-lock and A-Type queries returned no
cells or transactions. The B registration and A-Type control registration
survived; the destination held three registrations after import and
`MIN_FILTERED_NUMBER` was recomputed as 36.

The chain-only authority fingerprint was byte-identical before and after the
import. The full fingerprint changed only in the expected Script/progress
metadata and was stable on exact reimport.

## 10. SQLite same-backend result

SQLite repeated the same topology with independent source, baseline, and
destination storage instances. The same one-index/one-transaction-index/one-
closure export, query equality, negative B/A-Type queries, preserved
registrations, recomputed minimum, unchanged chain-only fingerprint, and
idempotent reimport all passed. No cross-backend serialization was used; this
section is strictly SQLite-to-SQLite.

## 11. Actual replay-request evidence

For each backend, the verifier classified the source and baseline traces as
`NORMAL_FILTERED`:

```text
BASELINE
A registered at 0
-> GetBlockFilters 1..30, accepted with match_count=0
-> GetBlockFilters 31..36, accepted with match_count=1
-> matched block proof and filter_block

IMPORT DESTINATION
independent authority accepted at H=36
-> typed S/H/P import committed
-> no GetBlockFilters request with start <= 36
-> first ordinary request starts at 37, then 39
```

The independent verifier classified both destination traces as
`GENUINELY_NOT_REQUESTED`. It requires the approved-import origin, coherent
coverage bounds, independent query equality, independent authority-fingerprint
evidence, and the absence of any request covering the claimed interval. The
destination JSONL contains starts `37, 39, 37, 39` because the test keeps the
observer session open across the baseline and destination continuation calls;
all starts are after H and none is a replay of 1..36.

## 12. Query-level equivalence at H

The comparison uses the real upstream service layer, not raw row equality. It
compares A live-cell objects, outpoints, data, block numbers, ordering, the
pagination shape used by the fixture, grouped and ungrouped transaction
objects, transaction hashes and inclusion metadata, and the exact A lock
cursor. Source and independent baseline agree at H, and imported destination
equals that baseline on both backends.

Negative service queries prove that B state was not imported and that the same
packed A bytes under the Type role acquired no Type indexes. Raw TxHash closure
is therefore not mistaken for Script ownership.

## 13. Post-H continuation

The continuation appends genuine packed blocks 37..40 to each chain, with an
unmatched 37..38 interval and a matched A output at block 39. The normal
filter scheduler requests 37..38, then 39..40; the matched block is proved,
received by the normal synchronizer, and passed through `filter_block`.

The new A output is the bounded replacement case that the pinned fixture can
validate. An attempted spend of synthetic A `[0x42; 32]` was rejected by the
upstream dummy-PoW validation path (`ScriptNotFound`/`InvalidDAO`), so this
report does not claim a spent-A outpoint or rollback consequence. Both
backends nevertheless converge with the independent baseline for A cells,
transactions, cursor 40, and live continuation semantics.

## 14. Repeated import and unrelated registrations

The exact accepted handoff was imported a second time on each backend. The
result was explicitly idempotent, with no cursor regression, duplicate query
objects, unrelated-state mutation, or chain-authority mutation. The destination
Script set was not replaced wholesale: its pre-existing B lock and same-bytes
A Type registration remained while A lock was added, and the global minimum
was recomputed across all three registrations.

## 15. Real-import adversaries

Each malicious claim was sent to the actual importer, not only to the RP2-A
dry-run validator. Seven cases were rejected independently on each backend:

* wrong handoff hash;
* wrong genesis;
* wrong packed Script;
* wrong role;
* cursor beyond the verified destination height;
* stale/unsupported format version;
* forged closure containing a chain-authority key.

Every rejection emitted `handoff_validation_rejected`; the destination kept an
empty imported Script set, and the before/after full authority fingerprints
were equal. RP2-A's seven negative controls also remained green in the same
runner invocation.

## 16. Evidence artifacts

The final runner is
[`run-rp2b.ps1`](../../experiments/rp2-real-upstream/scripts/run-rp2b.ps1),
which applies/verifies the pinned patches, builds both backends, reruns RP2-A,
runs both RP2-B tests, and invokes the independent verifier. The generated
ignored run directory contains:

* source, baseline, destination, and adversarial JSONL event logs for both
  backends;
* `rp2b-verification.json`;
* `rocksdb-rp2b-core.json` and `sqlite-rp2b-core.json`;
* corresponding adversarial result JSON;
* build evidence with toolchain, Cargo.lock hash, and artifact hashes;
* deterministic fixture manifests.

The compact tracked summary is
[`rp2b-evidence-summary.json`](../../experiments/rp2-real-upstream/manifests/rp2b-evidence-summary.json).
The final verifier result was `passed: true` with no failures. Large generated
databases and binaries are not committed.

## 17. Upstream patch and API accounting

The RP2-A observer remains in
`0001-rp2a-observer-and-negative-controls.patch`; observer changes were not
folded into the RP2-B seam. RP2-B adds only the test-gated module, the typed
storage adapter, and the handoff/continuation tests listed in Section 5.

No public package, schema version negotiation, remote provider, or Pocket Node
integration was added. The seam follows upstream `KeyPrefix`, packed Script,
`ScriptStatus`, `BatchWriter`, and transaction-row semantics rather than
creating a second database schema.

## 18. RP1 assumptions contradicted or narrowed

The experiment narrows rather than upgrades the RP1 claims:

* a source cursor is accepted only as a trusted user-owned statement bound to
  destination chain facts;
* global minimum is destination-derived and cannot be copied from source;
* shared TxHash closure is necessary for service semantics but is not Script
  ownership;
* same-backend success does not imply cross-backend portability;
* the dummy-PoW chain is not mainnet/testnet scale or reorg evidence;
* the seam grew to 369 implementation lines plus 562 test/evidence lines,
  confirming that a typed atomic boundary is a real upstream concern.

The incomplete spent-cell fixture is the only RP2-B matrix gap recorded here;
it must be repaired before claiming the full pass wording.

## 19. Remaining risks and deferred gates

Still unresolved are cross-backend RP2-C, fork/reorg convergence and
process-kill durability RP2-D, realistic G2 scale, Pocket Node G3, concurrent
imports, crash recovery, old/new upstream compatibility, and public package
stability. Trustless completeness and arbitrary third-party snapshot
distribution are outside this trust model.

The H closure is validated for the exercised service paths, not a general
formal proof of all future upstream query dependencies. The event observer is
test-only. The fixture must gain a distinct executable A lock (or an equivalent
real executable test chain) and an actual A spend/replacement before the
spent-cell and rollback portions can be promoted.

This paragraph is preserved as the R0 risk record; the dated R1 section below
documents the executable-lock and spend/replacement repair.

## 20. Exact commands and tests

From the project root:

```powershell
.\experiments\rp2-real-upstream\scripts\run-rp2b.ps1
```

The runner executes, with `--locked` and one test thread:

```text
cargo test --manifest-path light-client-lib/Cargo.toml --no-run --locked
cargo test --manifest-path light-client-lib/Cargo.toml --no-run --no-default-features --features sqlite --locked
cargo test --manifest-path light-client-lib/Cargo.toml rp2a_ -- --test-threads=1 --nocapture
cargo test --manifest-path light-client-lib/Cargo.toml --no-default-features --features sqlite rp2a_ -- --test-threads=1 --nocapture
cargo test --manifest-path light-client-lib/Cargo.toml rp2b_ -- --test-threads=1 --nocapture
cargo test --manifest-path light-client-lib/Cargo.toml --no-default-features --features sqlite rp2b_ -- --test-threads=1 --nocapture
python experiments/rp2-real-upstream/src/rp2a_verifier.py --events-dir experiments/rp2-real-upstream/run/events --output experiments/rp2-real-upstream/run/results/rp2b-verification.json
```

Final RP2-B test counts: RocksDB 2 passed, SQLite 2 passed. Final RP2-A
counts: RocksDB 7 passed, SQLite 7 passed.
These RP2-B counts are the preserved R0 record; R1's final three-case matrix
per backend is reported in Section 23.

## 21. Git and cleanliness records

Project Git remains at the pre-existing commit `f011722` with the new report,
runner, patch, and compact manifest uncommitted for review. The disposable
upstream checkout is dirty only by the expected RP2-A/RP2-B patch application;
its HEAD remains the pinned revision and no upstream commit exists.

The read-only research checkout `grant_find/d2-portability-proof` was checked
after the run: HEAD `bec39d6764e2622139d4f0a93613126f64d4f5a5`, clean. No files
under `grant_find` were modified.

## 22. Original pre-repair recommendation (preserved)

The pre-repair recommendation was to treat the result as **RP2-B PARTIAL - SEAM REPAIR REQUIRED**. Preserve the typed
seam and its evidence because the same-backend zero-replay core is real and
fail-closed. Do not proceed to cross-backend claims yet. First repair the
fixture with an executable, distinct A lock and demonstrate an actual A
spend/replacement plus the resulting spent-cell query semantics. Then rerun
the complete RP2-A/RP2-B matrix from a clean disposable upstream worktree;
only if that closes the missing consequence should the verdict be promoted to
`RP2-B PASS - PROCEED TO RP2-C CROSS-BACKEND`. Section 23 records that repair
and the resulting promotion.

## 23. RP2-B-R1 Spendable Lifecycle Repair (2026-08-31)

### Original blocker and root cause

The pre-repair fixture constructed A as a packed lock Script with code hash
`[0x42; 32]`, empty args, and `hash_type = data`. The dummy-PoW genesis only
contained the upstream `always_success` executable cell; no cell's data hash
was `[0x42; 32]`. `get_cellbase_as_input` supplied the canonical
`always_success` CellDep, not an A-code dependency. A direct spend therefore
failed at the real input-lock stage with:

```text
Verification failed Script(TransactionScriptError {
  source: Inputs[0].Lock,
  cause: ScriptNotFound: code_hash: Byte32(0x4242...4242)
})
```

Thus no executable lock code corresponding to the synthetic A hash existed in
the fixture, and the spend transaction had no valid dependency that could
resolve it.

An intermediate args-only trial using the canonical code exposed a separate
fixture construction issue: changing Script size without recomputing the
hand-built block DAO field produced `InvalidDAO`. Neither failure was caused
by a disabled validator or by dummy PoW alone.

### Replacement fixture

The disposable test utility now derives a second executable fixture cell from
the canonical upstream `always_success` ELF, changing one byte in its
non-loadable `.comment` section. Its code hash is
`0x9d9c7b16af412ae5c3d556bcc061b48ff0e3ba563b1e433e398ff49b516b45e3` and
the packed A lock Script hash is
`0x8a5203dcaa35d0b43c7675af74ff4029d4197a5540fd1f15cfa83ba3a574b9c8`.
The original canonical cell remains in genesis for the block assembler and
cellbase inputs. A's code CellDep is found from the real genesis transaction;
no validator bypass or arbitrary code hash was added. A and B remain distinct
Scripts, and the same A bytes under the Type role remains a negative control.
This always-success code is disposable fixture infrastructure, not a
production security primitive.

The repaired run's pinned authority checkpoints are genesis
`0xc117b5518c0522988f761f61e6edcb2c59ea6c8e2d787e411c3ee8f5b3794f5b`,
handoff height `H = 36`, and handoff hash
`0x0c75246f78f2ed60addf83fed18856de55deac420509f2766540ab01a35458b5`.

The handoff seam (`0002-rp2b-typed-script-handoff.patch`) is unchanged. The
fixture/test-only changes are isolated in
[`0003-rp2b-spendable-fixture.patch`](../../patches/rp2/0003-rp2b-spendable-fixture.patch).
The recorded SHA-256 values are `D811E5F6E1941A262884DFE2D2C2013216D8BCFB22AB3AD05B30D5AAD08C4F5F`
for `0002` and `23C933F7FBC7969A136D467279D1EFBED222566DD51C879613ABC70974591607`
for `0003`.
Patch `0003` modifies only `light-client-lib/src/tests/rp2_authority_replay.rs`
(439 additions, 44 deletions) and `light-client-lib/src/tests/utils/chain.rs`
(36 additions, 1 deletion). There is no handoff-seam diff beyond `0002`.

### L1: spend before handoff

Each independent source/baseline fixture now creates A0 at block 31, spends
A0 at block 34 through a valid A-code CellDep, and leaves A1 live at H=36.
The baseline's real filter trace requests 1..30 (no match), then block 31 and
32..36 in normal matched-block batches. Its service state contains no A0 and
does contain A1. The source export carries the actual post-spend Script rows
and three transaction-index rows plus two TxHash closure rows; no expected rows
are fabricated.

### L2: spend an imported live cell after H

After independent destination authority reaches H and the typed A handoff is
atomically committed, A1 is live in the destination query. Blocks 37..38 are
an unmatched interval. Block 39 contains a real transaction consuming A1
with the executable A CellDep and creating lower-capacity A2; block 40 closes
the interval. The destination receives these through filter response, proof,
matched-block retrieval, `SyncProtocol`, and upstream `filter_block`.

At both backends, A1 disappears from `get_cells`, A2 appears with the expected
outpoint/capacity/lock, and grouped/ungrouped `get_transactions` agree with
the independent baseline. The low-level diagnostic export shows the live A
index row's value changing from A1's transaction hash to A2's while the row
count remains one; it is corroborating evidence, not the semantic oracle.

### Evidence and regression results

The compact results in `rp2b-evidence-summary.json` and the ignored run
artifacts record, for both backends:

* `spendable_fixture_valid = true`;
* A0 created and spent before H; A1 live at handoff;
* A1 spent post-H; A2 live afterward;
* baseline/imported live-cell and transaction semantics equivalent;
* exact progress 40 after continuation;
* no request at or below H on the imported destination, with first normal
  request at 37 and post-H match at 39;
* authority fingerprint unchanged across import;
* repeated import idempotent and unrelated B/A-Type registrations preserved;
* all seven prior real-import adversaries rejected per backend;
* spend negatives: missing A CellDep rejected with `ScriptNotFound`, spent A0
  outpoint rejected with `Resolve failed Unknown`, and a B-locked replacement
  recorded as accepted-but-not-A without changing chain tip or A replacement
  semantics.

The real-import `forged_chain_closure` case specifically attempts to place a
chain-authority (C) row inside the claimed H closure; it is rejected before
any write, alongside the wrong-hash/genesis/Script/role/cursor/version cases.

RocksDB and SQLite each pass RP2-A (7/7), the RP2-B core (1/1), the real
import adversaries (1/1), and the spend-negative test (1/1). The independent
verifier passes with no failures. No source chain authority is imported.

### Revised verdict

The repaired experiment now proves the required lifecycle on both genuine
backends:

```text
created A0 -> indexed -> spent before H -> A1 handed off live
-> spent after H by ordinary upstream processing -> A1 removed
-> A2 indexed -> baseline converged
```

Therefore the revised result is **RP2-B PASS - PROCEED TO RP2-C
CROSS-BACKEND**. This remains trusted-source self-portability only; RP2-C,
RP2-D, scale, Pocket Node, public package stability, and trustless
completeness remain out of scope.
