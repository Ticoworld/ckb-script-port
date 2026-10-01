# D2 Final Core Proof — 2026-10-01

**Status:** Core proof complete for this stage; freeze feature work pending upstream review.

**Scope:** Exact-Script state handoff between CKB light-client SQLite stores. This report does not claim a full wallet/device migration, cross-version portability, production adoption, user demand, or universal performance improvement.

## Executive result

D2 selectively transferred one exact lock Script from an iBytes Rust/SQLite source into a fresh iBytes client store. The source and destination independently authenticated the handoff boundary using the light client's existing P2P proof path. A funded Script's post-handoff spend/change produced the same live-cell set in an ordinary-resync control and the D2 destination. A source with two Script registrations exported only A; the destination registered A and did not receive B.

Whole-store copying remains the simpler choice when the goal is to clone all state for the same application/version. D2's demonstrated difference is selective Script responsibility transfer, not universal superiority.

## 1. Original problem

A light-client consumer can lose or replace its local store while retaining the exact Script identity and needing its derived history. Normal restoration re-registers the Script and may filter from an old height. D2 packages one exact packed Script, role, cursor-bound chain commitment, selected index rows, and their referenced transaction closure. It does not transfer keys, application caches, peer state, consensus authority, or unrelated Scripts.

CKBuilder-projects issue #33 requested a controlled comparison against resynchronization and evidence of another consumer. It explicitly did not claim Pocket requested or adopted D2, and it recognized that loss of the original state still requires ordinary recovery/resync.

## 2. Pocket reference proof

Pocket remains D2's real-device reference, not the second-consumer proof. The executable reference record is `docs/G3_1R1_POCKET_EXECUTION_EVIDENCE.md`; it records the Android device/profile, actual Script, native SQLite capture, D2 export/import, and continuation evidence. The Pocket checkout did not call the D2 library directly; the report distinguishes host-side D2 execution from the app's consumption of the resulting local client state. Do not describe this as Pocket adoption.

## 3. Controlled benchmark

The R4 results are in `benchmarks/ev1/r4/results/REPORT.md` and its machine-readable summaries. Controlled pinned-client/SQLite fixtures report:

| Workload | Ordinary resync median | D2 destination median | D2 total median |
|---|---:|---:|---:|
| Sparse, H=10,000 | 45.17 s | 12.79 s | 12.79 s |
| Moderate, H=5,000 | 28.62 s | 6.29 s | 6.42 s |

These are fixture measurements, not mainnet, Internet, mobile, or production performance results. They do not show post-H processing is faster. Full database copying is a separate comparator.

## 4. Second-consumer investigation

The investigation returned 22 GitHub repository-search results and 41 README phrase-search results, then cloned/scanned 25 candidates across native, WASM, wallet, and operational integrations. Search coverage is not exhaustive for private, unindexed, or unpublished consumers. Quantum Purse documentation describes slow fresh-profile recovery and a manual start-height workaround; its static code registers exact Scripts and defaults to genesis when no earlier transaction is known. This is maintainer-documented product pain but was not independently runtime-reproduced here.

iBytes is an independent technical recurrence, not market-demand evidence or a production adoption claim. Its repository contains an implemented Swift/Rust SQLite client and a development-signed physical-iPhone test record. The first-party acceptance record (`iBytes/docs/LIGHT_CLIENT_DEVICE_ACCEPTANCE_2026-08-30.md`) reports imported-account genesis catch-up at cursor/tip 22,258,198 and a post-restart cursor of 22,258,215. That is iBytes' project record, not a new D2 iOS/device test. The current test proves the Rust/SQLite layer. Other inspected code patterns (including ChainPay and Neuron) were not counted as independent migration-pain reports.

## 5. iBytes recurrence reproduction

The imported-account path uses an exact lock Script and a genesis start policy when no trusted birthday exists. The local Rust/SQLite reproduction exercised the real embedded `MobileLightClient`, upstream filtering, SQLite persistence, and restart behavior. The earlier reproduction used a disposable testnet Script and reached the persisted cursor; do not conflate it with the later funded birthday-bounded final proof below.

The source example added for the reproducible Rust layer is `iBytes/rust/ckb-light-client-mobile/examples/nonempty_state_checkpoint.rs`. Its invocation accepts a fresh scan/observe mode, store and network paths, Script args, start/cursor, timeout, and JSON output path. It contains no account secret. The historical proof bridge is exercised by `historical_header_lookup.rs`; D2 storage export/import is exercised by the local example `crates/d2-script-handoff/examples/ibytes_sqlite_handoff.rs`.

Example invocation shapes (substitute local disposable paths and public Script data only):

```sh
cargo run -p ckb-light-client-mobile --features embedded-light-client --example nonempty_state_checkpoint -- scan <fresh-store> <network-dir> <lock-args> <start-block> <target-cursor> <timeout-seconds> <cells-json>
cargo run -p ckb-light-client-mobile --features embedded-light-client --example historical_header_lookup -- testnet <store-dir> <network-dir> <height> <untrusted-candidate-hash> <timeout-seconds>
cargo run -p d2-script-handoff --features sqlite --example ibytes_sqlite_handoff -- export <quiesced-store-file> <packed-script-hex> <new-artifact-file>
cargo run -p d2-script-handoff --features sqlite --example ibytes_sqlite_handoff -- import <fresh-store-file> <artifact-file>
```

The RPC-derived candidate is discovery data only. It is not a trust input to D2 or the client.

## 6. Whole-store-copy baseline

Phase 3 tested a quiesced same-version SQLite-store copy. It preserved Script registration and cursor when the corresponding iBytes sync-registration/account metadata was retained. Applying fresh-import metadata without the preserved sync registration rewound the Script cursor to zero. Peer/network state did not need to be copied. The copy moves unrelated client state and is coupled to the same application/store version; cross-version portability was not tested.

## 7. Sparse historical-boundary failure

The real sparse-store case had a watched Script cursor at H=72,000, a verified light-client tip far ahead, and no `BlockNumber(72,000)` row. The old D2 export therefore returned `HandoffMismatch("destination has no block hash at height 72000")`. The database schema and serialization matched the pinned upstream SQLite storage; this is a general sparse-storage case, not an iBytes-only schema problem.

The generic D2 offline adapter now resolves in this order: exact `BlockNumber(H)` mapping; exact-height entry in `LAST_N_HEADERS`; `LAST_STATE` header only when its own height equals H; otherwise fail closed. The sparse regression fixture keeps the Script cursor at H, omits `BlockNumber(H)`, places H outside the recent-header window, and places the tip far above H. It verifies failure rather than fabricating a mapping.

## 8. Upstream cursor/storage semantics

The per-Script cursor is progress through that Script's filter scan, not a promise that a header is stored for every cursor height. Unmatched filter ranges can advance a cursor without creating a `BlockNumber(H)` row. `LAST_STATE` identifies the accepted tip, and `LAST_N_HEADERS` is only a recent tail; neither is a general historical index. Therefore a missing old height mapping is expected for ordinary upstream SQLite/RocksDB stores.

## 9. Verified historical lookup design

The pinned client checkout is `iBytes/references/ckb-light-client` at `12e29522ab7e078ada704d4ac04cbc0498009b7b`. The local experimental service bridge is implemented in its `light-client-lib/src/service/impls.rs` and `types.rs` diffs, with protocol tests in `light-client-lib/src/tests/protocols/light_client/send_blocks_proof.rs`.

The service accepts `(height, candidate_hash)`, snapshots the accepted tip hash, and queues the candidate through the existing header-fetch/blocks-proof path. The existing protocol machinery verifies the proof against accepted chain state and persists verified header/index data. Polling checks the stored `BlockNumber(height)` mapping, header number, and candidate hash before returning `Verified`. It returns a typed `StaleAnchor` status when the accepted tip changed; the experimental wrapper reissues a proof request against the new accepted tip. It never treats the candidate itself as authority.

This is orchestration around existing proof messages and verification, not a new wire protocol, cryptographic verifier, historical index, or D2-specific upstream API.

## 10. Trust model

- RPC or other discovery may suggest a candidate hash but cannot establish it.
- The active light client's accepted tip and existing P2P/MMR proof verification remain authoritative.
- The requested height and candidate hash must match the persisted verified header mapping.
- Tip changes produce a typed stale-anchor result; the caller retries against a fresh accepted anchor or fails closed.
- D2 source and destination resolve/verify the handoff boundary independently. The destination does not trust the source's assertion or the artifact alone.
- No chain-boundary check was removed or weakened.

## 11. Real H=72,000 source export

The source's Script cursor was H=72,000 and its local `BlockNumber(H)` row was absent. The source database is `/home/timot/ibytes-recurrence/run-20260930T132441Z/store/db.sqlite`; the fresh destination database is `/home/timot/ibytes-recurrence/d2-fresh-destination/store`. The candidate `0x3948bf04f1b45d128e51198c4d69a823ff6ef6818dc742c1eb82859c85dbbce6` was logged as untrusted. The source proof trace is `/home/timot/ibytes-recurrence/verified-lookup-source.log`; it records a stale-anchor retry and then a verified result at height 72,000. The destination independently verified the same candidate in `d2-fresh-destination/lookup.log`. D2 export completed only after the verified height mapping was available; no synthetic mapping was inserted. The preserved export artifact is `/home/timot/ibytes-recurrence/handoff-H72000-S-B.d2` (286 bytes; digest `0xb44c443282a9bce364367e8db031bc16d495f365ec3639d514bfd697be22764c`; 0 index rows, 0 transaction-index rows, 0 transaction rows). This proves sparse-boundary resolution/export for that Script, not non-empty-state correctness; the funded Script A test below establishes non-empty correctness separately.

## 12. Fresh destination import

A genuinely fresh SQLite destination received the D2 artifact, not the source database. It independently obtained and verified the same historical boundary before import. The H=72,000 artifact for this no-match Script carried no indexed transaction rows; it did not clone unrelated client rows, peers, or network state. The separate funded Script A artifact carried one index row, one transaction-index row, and one transaction closure.

## 13. H+1 continuation and restart

The H=72,000 sparse-store run recorded the destination's initial Script cursor as 72,000 and its first filter request with `start_number=72001`. The log `/home/timot/ibytes-recurrence/d2-fresh-destination/resume.log` records subsequent continuation and restart/resume. The final funded run also restored H=22,596,677 and advanced past it, with the cursor preserved after restart. Do not claim the final funded run re-demonstrated imported-account genesis recovery.

## 14. Funded non-empty Script A

The funded test used the locally protected disposable testnet account; no mnemonic/private key is included in this repository or report. Script A was a standard secp256k1 lock (code hash `0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8`, hash type `type`, args `0x022ab7ac6e9b348660965def8b98efd40a426e3d`). The original funding transaction was `0x04d7450b75a574e41f0a1a885f8f5786cf446295fb51ba5318efb6cc708d74ab`, output 0, confirmed at 22,596,464 for 1,000,000,000,000 shannons. The birthday scan start was 22,596,463; handoff H was 22,596,677.

The later self-transfer/change transaction was `0x3f7badcb13642fbe4a487f5f0d071742d3730b7dde0a97240b8bd5e32ab4679d`, confirmed at 22,596,804. It spent the funded cell into outputs of 100,000,000,000 and 899,999,999,404 shannons (596 shannons fee), leaving two live cells and non-empty Script state after handoff.

## 15. Ordinary-resync control

The control was a fresh iBytes SQLite store registering Script A from its correct birthday block 22,596,463. It reconstructed the original funded cell, then independently processed the post-handoff self-transfer. It reached cursor 22,596,810 and reported the two expected live output cells with total capacity 999,999,999,404 shannons.

## 16. Semantic state-equivalence result

The D2 destination independently verified H, imported `/home/timot/ibytes-recurrence/nonempty-state-A.d2` (1,020 bytes; digest `0x04815f929a4e9507f58efd89094b6924f6edf7e36ebcae1f3511912b4ea37263`), and resumed from H=22,596,677. It continued normal filtering and reached cursor 22,596,820, which survived restart. At the common post-spend checkpoint, the control and D2 destination had the same two live outpoints and capacities. Canonical cell JSON SHA-256 matched:

```text
ecb428f900af8bca0a1d4a7e94e2ba5418e0f1b101bf1dce2e423a19cff20c2b
```

The pre-spend one-cell snapshots also matched at SHA-256 `03aa90b1bd704715ab8c6a9f617e3963640595b5a31bdd30b0d079dbf0d5022c`. Final evidence files are under `/home/timot/ibytes-recurrence/nonempty-control/` and `/home/timot/ibytes-recurrence/nonempty-d2-destination/`, including `cells.json`, `post-spend-cells.json`, and `post-restart-cells.json`. The restart snapshot matched the post-spend state digest and retained the cursor.

## 17. Multi-Script selectivity

The source had registrations for A and independent Script B (args `0x1b88b7a6799812a4fcee199ff8c221367c8a2a20`). A held the funded cell; B was registered but had zero live cells. Exporting A produced one Script index row, one transaction-index row, and one transaction closure. The fresh destination had exactly one registration (A); B's registration/state/index was absent. This proves selective transfer of registration and indexed responsibility, not transfer exclusion of B-owned live cells (there were none).

## 18. Full SQLite copy versus D2

At the final proof snapshot, the source directory was approximately 2.04 MB and the D2 artifact was 1,020 bytes. This is an observation, not a controlled size/performance comparison. A full quiesced SQLite copy remains simpler when a user wants the entire same-version client state. D2 transfers one exact Script plus referenced transaction data and avoids copying unrelated Script/client state. Full copy requires preserving relevant iBytes app sync metadata; neither path establishes cross-version portability.

## 19. Security and adversarial tests

D2 regression command and result (run from the D2 workspace root):

```sh
cargo test -p d2-script-handoff --no-default-features --features sqlite
# 24 passed, 0 failed, 4 intentionally ignored
```

The suite covers stored block-number lookup, exact recent-header fallback, exact-tip fallback, wrong-height rejection, sparse unresolved-boundary fail-closed behavior, artifact authority conflicts, and lifecycle cases. In the real proof bridge, a wrong candidate was reported missing and did not create a boundary mapping; importing without a mapping failed closed. The pinned upstream's historical-lookup tests pass 5/5; the complete `send_blocks_proof` module passes 24/24, including the existing proof cases. Tests exercise a far-old valid candidate (including cached header data without a height index), wrong-height response, invalid fork/MMR proof, missing candidate, verified mapping persistence, and changed accepted tip.

Run D2 tests from the repository root. The pinned upstream suite is run from `iBytes/references/ckb-light-client` with `cargo test -p ckb-light-client-lib --lib protocols::light_client::send_blocks_proof` after the focused historical-lookup tests.

## 20. Limitations

- iBytes remains a development-stage project; this is not user-demand evidence or adoption.
- The final funded run used a birthday start, not a fresh imported-account genesis scan.
- Script B had no live cells.
- No full iBytes iOS D2 integration/device handoff was performed; Pocket remains the separate real-device reference.
- Cross-version or cross-schema portability was not tested.
- The benchmark is controlled-fixture evidence only.
- Whole-store copy is valid and often simpler for whole-install migration.
- The experimental historical lookup bridge is local and uncommitted; the final maintained public API and retry orchestration remain for upstream review.

## 21. Minimal upstream change

Propose a small active-client service API that accepts a requested historical height and an untrusted candidate hash, queues the candidate through the existing proof path, returns pending/missing/verified/typed-stale status, and only returns the header/hash after the existing proof verifier has persisted a mapping that matches the requested height and candidate. Snapshot the accepted tip hash for each request; on anchor change, return stale status so the caller can retry with a fresh snapshot. No new wire message, consensus rule, storage schema, D2 type, wallet policy, or RPC trust is needed.

## Local change inventory and evidence handling

| File / area | Repository | Purpose | Disposition | Upstreamable |
|---|---|---|---|---|
| `crates/d2-script-handoff/src/upstream.rs` | D2 | Exact stored mapping → recent header → exact tip boundary resolver, plus sparse/fallback tests | Keep in D2 core patch | Yes, D2 repo |
| `docs/D2_FINAL_CORE_PROOF_2026-10-01.md` | D2 | Durable proof report | Keep | Yes, D2 docs |
| `docs/CKB_LIGHT_CLIENT_HISTORICAL_HEADER_LOOKUP_PROPOSAL_2026-10-01.md` | D2 | Maintainer-facing technical note | Keep | Yes, proposal doc |
| `docs/CKBUILDER_ISSUE_33_DRAFT_UPDATE_2026-10-01.md` | D2 | Unposted issue update | Keep as draft | No |
| `crates/d2-script-handoff/examples/ibytes_sqlite_handoff.rs` | D2 | Local real-SQLite export/import driver | Archive locally; exclude from core patch unless separately polished | No |
| `light-client-lib/src/service/impls.rs` | Pinned upstream checkout | Historical candidate fetch and proof status polling | Keep as local candidate patch | Yes, upstream proposal |
| `light-client-lib/src/service/types.rs` | Pinned upstream checkout | Request/result types including typed stale-anchor status | Keep as local candidate patch | Yes, upstream proposal |
| `light-client-lib/src/tests/protocols/light_client/send_blocks_proof.rs` | Pinned upstream checkout | Existing proof-path historical-header regression tests | Keep as local candidate patch | Yes, upstream proposal |
| `rust/ckb-light-client-mobile/src/mobile.rs` | iBytes | JSON bridge around the experimental service API | Keep as reference-only general-wrapper candidate; not an iBytes PR | Potentially |
| `rust/ckb-light-client-mobile/Cargo.toml` | iBytes | Enables proof/resume example targets | Archive with harness | No |
| `rust/ckb-light-client-mobile/examples/historical_header_lookup.rs` | iBytes | Proof lookup and stale-anchor retry harness | Archive locally; retain as evidence | No |
| `rust/ckb-light-client-mobile/examples/handoff_resume_check.rs` | iBytes | Destination continuation/restart harness | Archive locally; retain as evidence | No |
| `rust/ckb-light-client-mobile/examples/nonempty_state_checkpoint.rs` | iBytes | Scan/observe and canonical cell-state harness | Archive locally; retain as evidence | No |
| `/home/timot/ibytes-recurrence/` DBs, artifacts, JSON snapshots, and logs, including `handoff-H72000-S-B.d2` | Local WSL evidence only | Reproduction inputs/outputs | Keep locally; do not add to either repository | No |
| WSL `verified-lookup-network/secret_key` and the DPAPI-wrapped disposable account file under `%LOCALAPPDATA%\iBytes-D2-disposable\` | Local secret material | Runtime identity and test account | Keep secured locally; contents not read for packaging; exclude from commits/docs | No |
| Cargo build targets and caches | Local build environment | Build output | Leave ignored/outside source control | No |
| Other files | D2, iBytes, pinned upstream | Unrelated changes | None detected in current worktree diffs | N/A |

No unrelated source changes are intended. No evidence, database, account material, or log is deleted by this packaging work.
