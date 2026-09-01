# D2-RP2C - Cross-Backend Semantic Portability Report

## 1. Verdict

**RP2-C PASS - PROCEED TO RP2-D REORG + CRASH**

Both directions passed on separate feature-specific upstream test binaries:

* C1: RocksDB source -> SQLite destination;
* C2: SQLite source -> RocksDB destination.

The accepted RP2-B typed seam (`0002`) and spendable fixture (`0003`) were not
changed. A bounded, test-only experimental transport patch (`0004`) serializes
the already-accepted typed handoff; it does not define a production package
format. The destination established chain authority independently, imported
only typed Script state/closure/progress, made no authority transition during
import, requested no historical A range through H, and then spent the imported
live cell through ordinary upstream filtering and synchronization.

This remains an experiment in trusted-source self-portability. It does not
prove trustless completeness, public snapshot distribution, reorg safety,
crash durability, realistic scale, or Pocket Node integration.

## 2. Checkpoints and cleanliness

| Item | Value |
|---|---|
| Project | `ckb-script-port` |
| Project HEAD | `f0117229a6cb684c76bb46b32a40b80ae7c39ff4` |
| Upstream | `nervosnetwork/ckb-light-client` |
| Pinned upstream | `12e29522ab7e078ada704d4ac04cbc0498009b7b` |
| Handoff height | 36 |
| Handoff hash | `0x0c75246f78f2ed60addf83fed18856de55deac420509f2766540ab01a35458b5` |
| Genesis | `0xc117b5518c0522988f761f61e6edcb2c59ea6c8e2d787e411c3ee8f5b3794f5b` |
| A lock Script hash | `0x8a5203dcaa35d0b43c7675af74ff4029d4197a5540fd1f15cfa83ba3a574b9c8` |
| Artifact | `rp2-cross-backend-fixture-v1` |
| Artifact digest (C1/C2) | `0xc9b3d3387b9f4cf8c7680edb9d672bec30449d5553808d82f93d55158d509544` |

The upstream worktree remained detached at the pinned revision. The project
status contains only the expected experiment reports, manifests, runners, and
patches; no project or upstream commit was created. The read-only
`grant_find/d2-portability-proof` checkout was clean at
`bec39d6764e2622139d4f0a93613126f64d4f5a5`.

## 3. Accepted-gate reproduction

`run-rp2c.ps1` first invoked the unchanged RP2-B runner. The pinned
RP2-A/RP2-B measuring instrument remained green:

| Backend | RP2-A | RP2-B | Independent verifier |
|---|---:|---:|---|
| RocksDB | 7 passed | 3 passed | pass |
| SQLite | 7 passed | 3 passed | pass |

The RP2-C run verifier classified 30 event traces as 4 `NORMAL_FILTERED`, 4
`GENUINELY_NOT_REQUESTED`, and 22 `AUTHORITY_INVALID`, with zero failures.

## 4. Experimental interchange representation

`0004` adds a test-only worker and a deliberately named experimental wire
representation. The envelope contains:

* format version, pinned upstream revision, diagnostic source backend/process;
* canonical payload bytes and a CKB blake2b-256 payload digest.

The payload contains only the accepted typed object: exact packed Script,
`lock` role, S index rows, validated H transaction closure rows, and P cursor,
handoff height/hash, and genesis hash. Rows are sorted by exact key bytes and
the decoder strictly rejects unknown fields, non-canonical hex, duplicate or
out-of-order rows, malformed packed values, truncation, digest mismatch,
version mismatch, and size overflow. Re-encoding must byte-match the payload.

The source backend never emits destination-specific keys. The destination
decodes typed values and calls the same upstream typed importer, whose native
writer persists RocksDB or SQLite rows. The source backend field is diagnostic:
the tampered-backend control was accepted and produced equivalent destination
semantics in both directions.

## 5. S/H/P and excluded state

The exported handoff contained one Script index row, one transaction-index row,
and three validated transaction closure rows in the fixture. The destination
recomputed its global minimum locally (36) across its complete registration
set. No source global minimum was transported as authority.

The artifact contained no `LAST_STATE`, checkpoints, header windows, proof
state, matched-block work, peer state, chain-selection state, or other C/R
rows. Destination authority was established before decoding/import through the
real light-client last-state proof path. The chain-only authority fingerprint
event was `unchanged: true` before versus after each import; the full
fingerprint is allowed to change for the newly installed Script/progress rows.

## 6. C1 - RocksDB source to SQLite destination

The RocksDB source process `c1-rocksdb-to-sqlite-source-rocksdb` derived A
normally through filter requests 1..30, 31, and 32..36, matched-block proof,
synchronizer, and `filter_block`. `c1-rocksdb-to-sqlite-baseline` was a fresh
SQLite client that independently derived the same history. The SQLite import
process independently established H=36, decoded the RocksDB artifact, and
committed S/H/P atomically.

At H, imported SQLite service results exactly matched the independent SQLite
baseline for `get_cells`, grouped and ungrouped `get_transactions`, ordering
and pagination shape exercised by the fixture, and Script progress. A0 was
absent and A1 was live. B-lock and same-bytes A-Type controls remained negative.

After import, SQLite requested only 37..38 and 39..40. The real block 39 path
spent A1 and indexed A2; progress advanced from 36 to 40 and the service state
matched the SQLite baseline after continuation. The exact handoff was accepted
again idempotently without cursor regression or authority mutation.

## 7. C2 - SQLite source to RocksDB destination

The reverse topology used independent process IDs
`c2-sqlite-to-rocksdb-source-sqlite`, `c2-sqlite-to-rocksdb-baseline`, and
`c2-sqlite-to-rocksdb-import-rocksdb`. SQLite source extraction produced the
same canonical artifact digest. RocksDB independently established authority,
decoded the SQLite-produced typed payload, and persisted it through the native
RocksDB writer.

The H=36 and post-continuation service comparisons were exact: A0 was already
spent, A1 was live at the boundary, A1 disappeared only after the genuine
post-H spend, and A2 became live. Progress converged at 36 and then 40. B/A-Type
negative queries, unrelated registration state, idempotent reimport, and the
chain-only authority fingerprint invariant all passed.

## 8. Replay evidence

The independent RP2-A verifier observed normal historical work for every source
and baseline trace:

```text
BASELINE / SOURCE
  request 1..30 -> accepted, no match
  request 31 -> accepted, match
  request 32..36 -> accepted, match classification as recorded

IMPORT DESTINATION
  independently accepted chain authority at H=36
  typed S/H/P import committed
  no request with start <= 36
  first ordinary request starts at 37, then 39
```

Both C1 and C2 import traces (including the tampered-backend positive control)
were classified `GENUINELY_NOT_REQUESTED`. The verifier rejected any trace that
requested a range through the claimed coverage, used direct cursor/minimum or
authority mutation, or lacked independent authority/query evidence. Post-H
requests are continuation, not replay.

## 9. Query and spend lifecycle

The destination-backend baseline is the oracle; raw RocksDB/SQLite file or KV
equality is not a criterion. Both directions passed:

`A0 created -> spent before H -> absent at H; A1 live at H -> imported -> spent
by block 39 -> absent; A2 replacement -> live and indexed; transaction history
and progress converge.`

The exact outpoints and service objects are recorded in each comparison JSON and
the tracked summary. The replacement output, data, block metadata, transaction
relationships, grouped/ungrouped history, and cursor all matched the
destination-backend baseline.

## 10. Global minimum and unrelated Script controls

Each import destination first registered B under its lock role and the exact A
bytes under the Type role. The importer added A lock without replacing the
Script set. B remained registered with its progress and no imported B indexes;
the A-Type control remained without Type indexes. The destination recomputed
`MIN_FILTERED_NUMBER` locally as 36. The source backend's global scheduler
state was never transported.

## 11. Idempotence and authority

Each valid artifact was imported twice. The second operation returned the
upstream seam's explicit idempotent result. There was no duplicate query state,
cursor regression, unrelated Script mutation, or C-only authority change.
The full fingerprint changes as expected when S/H/P and registration rows are
installed; the protected chain-authority fingerprint is unchanged for the
import transition.

## 12. Artifact and semantic adversaries

For each direction, the real destination importer rejected all 11 artifact
adversaries before durable state:

| Adversary | Result |
|---|---|
| truncated | rejected during strict envelope decode |
| digest mismatch | rejected before payload use |
| duplicate item | rejected by strict row ordering |
| wrong/unknown version | rejected |
| reordered content | rejected as non-canonical |
| wrong genesis | rejected against destination authority |
| wrong handoff hash | rejected against destination authority |
| wrong Script | rejected by exact Script binding |
| wrong role | rejected by exact role prefix |
| cursor beyond boundary | rejected by handoff identity/boundary validation |
| forged C-state row | rejected as invalid/non-typed closure |

That is 22 real destination-process rejections with unchanged authority and no
destination Script registration. The unchanged RP2-A/RP2-B semantic controls
also remained green, including rows-only, direct cursor/minimum, wrong chain,
and attempted authority import. A source-backend metadata tamper was a positive
control: because that field is non-authoritative, it did not change semantics.

## 13. Physical-storage diagnostics

The native destination writer produced backend-specific physical rows from the
same typed values. The diagnostic imported counts were S=1 index row and H=3
transaction closure rows in both directions. Service behavior, not raw row
layout, was the portability oracle. No database file, dump, file copy, or
source backend key was used.

## 14. Patch and API discipline

`0002` and `0003` are byte-for-byte unchanged:

* `0002` SHA-256:
  `D811E5F6E1941A262884DFE2D2C2013216D8BCFB22AB3AD05B30D5AAD08C4F5F`;
* `0003` SHA-256:
  `23C933F7FBC7969A136D467279D1EFBED222566DD51C879613ABC70974591607`.

New patch:

* `patches/rp2/0004-rp2c-cross-backend-transport.patch`;
* SHA-256 `8C0B8F9D60CE54647B9C99E372E2B51E833CEF1B57AF4C2B0F789316941EDDC7`;
* one test file, 566 additions and one context deletion relative to the
  accepted A/B/C worktree;
* upstream path: `light-client-lib/src/tests/rp2_authority_replay.rs`.

The new code is test-only experimental transport/orchestration. It introduces
no public package API and no production storage schema. Project-side files are
`apply-rp2c-upstream-patches.ps1`, `run-rp2c.ps1`, `compare_rp2c.py`, this
report, the starting checkpoint, and `rp2c-evidence-summary.json`.

## 15. Commands and evidence

From the project root:

```powershell
.\experiments\rp2-real-upstream\scripts\run-rp2c.ps1
```

The runner verifies the pinned revision, invokes `run-rp2b.ps1`, applies/checks
`0004`, builds distinct RocksDB and SQLite feature targets, runs C1/C2 source,
baseline, import, tampered-backend, and 22 negative workers, then runs the
independent verifier and comparator.

Tracked deterministic evidence:

* [`rp2c-evidence-summary.json`](../../experiments/rp2-real-upstream/manifests/rp2c-evidence-summary.json)
* [`rp2c-starting-checkpoint.json`](../../experiments/rp2-real-upstream/manifests/rp2c-starting-checkpoint.json)
* [`0004-rp2c-cross-backend-transport.patch`](../../patches/rp2/0004-rp2c-cross-backend-transport.patch)

The generated run databases, event logs, process logs, and binaries remain in
the ignored disposable RP2-C run root; the summary records process IDs,
feature-specific commands, artifact digests, classifications, results, and
adversarial reasons.

## 16. Remaining risks and explicit non-goals

RP2-D remains necessary for fork/reorg convergence, rollback of imported state,
process-kill and power-loss durability, crash points, and concurrency. RP2-C
does not establish cross-version compatibility, production schema stability,
trustless completeness, public distribution, G2 scale, or Pocket Node support.

## 17. Recommendation

The two genuine native backends consumed the same backend-neutral typed Script
view/progress artifact under independently established authority and converged
through a real post-handoff spend. The cross-backend portability claim is
therefore accepted for this bounded fixture and pinned upstream experiment.

Proceed to RP2-D reorg and crash work without changing the accepted `0002`
handoff semantics.
