# G1-R1 lifecycle evidence

This document closes the four required G1 HOLD rows using the production
`d2-script-handoff` path. It does not add G2 scale work, PV1 semantics, or a
reference-consumer integration.

## Evidence classification

- **New production path:** D2 export, inspect/validation, exclusive-open,
  import, native batch commit, reopen, and result handling in
  `crates/d2-script-handoff`.
- **Reused upstream fixture:** the accepted bounded RP2 fixture shape, with
  the real pinned upstream filter/proof/synchronizer path and native RocksDB or
  SQLite storage.
- **Test-only upstream instrumentation:** the ignored upstream checkout adds
  persistent chain-fixture construction, filter-request capture, and worker
  modes. It does not change D2 artifact semantics or production D2 storage
  operations.
- **Independent oracle:** the upstream protocol itself performs continuation
  and rollback/reorg decisions. D2 supplies only the imported Script-derived
  state and transaction closure.

The upstream source revision used by all protocol evidence is:

```text
12e29522ab7e078ada704d4ac04cbc0498009b7b
```

The D2 adapter profile is:

```text
ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1
```

The protocol worker is the ignored test `tests::rp2_authority_replay::g1_production_protocol_worker` in the pinned upstream checkout. The D2 worker is the ignored test `upstream::tests::production_g1_external_worker`; every export/import operation in that worker calls the public `D2` facade.

## Row 24 — post-H continuation

The tracked runner is:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-r1-protocol.ps1 -Direction rocks-to-sqlite -UpstreamSourceExe _work\upstream\ckb-light-client\target\debug\deps\ckb_light_client_lib-5f505b5cd3ee38ff.exe -UpstreamDestinationExe _work\upstream\ckb-light-client\target\debug\deps\ckb_light_client_lib-ae2c7b6fc1d19ab8.exe -D2SourceExe target\debug\deps\d2_script_handoff-301c15f6fed911db.exe -D2DestinationExe target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe -Root _work\g1-r1-protocol-rocks-to-sqlite-final-20260908b

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-r1-protocol.ps1 -Direction sqlite-to-rocks -UpstreamSourceExe _work\upstream\ckb-light-client\target\debug\deps\ckb_light_client_lib-ae2c7b6fc1d19ab8.exe -UpstreamDestinationExe _work\upstream\ckb-light-client\target\debug\deps\ckb_light_client_lib-5f505b5cd3ee38ff.exe -D2SourceExe target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe -D2DestinationExe target\debug\deps\d2_script_handoff-301c15f6fed911db.exe -Root _work\g1-r1-protocol-sqlite-to-rocks-final-20260908
```

Each direction performs, in separate processes: upstream source preparation
through H, production `D2::export`, upstream destination preparation,
production `D2::import`, destination reopen, actual upstream filtering, and a
post-H exact-Script transaction. The bounded fixture uses H=36 and puts the
post-H transaction in block 39. Both runners reported:

```text
positive_filter_request_starts: [37]
positive_no_refilter_through_h: true
negative_control_filter_request_starts: [1]
negative_control_detected_historical_filtering: true
post_h_transaction_height: 39
```

The positive state and transaction closure are in `evidence/continuation.json`
under each direction root. The negative control registers the same Script at
cursor 0 and lets the same real scheduler run; its request at 1 demonstrates
that the instrumentation would observe historical filtering when the handoff
cursor is absent/lower.

**Result: PASS.** This proves the bounded pinned-protocol continuation seam,
not historical completeness or arbitrary client behavior.

## Row 25 — no historical refilter through H

This is the same two protocol runs, but the result is based on captured
upstream request starts rather than the imported cursor alone. After restart,
the accepted H=36 destination begins at 37. The matched negative-control
destination begins at 1. The upstream worker records both lists and asserts
both the positive and negative conditions before writing its result.

**Result: PASS.** The claim is limited to the exercised filter scheduler and
fixture; D2 does not add a global coverage ledger and does not claim trustless
historical completeness.

## Row 26 — production shallow-fork convergence

The tracked runner is:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-r1-reorg.ps1 -UpstreamExe _work\upstream\ckb-light-client\target\debug\deps\ckb_light_client_lib-5f505b5cd3ee38ff.exe -D2Exe target\debug\deps\d2_script_handoff-301c15f6fed911db.exe -Artifact _work\g1-r1-protocol-rocks-to-sqlite-final-20260908b\evidence\handoff.d2 -Root _work\g1-r1-reorg-script-final-20260908
```

The runner first creates an independently authoritative destination, imports
the handoff with production D2, then invokes the pinned upstream
`LightClientProtocol.received` path for the accepted RP2 fork fixture. The
fixture is H=36, forks at 33, and converges at tip/progress 38. The protocol
worker asserts that the old A1 state is removed, replacement A2R is live,
progress is 38, unrelated lock/type registrations survive, and a fresh
process can reopen the resulting native storage. The evidence is
`reorg.json` and `reorg-reopen.json` under the runner root.

**Result: PASS.** This is a bounded shallow-fork result. Chain rollback and
reconciliation remain destination-owned; no arbitrary-depth fork claim is
made.

## Row 28 — independent process race

The tracked runner is:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-r1-process-race.ps1 -Backend rocksdb -WorkerExe target\debug\deps\d2_script_handoff-301c15f6fed911db.exe -Root _work\g1-r1-race-rocks-final-20260908c -Count 10

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-r1-process-race.ps1 -Backend sqlite -WorkerExe target\debug\deps\d2_script_handoff-6ab6297fddde5b7d.exe -Root _work\g1-r1-race-sqlite-final-20260908b -Count 10
```

Each repetition creates a fresh native destination and valid production D2
artifact. One OS process opens the destination through
`UpstreamAdapter::open_exclusive`, pauses immediately before its native batch
commit, and holds the D2 lock. A second independent process starts during
that preparation window. The runner then releases the winner, verifies the
winner's accepted result and the contender's typed `Retryable` lifecycle
rejection, and runs a third post-commit process which must return accepted
`idempotent: true`. Captured evidence is in each case's
`evidence/race-result.json`, with process stdout/stderr alongside it.

Results:

| Backend | Repetitions | Winner | Contender | Post-commit retry | Result |
|---|---:|---|---|---|---|
| RocksDB | 10 | accepted, non-idempotent | typed retryable lifecycle rejection | accepted, idempotent | PASS |
| SQLite | 10 | accepted, non-idempotent | typed retryable lifecycle rejection | accepted, idempotent | PASS |

The pre-open lock ordering is required for RocksDB: opening native storage
before D2's lifecycle lock would let the contender fail inside the upstream
engine's `LOCK` handling instead of receiving a D2 lifecycle result. The
product constructor now acquires D2 exclusivity before opening native storage.
This does not replace or weaken the upstream native lock, and it does not
claim live import or power-loss durability.

**Result: PASS.** The test covers the required controlled preparation race and
post-commit retry. It does not cover a physical power loss or a kill inside a
native storage-engine commit.

## Regression evidence

The following passed after the lifecycle changes:

```text
cargo fmt --all -- --check
cargo check -p d2-script-handoff --no-default-features --features sqlite --offline
cargo clippy -p d2-script-handoff --no-default-features --features sqlite --all-targets --offline -- -D warnings
cargo test -p d2-script-handoff --no-default-features --features sqlite --offline
cargo check -p d2-script-handoff --offline
cargo clippy -p d2-script-handoff --all-targets --offline -- -D warnings
cargo test -p d2-script-handoff --offline
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-g1-cross-backend.ps1
```

Both backend unit/product suites reported 16 passed, 2 ignored, 0 failed.
The cross-backend runner reported four production exchange tests passed: two
export/import operations in each direction. The G1-R1 protocol runners added
two continuation and two control preparations per direction, and the reorg
runner passed both the rollback process and separate reopen process. The race
runner passed 20/20 process repetitions.

## Explicit remaining limits

These results do not change PDEF1's non-goals: no trustless completeness, no
historical interval ledger or PV1 coverage epochs, no arbitrary full-client
snapshot, no arbitrary-depth reorg guarantee, no power-loss durability, no
mainnet-scale or mobile claim, no automatic cross-version migration, no live
import, no signed artifact, and no Pocket/Neuron/Fiber integration.
