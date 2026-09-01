# D2-RP2D: Reorg + Crash Correctness Gate

Date: 2026-08-31  
Pinned upstream: `nervosnetwork/ckb-light-client` at `12e29522ab7e078ada704d4ac04cbc0498009b7b`

## 1. Verdict

`RP2-D CONDITIONAL PASS — SMALL SAFETY SEAM REQUIRED BEFORE PDEF1`

The primary shallow-fork proof and the durable S/H/P crash matrix pass on both genuine backends and both cross-backend directions. The gate is not promoted to a full PASS because the experiment does not yet enforce offline/exclusive import, does not test two simultaneous imports, does not test valid-artifact removal after validation, and C7 kills immediately before `batch.commit()` rather than from inside the storage engine’s commit implementation.

## 2. Executive finding

An imported A view behaves as ordinary light-client state under a real competing chain. At `H=36`, a fork at `F=33` was selected through `LightClientProtocol`; the normal upstream rollback removed the old A consequence, reset filtering to the fork boundary, and normal `FilterProtocol`/`SyncProtocol` processing indexed the winning replacement. The imported destination matched an independently derived baseline for SQLite and RocksDB.

Twenty real child-process abort cases (C0–C9 for each backend), including cross-backend artifacts, reopened as either the complete old state or complete new state. The independent persisted-state verifier classified all 20 coherently and found no authority mutation. The remaining work is a bounded lifecycle/commit-boundary safety seam, not a change to the typed handoff model.

## 3. Starting checkpoints

- Project HEAD at the RP2-D checkpoint: `f0117229a6cb684c76bb46b32a40b80ae7c39ff4`.
- Upstream HEAD remained detached at `12e29522ab7e078ada704d4ac04cbc0498009b7b`.
- `Cargo.lock` SHA-256: `F3A18D999A89519024B44B702C1637C571217CEB8D06CD7E39126E8D22EAE890`.
- Toolchain: `rustc 1.96.0 (ac68faa20 2026-05-25)`, `cargo 1.96.0 (30a34c682 2026-05-25)`.
- Accepted patch hashes: 0002 `D811E5F6…08C4F5F`, 0003 `23C933F7…4591607`, 0004 `8C0B8F9D…941EDDC7`.
- Final D-only patch hash: 0005 `5EF44FE5EC25965742707E04E98229BB4C9A785D5EBE19E394486E3652E4E5A3`.
- Starting checkpoint: `experiments/rp2-real-upstream/manifests/rp2d-starting-checkpoint.json`.

The project worktree is intentionally dirty with the RP2 experiment patches, runners, manifests, and audit reports; no unrelated source change was introduced.

## 4. Previous gate reproduction

`run-rp2d.ps1` first invokes the accepted RP2-C runner, which invokes the accepted RP2-B runner and RP2-A verifier. The final run reproduced RP2-A, RP2-B, and RP2-C successfully on RocksDB and SQLite. Both RP2-C directions and the prior 22 cross-backend adversarial cases remained green before D-only cases ran.

## 5. RP2-D changes

The disposable pinned upstream received only `0005-rp2d-reorg-crash-test.patch`. Project-side changes are the dedicated runner, reorg comparator, persisted-state verifier, patch-application helper, ignored generated run roots, and this report. The typed handoff semantics in 0002, spendable fixture in 0003, and cross-backend transport in 0004 were not edited.

## 6. Reorg fixture

The accepted spendable always-success fixture is extended from the common chain through height 36. The old branch has live A1 at H. A remote fixture is used only to construct a competing chain: it is rewound to 33, cleared of detached transaction-pool entries, given a distinct valid A replacement, and mined to height 38. The destination never receives the remote database or tip.

## 7. Old/winning branch semantics

Old branch: A0 was spent before H and A1 is live at H. Winning branch: the old post-fork consequences are detached and a distinct A2R output is created on the replacement branch. The final service state therefore distinguishes stale old A1 from the winning replacement; equal final rows could not accidentally satisfy the test.

## 8. Real upstream rollback path exercised

The destination receives a real `SendLastStateProof` through `LightClientProtocol`. The proof contains the winning branch’s retained headers and MMR proof. Upstream `commit_prove_state` identifies the common header, invokes native `rollback_to_block`, clears matched-block state, updates chain authority, and then the normal filter/synchronizer path requests and processes the winning range. The driver calls `rollback_to` only while constructing the isolated remote fixture branch; it never calls destination storage rollback as the proof.

## 9. RocksDB → SQLite reorg result

Case `c1-rocksdb-to-sqlite` passed. The SQLite import destination selected the proof, rolled back at 33, requested from 34, removed old A1, indexed A2R, and reached progress 38. Its service state and outpoint matched the independent SQLite baseline.

## 10. SQLite → RocksDB reorg result

Case `c2-sqlite-to-rocksdb` passed with the same checks and values. The RocksDB destination independently established old-chain authority, accepted the SQLite-produced typed state, and later converged with the independently derived RocksDB winning-chain baseline.

## 11. Same-backend controls

`s1-rocksdb-to-rocksdb` and `s2-sqlite-to-sqlite` both passed the same comparator. These controls separate rollback behavior from interchange translation and show that neither native backend requires D2-specific cleanup.

## 12. Deeper-fork control

Both backends attempted a deterministic fork at 20 to height 38. The upstream fixture rejected construction at block 21 (`failed to process block 21`); no protocol selection or authority mutation followed. Both cases are recorded as `UPSTREAM_LIMIT_OR_REJECTED`, not as primary reorg passes. This is an upstream retention/fixture limitation and was not bypassed with direct destination rollback.

## 13. Losing-fork rejection

Two cases (one per cross-backend direction) presented the old-branch artifact after the destination had established the winning chain. Both were rejected with `authority_validation_rejected`; S/P and chain-authority fingerprints were unchanged.

## 14. Post-reorg query convergence

The independent comparator passed all 13 checks for C1, C2, and both same-backend controls. Service-level checks covered live cells/outpoints, output/data and state ordering, transaction relationships, progress, old A1 absence, winning A2R presence, and authority preservation. Raw native rows were retained only as diagnostics.

## 15. Post-reorg progress/replay behavior

The imported interval through H remained zero-replay evidence. Reorg recovery legitimately reprocessed only the invalidated interval: both baseline and imported destinations requested starting at 34, accepted 34–35 as unmatched, accepted 36–38 with the winning match, and ended at progress 38. This is normal reorg replay, not a violation of RP2-B’s pre-H zero-replay claim.

## 16. Import transaction boundary

Artifact open/decode and digest/canonical validation occur in the worker before the typed importer call. Inside `import_typed_script_handoff`, format, Script/role, genesis/hash/height, cursor, authority-prefix exclusion, current registration state, and global-min recomputation are validated before one native backend batch is built. S rows, H closure rows, A registration/P, and recomputed `MIN_FILTERED_NUMBER` are written to that batch and committed together. No C/R rows are included. Post-commit result reporting is outside the batch. There is no artifact completion journal.

## 17. Crash failpoint design

The test-only failpoints are C0 before artifact open/decode, C1 after validation, C2 after batch creation, C3 before S writes, C4 after S/H writes, C5 after P, C6 after global-min write, C7 immediately before `batch.commit()`, C8 after commit, and C9 after success. C0–C9 terminate the child with `std::process::abort`, not a returned error. C7 is intentionally reported as a pre-commit controlled kill; an in-engine kill was not claimed.

## 18. RocksDB crash matrix

All ten RocksDB cases passed. C0–C7 reopened `OLD_COMPLETE`; C8–C9 reopened `NEW_COMPLETE`. Every child exit was non-zero (`-1073740791` on Windows), every reopen exited 0, and every retry exited 0. The destination consumed the SQLite-produced artifact, demonstrating that crash behavior belongs to destination persistence rather than source backend.

## 19. SQLite crash matrix

All ten SQLite cases passed with the same classification split and exit/reopen/retry behavior. The destination consumed the RocksDB-produced artifact. SQLite used the native upstream SQLite storage configuration; no durability setting was silently changed for the experiment.

## 20. Cross-backend crash artifact results

C1’s RocksDB artifact was used for SQLite crash destinations; C2’s SQLite artifact was used for RocksDB crash destinations. The 20-row matrix records `source_artifact_backend` separately and the independent consistency verifier checked all rows.

## 21. Retry/recovery results

After every C0–C7 old-state reopen, retrying the exact artifact completed the import. After C8–C9 new-state reopen, retrying was idempotent. No cursor regression, duplicate semantic state, unrelated registration loss, or authority change was observed.

## 22. Unrelated Script safety

Each crash destination was initialized with B lock and A type registrations before import. Old-state reopen retained exactly those two registrations; new-state reopen retained them and added A lock (three total). `MIN_FILTERED_NUMBER` remained 36 in both coherent states. The reorg/import comparators likewise passed unrelated-script preservation.

## 23. Authority safety

The import comparator found destination chain authority unchanged across the handoff. Crash workers persisted a pre-import authority fingerprint; fresh reopen workers returned the post-crash fingerprint. The independent consistency verifier compared the fingerprints for all 20 rows and passed. Normal proof progression during the reorg is kept separate from import-induced mutation.

## 24. Offline/concurrency boundary

The current seam is a storage-level typed method and does not enforce an offline/exclusive client lifecycle. No live-filter/import race or two-process simultaneous import was run as a supported operation. This is an explicit bounded gap, not an assumed pass: PDEF1 must add an enforceable exclusive lifecycle guard (or explicitly keep the API unavailable while workers are active) before scope freeze.

## 25. Consistency-verifier results

`experiments/rp2-real-upstream/src/rp2d_consistency_verifier.py` independently classified the 20 fresh-process reopen observations. It checked coherent OLD/NEW relationships between A registration, live A1/S state, H-dependent state, P, unrelated registrations, authority fingerprints, crash exit, and retry. Result: `checked=20`, `passed=true`, `failures=[]`. No `TORN_INVALID`, `AUTHORITY_MUTATED`, or unrelated-state failure occurred.

## 26. Exact patches/files changed

- Upstream D-only patch: `patches/rp2/0005-rp2d-reorg-crash-test.patch` (1000+ test-only lines plus persistent test-fixture/failpoint support; `git apply --check` passes).
- Runner: `experiments/rp2-real-upstream/scripts/run-rp2d.ps1`.
- Patch helper: `experiments/rp2-real-upstream/scripts/apply-rp2d-upstream-patches.ps1`.
- Reorg comparator: `experiments/rp2-real-upstream/src/compare_rp2d.py`.
- Persisted-state verifier: `experiments/rp2-real-upstream/src/rp2d_consistency_verifier.py`.
- Evidence: `experiments/rp2-real-upstream/manifests/rp2d-starting-checkpoint.json`, `rp2d-evidence-summary.json`, and ignored generated `run-rp2d` logs/results.
- Upstream files touched by 0005: `light-client-lib/src/tests/utils/chain.rs`, `light-client-lib/src/rp2_handoff.rs`, and `light-client-lib/src/tests/rp2_authority_replay.rs`.

## 27. Whether `0002` changed

No. SHA-256 remains `D811E5F6E1941A262884DFE2D2C2013216D8BCFB22AB3AD05B30D5AAD08C4F5F`.

## 28. Whether `0003` changed

No. SHA-256 remains `23C933F7FBC7969A136D467279D1EFBED222566DD51C879613ABC70974591607`.

## 29. Whether `0004` changed

No. SHA-256 remains `8C0B8F9D60CE54647B9C99E372E2B51E833CEF1B57AF4C2B0F789316941EDDC7`.

## 30. Any new semantic seam required

No new S/H/P, chain-binding, progress, backend-neutral transport, or rollback semantic seam was required. The required follow-up is operational: enforce offline/exclusive import, define artifact lifecycle handling around validation/commit, and provide a deterministic commit-internal crash harness or journal if PDEF1 requires that stronger claim.

## 31. Remaining core risks

- C7 does not kill inside RocksDB/SQLite engine commit.
- Valid-artifact removal after validation (A5) is not exercised; the current API receives a decoded typed object and has no artifact lifecycle journal.
- Concurrent/live import is not supported or enforceably rejected.
- Deeper-than-retained-header rollback remains an upstream limitation.
- Process-kill evidence is Windows-specific and does not model power loss or filesystem corruption.
- Reorg/crash work does not claim fork safety beyond the tested upstream path, nor realistic-scale performance.

## 32. Test commands/results

From the project root:

```powershell
$env:CXXFLAGS='-D_WIN32_WINNT=0x0602'
.\experiments\rp2-real-upstream\scripts\run-rp2d.ps1
```

The runner verifies the pin, reruns RP2-A/B/C, builds feature-specific RocksDB/SQLite workers, runs C1/C2 and same-backend reorg controls, records the deeper-fork and losing-artifact controls, executes both ten-stage crash matrices, invokes both independent verifiers, and emits the manifest. Final result: RP2-A/B/C green; reorg comparisons 4/4 green; losing-fork rejection 2/2; crash matrix 20/20; consistency verifier 20/20; event verifier passed.

## 33. Project commit/status

Project HEAD remains `f0117229a6cb684c76bb46b32a40b80ae7c39ff4`. The worktree is dirty only with the expected RP2 patches, scripts, manifests, reports, and `.gitignore` experiment-root rule. No project commit was fabricated by this experiment. The upstream worktree is pinned and intentionally dirty with the applied disposable patches.

## 34. `grant_find` cleanliness

Research reference `C:\Users\timot\Desktop\2026\CKB\grant_find\d2-portability-proof` remains clean at `bec39d6764e2622139d4f0a93613126f64d4f5a5`. No research-reference file was modified.

## 35. Final recommendation

`RP2-D CONDITIONAL PASS — SMALL SAFETY SEAM REQUIRED BEFORE PDEF1`

Do not begin PDEF1 scope freeze yet. First add and rerun the bounded safety seam for exclusive/offline lifecycle, artifact validation-to-commit handling, and commit-internal crash coverage. The tested D2 semantic core itself remains credible: imported state rolls back as ordinary upstream state and native backend transactions preserve coherent old-or-new S/H/P state under the exercised interruptions.

---

## RP2-D-R1 FINAL SAFETY SEAM CLOSURE

Captured 2026-09-01 against project HEAD `f0117229a6cb684c76bb46b32a40b80ae7c39ff4`, pinned upstream `12e29522ab7e078ada704d4ac04cbc0498009b7b`, Rust/Cargo `1.96.0`, and the existing RP2-A/B/C/D patch stack. The unchanged conditional runner reproduced RP2-A/B/C, reorg convergence 4/4, losing-fork rejection 2/2, the 20-row crash matrix, and the independent persisted-state verifier before the R1 cases were run.

### 1. Previous blocker and selected lifecycle architecture

The conditional result left three operational gaps: the storage seam assumed offline use but did not enforce it, artifact lifetime after validation was unspecified, and C7 killed immediately before (rather than observing) the native commit call. R1 adds a test-only `ImportLifecycle` shared by Storage instances for a database path, with RAII `ProtocolActivityGuard` and `OfflineImportGuard`. Protocol/filter/synchronizer/relayer activity increments the worker count; import acquisition is rejected while any worker is active or another import owns the guard. This makes the supported operation an exclusive offline transition without adding a distributed-locking or live-import mode.

### 2. Live and concurrent import controls

On both RocksDB and SQLite, `live-reject` rejected a valid import before any registration, S/H/P, minimum, authority, or unrelated-Script mutation; dropping the active protocol and retrying succeeded. SI-1 ran two identical imports concurrently: one committed, the other received the busy rejection, and a retry was idempotent. SI-2 used a conflicting lower-progress handoff: it was rejected after the winner and the fresh persisted-state verifier found one coherent state. All eight safety cases are recorded in [`safety-evidence.json`](../../experiments/rp2-real-upstream/run-rp2d-r1/results/safety-evidence.json), with `safety_checked=8`, no failures, unchanged authority, and preserved unrelated registrations.

### 3. Artifact validation-to-commit lifetime

The importer receives a complete owned immutable decoded `TypedScriptHandoff`; it does not reopen the original path. The artifact-remove and artifact-replace cases deleted/renamed or replaced the source path after validation and before the offline import call. Both backends imported the originally validated digest successfully, with the expected one Script-index row and three transaction-closure rows. No artifact journal or production package schema was introduced.

### 4. Commit-edge observability and process termination

Test-only markers are flushed to a parent-visible signal file immediately before `db.write` (RocksDB) or `tx.commit` (SQLite), and only after the native call returns. The parent-child harness performs four controlled termination attempts per destination backend, records `commit_enter`, `commit_exit`, exit code, kill timing, fresh reopen classification, and retry. All 8/8 attempts observed `commit_enter`, terminated the child (`exit=-1`), reopened as `NEW_COMPLETE`, and retried successfully; the observed samples landed after `commit_exit` because these native commits completed within the polling interval. No trial was counted without `commit_enter`, and no native engine was patched. The independent verifier classified every row as OLD_COMPLETE or NEW_COMPLETE with zero `TORN_INVALID`, `AUTHORITY_MUTATED`, mixed-state, or unreopenable results. Evidence is in [`commit-race.json`](../../experiments/rp2-real-upstream/run-rp2d-r1/results/commit-race.json) and [`rp2d-r1-consistency-verification.json`](../../experiments/rp2-real-upstream/run-rp2d-r1/results/rp2d-r1-consistency-verification.json).

### 5. Authority, unrelated state, and reorg regression

Every safety case retained the destination authority fingerprint across import, preserved B/A-type/unrelated Script registrations, and recomputed global minimum locally. The unchanged primary reorg matrix was rerun after the seam: 4/4 convergence and 2/2 losing-fork rejection remained green, with ordinary rollback of imported state and no D2-specific cleanup.

### 6. Patch and source discipline

The semantic handoff patches remain unchanged byte-for-byte: `0002` (`D811E5F6E1941A262884DFE2D2C2013216D8BCFB22AB3AD05B30D5AAD08C4F5F`), `0003` (`23C933F7FBC7969A136D467279D1EFBED222566DD51C879613ABC70974591607`), and `0004` (`8C0B8F9D60CE54647B9C99E372E2B51E833CEF1B57AF4C2B0F789316941EDDC7`). `0005` is also unchanged (`5EF44FE5EC25965742707E04E98229BB4C9A785D5EBE19E394486E3652E4E5A3`). New `0006-rp2d-exclusive-import-safety-seam.patch` carries the focused lifecycle/RAII safety changes (13 upstream files, 435 additions and 7 removals relative to the disposable RP2-C base); `0007-rp2d-commit-edge-observability.patch` carries the test-only commit-edge/worker evidence additions. No S/H/P, chain binding, progress, backend-neutral transport, or rollback semantic change was required.

### 7. Earned operational contract and limits

The supported D2 operation is an exclusive offline import: normal protocol workers must be quiescent, one importer owns validation-to-commit, and the validated handoff is an owned immutable typed object before the native transaction. S/H/P plus destination-local scheduler state commit through one backend transaction. Termination around the supported commit boundary reopened as complete-old or complete-new state in the exercised native backends, and retries were safe. This is not a power-loss/filesystem-corruption proof, does not claim a kill inside native engine code, and does not add reorg-specific cleanup, public package stability, trustless completeness, or scale claims.

### 8. Reproducibility and final verdict

Use [`run-rp2d-r1.ps1`](../../experiments/rp2-real-upstream/scripts/run-rp2d-r1.ps1) from the project root. It first invokes the unchanged `run-rp2d.ps1`, then rebuilds/uses feature-specific workers, runs live/concurrent/artifact/commit-edge cases, both independent verifiers, and the reorg regression. The structured result is [`rp2d-r1-evidence-summary.json`](../../experiments/rp2-real-upstream/manifests/rp2d-r1-evidence-summary.json); the last completed R1 run reports `passed=true`, `safety_checked=8`, `commit_race_checked=8`, and no verifier failures. The research reference `grant_find` remains unchanged.

**RP2-D PASS — PROCEED TO PDEF1 SCOPE FREEZE**

This promotion is contingent on committing the reproducible project checkpoint with generated databases/logs ignored and a clean working tree. No PDEF1 work has begun.

### 9. Final project checkpoint

The accepted RP2 artifacts were committed as project commit `11a3a5893a8363934e9a3a8c2f3db64c33f1a409`. The post-checkpoint R1 rerun updated the manifest to that commit and reported a clean project tree, `RP2-D PASS — PROCEED TO PDEF1 SCOPE FREEZE`, `commit_race_checked=8`, and zero verifier failures. The generated `run-*` databases, logs, event streams, and build workspaces remain ignored; `grant_find` is unchanged.
