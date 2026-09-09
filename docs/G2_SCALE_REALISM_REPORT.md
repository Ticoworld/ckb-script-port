# G2 scale, realism, and durability qualification

Date: 9 September 2026  
G2 start checkpoint: `89e2627dd8edd0a38dbfd07528e799ff6008ab09`  
PDEF1: `a7cef643b2fd5b8941670b6319e53cb15380b164`  
Pinned upstream profile: `ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1`

## Executive result

G2 result: **PASS — REALISM QUALIFIED**.

D2 remains coherent and useful at the tested synthetic scale, but its product
value is conditional rather than a universal wall-clock win. The source has
already paid the historical filtering cost; D2 then transports a selective,
backend-neutral exact-Script view. On the measured workloads this is materially
smaller and faster than replaying the same native filter path, while a same-
backend whole-database copy remains faster when portability and selectivity are
irrelevant.

This is a qualification result, not a mainnet, mobile, power-loss, or arbitrary
reorg result.

## Evidence boundary and provenance

The scale workers are test-only runners in `crates/d2-script-handoff/src/upstream.rs`.
They call the production D2 facade for every export, inspection, validation, and
import. They use the pinned upstream native storage profile to construct
disposable histories through `Storage::filter_block`. The histories are
generated packed CKB blocks with deterministic headers and transactions; they
are controlled synthetic workloads and must not be described as mainnet data or
as a full network-protocol replay.

The primary commands were:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\run-g2-scale.ps1' -Root '.\_work\g2-scale-control-20260909c' -Workloads 'control' -Repeats 3 -RocksWorker '.\target\debug\deps\d2_script_handoff-301c15f6fed911db.exe' -SqliteWorker '.\target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe'"

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\run-g2-scale.ps1' -Root '.\_work\g2-scale-realistic-20260909b' -Workloads 'realistic-sparse','realistic-moderate','realistic-dense' -Repeats 3 -RocksWorker '.\target\debug\deps\d2_script_handoff-301c15f6fed911db.exe' -SqliteWorker '.\target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe'"

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\run-g2-scale.ps1' -Root '.\_work\g2-scale-stress-unique-20260909b' -Workloads 'stress-unique' -Repeats 2 -RocksWorker '.\target\debug\deps\d2_script_handoff-301c15f6fed911db.exe' -SqliteWorker '.\target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe'"

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '.\scripts\run-g2-scale.ps1' -Root '.\_work\g2-scale-stress-shared-20260909b' -Workloads 'stress-shared' -Repeats 2 -RocksWorker '.\target\debug\deps\d2_script_handoff-301c15f6fed911db.exe' -SqliteWorker '.\target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe'"
```

The first mixed five-workload attempt was stopped after more than fifteen
minutes in the shared stress section and had no summary. It is retained as an
incomplete exploratory attempt and is not used as a passing result. The
bounded workload runs above completed and produced the evidence used here.

A separate optional runner, `scripts/run-g2-protocol.ps1`, attempted the
larger pinned protocol fixture. Its source-preparation process reached a
pinned-upstream `ckb-traits::epoch_provider` subtraction overflow before it
could produce a protocol result. That failure is recorded as an upstream
fixture limitation and is not converted into a D2 pass. The completed scale
matrix therefore intentionally uses the upstream-compatible native storage
filter path described above, with its protocol/network limitation stated
explicitly.

The machine was Windows PowerShell on an 11th Gen Intel Core i5-1145G7,
4 cores/8 logical processors, with Rust `rustc 1.96.0` and Cargo `1.96.0`.
Measurements used the Cargo dev/test profile. Process RSS and CPU are sampled
by the PowerShell runner every 20 ms; operation timings are measured inside the
worker. Source preparation is reported separately from D2 transfer work.

## Workload matrix

| Workload | Class | History H | Match shape | Index rows | Transaction-index rows | Closure transactions | Repetitions |
|---|---|---:|---|---:|---:|---:|---:|
| control | CONTROL | 36 | every 18th block, 1 transaction × 1 output | 2 | 2 | 2 | 3 |
| realistic-sparse | REALISTIC-SYNTHETIC | 10,000 | every 100th block, 1 × 1 | 100 | 100 | 100 | 3 |
| realistic-moderate | REALISTIC-SYNTHETIC | 5,000 | every 10th block, 2 × 4 | 4,000 | 4,000 | 1,000 | 3 |
| realistic-dense | REALISTIC-SYNTHETIC | 2,000 | every block, 2 × 4 | 16,000 | 16,000 | 4,000 | 3 |
| stress-unique | STRESS | 2,500 | every block, 4 × 2 | 20,000 | 20,000 | 10,000 | 2 |
| stress-shared | STRESS | 2,500 | every block, 1 × 16 | 40,000 | 40,000 | 2,500 | 2 |

Every workload was exported from RocksDB and SQLite sources and imported into
both destination backends. The control run preserves the accepted H=36 shape;
the other runs intentionally vary depth, density, row count, and closure
sharing. `stress-unique` makes mostly unique transaction facts, while
`stress-shared` maximizes many Script rows per closure transaction.

## Export and artifact results

The following are median internal export times; preparation is not part of the
D2 export call and is shown separately. `row payload` is the sum of semantic row
key/value bytes, not a fabricated in-memory model size.

| Workload/backend | Preparation | Export | Source tree | Row payload | Artifact |
|---|---:|---:|---:|---:|---:|
| control / RocksDB | 85.6 ms | 0.26 ms | 84 KiB | 718 B | 1,032 B |
| control / SQLite | 50.2 ms | 0.32 ms | 136 KiB | 718 B | 1,032 B |
| sparse / RocksDB | 650.7 ms | 7.5 ms | 84 KiB | 35.9 KiB | 38.6 KiB |
| sparse / SQLite | 802.4 ms | 8.2 ms | 136 KiB | 35.9 KiB | 38.6 KiB |
| moderate / RocksDB | 687.9 ms | 256 ms | 346 KiB | 1.097 MiB | 1.169 MiB |
| moderate / SQLite | 1.150 s | 244 ms | 2.71 MiB | 1.097 MiB | 1.169 MiB |
| dense / RocksDB | 1.398 s | 1.17 s | 1.18 MiB | 4.388 MiB | 4.676 MiB |
| dense / SQLite | 3.363 s | 1.10 s | 10.75 MiB | 4.388 MiB | 4.676 MiB |
| unique stress / RocksDB | 2.893 s | 3.50 s | 2.01 MiB | 5.77 MiB | 6.45 MiB |
| unique stress / SQLite | 8.275 s | 3.15 s | 15.09 MiB | 5.77 MiB | 6.45 MiB |
| shared stress / RocksDB | 7.834 s | 3.51 s | 1.77 MiB | 9.66 MiB | 10.78 MiB |
| shared stress / SQLite | 20.905 s | 3.80 s | 25.44 MiB | 9.66 MiB | 10.78 MiB |

The artifact was byte-identical for RocksDB and SQLite for each workload. Its
ratio to semantic row payload was approximately 1.065–1.074×. Source tree size
is backend-engine and compaction dependent, so it is not a semantic artifact
size and must not be used as a portability promise.

## Validation and import results

The production import worker measures inspect/decode, full validation, native
mutation, and reopen separately. The table gives representative medians by
destination backend aggregated over both source backends and the available
repetitions.

| Workload/destination | Inspect | Validate | Import | Reopen | Peak sampled RSS |
|---|---:|---:|---:|---:|---:|
| sparse / RocksDB | 1.8 ms | 8.6 ms | 22.0 ms | 84.0 ms | 14.5 MiB |
| sparse / SQLite | 1.3 ms | 7.3 ms | 35.0 ms | 13.7 ms | 7.7 MiB |
| moderate / RocksDB | 43.5 ms | 244.7 ms | 486.7 ms | 401.4 ms | 20.8 MiB |
| moderate / SQLite | 44.4 ms | 275.5 ms | 1.33 s | 312.7 ms | 15.6 MiB |
| dense / RocksDB | 184.0 ms | 966.4 ms | 2.68 s | 2.87 s | 37.4 MiB |
| dense / SQLite | 261.2 ms | 1.50 s | 6.23 s | 2.38 s | 37.0 MiB |
| unique stress / RocksDB | — | 2.62–3.18 s | 6.09–7.66 s | 4.62–4.78 s | 70 MiB |
| unique stress / SQLite | — | 3.34–4.77 s | 7.89–18.08 s | 2.33–4.12 s | — |
| shared stress / RocksDB | 727 ms | 3.61 s | 8.94 s | 6.85 s | 73.2 MiB |
| shared stress / SQLite | 537 ms | 4.53 s | 24.88 s | 6.44 s | 78.6 MiB |

The stress figures are deliberately not presented as a production capacity
limit. They identify the cost curve and the resource risk as closure and index
rows grow.

## D2 versus native rescan

The rescan comparator creates a fresh destination and replays the same packed
history through the pinned upstream native `filter_block` path. It measures
storage and filtering CPU, but does not emulate network transfer latency or a
real peer's filter-request scheduling. It is therefore a conservative local
replay comparator, not a complete network benchmark.

Median rescan times were:

| Workload | RocksDB rescan | SQLite rescan |
|---|---:|---:|
| control | 94.8 ms | 40.6 ms |
| sparse | 1.01 s | 0.80 s |
| moderate | 0.91 s | 1.42 s |
| dense | 2.81 s | 5.38 s |
| unique stress | 2.63 s | 7.15 s |
| shared stress | 5.82 s | 13.07 s |

D2 transfer is clearly cheaper than replay for sparse histories and the larger
stress shapes when the source state already exists. At moderate/dense sizes,
SQLite import and reopen can approach or exceed this local replay comparator.
The correct product conclusion is **CONDITIONALLY BENEFICIAL**, not “always
faster.” D2's additional value is avoiding repeated historical protocol work,
selecting one exact Script, preserving destination chain authority, and
crossing RocksDB/SQLite boundaries.

The first mixed five-workload run exceeded fifteen minutes before its summary
could be written, concentrated in the 40,000-row shared stress case. The
completed two-repeat stress run establishes that this is a slow but bounded
case, not a silent pass or a mainnet claim.

## D2 versus raw database copy

For a same-backend move, native RocksDB backup/copy or SQLite file backup is
normally faster and simpler. It also transfers every unrelated Script, global
metadata, chain state, and backend-specific implementation detail. It is tied
to the native backend, file lifecycle, and usually the exact upstream storage
version.

D2 adds a typed, deterministic, exact-Script-selected artifact, explicit
closure validation, fail-closed identity/genesis/handoff checks, and a
cross-backend adapter boundary. D2 does not replace a full database backup,
and a database copy remains the stronger alternative when the requirement is a
same-version whole-client restore. D2 is preferable when the requirement is a
selective handoff that must not import source chain authority or unrelated
state.

## Interruption and durability

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g2-interruption.ps1 -Backend rocksdb -WorkerExe target/debug/deps/d2_script_handoff-301c15f6fed911db.exe -Root _work/g2-interruption-rocks-20260909b -Count 3
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g2-interruption.ps1 -Backend sqlite -WorkerExe target/debug/deps/d2_script_handoff-6ab6297fddde5b7d.exe -Root _work/g2-interruption-sqlite-20260909b -Count 3
```

Each of three cases per backend killed an independent production D2 process
after validation/preparation and before the native commit. The killed process
exited with `-1`; a retry was newly accepted; a subsequent reopen/retry was
accepted idempotently. This is stronger than an in-process exception and
confirms the tested pre-commit window leaves coherent old state.

The evidence does not cover terminating the process inside RocksDB or SQLite's
native commit, filesystem power loss, or physical storage failure. Those remain
explicitly outside G2. The claim is controlled process interruption plus
reopen coherence within the tested boundary.

## Reorg depth and history shape

The production path was exercised with the pinned upstream reorg worker using
the imported artifact. The accepted bounded case at `fork_point=33` and
`fork_tip=38` removed the old Script cell, indexed the replacement branch,
preserved unrelated state, converged progress, and remained coherent after
reopen. Evidence: `_work/g2-reorg-sqlite-20260909d/evidence`.

Attempts to use `fork_point=32, fork_tip=40` and `fork_point=30, fork_tip=40`
were rejected by the upstream proof/sample path with `InvalidSamples(451)` in
the first attempts. The later diagnostic runner recorded the same boundary as
`InvalidReorgHeaders: retained last-N window is 3`, with authority unchanged
and coherent reopen state, for both RocksDB and SQLite. Evidence roots include
`_work/g2-reorg-rocks-20260909e/evidence` and
`_work/g2-reorg-sqlite-20260909-x/evidence`. This is an upstream
fixture/proof envelope, not a D2 success. It establishes that this fixture
cannot honestly qualify deeper forks. D2 therefore retains the G1 bounded
reorg claim and makes no arbitrary-depth assertion.

## Repeated independent Script operations

`upstream::tests::production_g2_repeated_independent_script_operations_remain_coherent`
passed in both backend feature builds. It exports two distinct exact packed
Scripts from independent production source adapters, imports them sequentially
into one destination, closes/reopens the destination, and validates both
artifacts idempotently with all rows present. This validates repeated
single-Script operations; it does not add or prove an atomic multi-Script
package.

## SQLite and mobile-style feasibility

SQLite is the embedded-style surface measured here. The largest completed
shared workload used a 10.78 MiB artifact, a 23.61 MiB SQLite destination, and
about 78.6 MiB peak sampled worker RSS during import. Its import median was
about 24.9 seconds. These numbers show no architectural requirement for a
second chain-authority database, but they expose a material resource risk for
small-memory devices. No mobile OS, emulator, application, or beneficiary was
tested. Classification: **RESOURCE RISK**; mobile deployment remains outside
G2/G3 integration work.

## Upstream profile coupling

The adapter is explicitly pinned to `12e2952.../storage-v1`. The local
upstream checkout also contains `v0.5.5-rc1`, which was inspected without
changing the project dependency. The storage comparison showed no changes in
the key-encoding storage modules used by the adapter, while
`storage_trait.rs` changed and filter-processing files were materially
refactored. This means the logical profile is not obviously unstable, but the
adapter is coupled to upstream `Key`, `Value`, and storage API details.

Classification: **PROFILE MODERATELY COUPLED**. The current adapter must not be
used with an untested revision. A new profile requires an explicit adapter and
conformance run; no automatic migration is provided.

## Product-value kill gate

The measurements do not kill the product, but they narrow its value. D2 is not
a universal speed optimization: for some dense SQLite cases, import plus
reopen is slower than local synthetic replay, and same-backend database copy is
faster. D2 remains useful where the source has already done historical work,
where the destination must avoid repeating that work, where only one exact
Script should move, or where RocksDB/SQLite portability and destination-owned
chain authority matter. This is a conditional product, consistent with PDEF1.

## G2 acceptance and deferred work

The canonical 20-row result is in `docs/G2_ACCEPTANCE_MATRIX.md`: **20 PASS,
0 HOLD, 0 FAIL**.

Deferred beyond G2:

- mainnet-derived scale and long-history performance;
- power-loss and kill-inside-native-commit durability;
- mobile/Android/iOS execution and memory tuning;
- arbitrary-depth reorgs or consensus-authority transfer;
- signed/authenticated/public artifacts;
- multi-Script atomic packages;
- arbitrary upstream-version migration;
- PV1 historical coverage semantics;
- Pocket, Neuron, Fiber, or another reference consumer.

## G3 readiness

D2 is technically ready for G3 beneficiary selection, not for an assumed
beneficiary integration. G3 should select one real consumer only after checking
that it uses this pinned light-client profile, has exact-Script-derived state
worth transferring, and has a real restore/backend-change scenario. No Pocket,
Neuron, or Fiber support is claimed by this report.

## Final classification

**G2 PASS — REALISM QUALIFIED.**

Safe next action: begin the separate G3 reference-consumer selection review.
Do not expand D2 scope or reinterpret this report as a mainnet/mobile/power-
loss qualification.
