# G3-1R1 Pocket executable reference-flow evidence

**Status:** G3-1R1 HOLD — Android execution is incomplete

**Starting D2 HEAD:** `7e96fbb83645f3196c01ab6113a39903a44a2a9b`

**Pocket checkout:** `_work/g3-1-pocket-node`, commit
`6eda0b7a4601050b011591d41cc702f0dc7a7c38` (`v0.5.4` source profile)

**Test date:** 10 September 2026

This document records only G3-1R1 execution evidence. It does not reopen G2,
change PDEF1, add PV1, or claim Pocket adoption.

## 1. Scope and evidence classes

The required flow is:

```text
real Pocket wallet and Script
  -> real Pocket store.db
  -> production D2 export/inspect/validate/import
  -> Pocket destination restart and normal continuation
  -> Pocket Room/application state
```

Evidence is classified as:

- **NEW PRODUCTION TEST:** the D2 Pocket adapter and its production-path test
  in `crates/d2-script-handoff/src/pocket.rs`.
- **REAL DEVICE EVIDENCE:** logs and database captures from a debug build of
  Pocket on a Samsung SM-S9180.
- **HOST-SIDE POCKET EVIDENCE:** production D2 execution against a captured
  Pocket-created database, without claiming that the Android application
  lifecycle has been exercised.
- **NOT PROVEN:** a required property for which no direct Pocket execution
  evidence exists.

## 2. Target and wallet

The published Pocket v1.8.3 package was replaced on a disposable test
installation by a debuggable build from the pinned Pocket checkout. The device
reported model `SM-S9180`, ABI `arm64-v8a`, and SDK 36. `run-as` was available
for the debug package, while the original release package was not debuggable.

A new wallet was created through Pocket's actual UI. No mnemonic, private key,
PIN hash, Android keystore material, `key_material` blob, or native
`secret_key` file was extracted or stored in the repository. The wallet remains
usable only through the device's normal authentication/recovery flow.

The captured wallet's exact registered identity was:

- packed Script length: 73 bytes;
- role: `lock`;
- packed Script:
  `490000001000000030000000310000009BD7E06F3ECF4BE0F2FCD2188B23F1B9FCC88E5D4B65A8637B17723BBDA3CCE80114000000BC5882C4309431EE23AD7BBAD4B5C3325539EEBD`;
- Pocket registration key: the Pocket `FILTER_SCRIPTS` prefix followed by
  that packed Script and role byte `00`.

The source database was captured after Pocket had reached a real mainnet tip.
The capture was made after force-stopping the app; the native secret-key path
was deliberately excluded.

## 3. Real Pocket storage profile

The captured Pocket database is:

`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-store.db`

Observed facts:

| Property | Observation |
|---|---|
| SQLite schema | `kv(key BLOB PRIMARY KEY, value BLOB)` |
| Rows | 10,215 |
| Integrity | SQLite integrity check returned `ok` |
| Logical key families | transaction, CellLockScript, CellTypeScript, TxLockScript, TxTypeScript, BlockHash, BlockNumber, checkpoint/filter hash, Meta |
| exact Script status | present under `FILTER_SCRIPTS` |
| status value | big-endian cursor `20,410,406` |
| `MIN_FILTERED_NUMBER` | little-endian value `20,410,406` |
| selected Script index rows | 0 in this capture |
| selected transaction-index rows | 0 in this capture |
| selected transaction closure rows | 0 in this capture |

The zero derived-row result is important. This is a genuine registered
Script-bearing Pocket database and a real cursor handoff, but it is not a
matched-transaction history. The random new wallet had no funded or historical
mainnet activity during the capture. No rows were fabricated to turn it into a
positive transaction fixture.

Source/profile correspondence was checked against Pocket's vendored
`light-client-lib/src/storage/mod.rs` and `src/storage/db/sqlite.rs`. The
relevant logical key prefixes, packed Script encoding, role byte, cursor byte
order, and native SQLite `kv` representation match the explicit adapter
profile. Pocket's Room database is a separate application database and is not
part of the D2 artifact.

## 4. Production D2 Pocket adapter result

G3-1R1 added one explicit feature/profile only:

```text
pocket-sqlite
pocket-node@6eda0b7a4601050b011591d41cc702f0dc7a7c38/ckb-light-client@0.5.4/kv-v1
```

The adapter is separate from the pinned G1 `kv_store` adapter. It accepts only
the Pocket `kv` schema, exports the selected exact packed Script plus `lock`
role, includes only that Script's relevant index families and exact referenced
transaction closure, and updates only the selected registration and the
recomputed global minimum cursor during import. It does not export or import
`LAST_STATE`, headers, peer/network state, Room rows, wallet keys, or any other
global chain authority.

The production-path test was:

```powershell
$env:D2_POCKET_SOURCE = "_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-store.db"
$env:D2_POCKET_DEST = "_work/g3-1-pocket-node/_g3-1r1-evidence/<new-disposable>.db"
$env:D2_POCKET_SCRIPT = "490000001000000030000000310000009BD7E06F3ECF4BE0F2FCD2188B23F1B9FCC88E5D4B65A8637B17723BBDA3CCE80114000000BC5882C4309431EE23AD7BBAD4B5C3325539EEBD"
cargo test -p d2-script-handoff --no-default-features --features sqlite,pocket-sqlite --offline production_pocket_export_validate_import --lib -- --ignored --nocapture --test-threads=1
```

The exact final run is recorded in
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-production-test-final.log`:

```text
test pocket::tests::production_pocket_export_validate_import ... ok
result: 1 passed, 0 failed
pocket-export ... handoff_height=20410406 index_rows=0 transaction_index_rows=0 transaction_rows=0 artifact_bytes=299
```

This test used production `D2::export`, canonical artifact encoding, inspect,
destination validation, atomic import, reopen, idempotent validation, and
idempotent re-import. It is a real Pocket storage/profile result. It is not an
Android app import result.

## 5. No-D2 control attempt

A disposable no-D2 control was constructed from the real Pocket source:

- selected exact Script registration removed;
- selected Script index namespaces removed;
- the rest of the native Pocket database retained;
- `MIN_FILTERED_NUMBER` lowered to `20,410,389`;
- Pocket Room `sync_progress` for the wallet set to start/local block
  `20,410,389`;
- Room wallet and key-material rows retained on the device.

The resulting native database was structurally valid with 10,214 rows. Pocket
was started from the debug package and the native pinned client exchanged real
peer, proof, and filter-hash traffic. The captured log includes filter-hash
ranges such as `start: 20408001` and `start: 20410001`.

However, Pocket's application log reported `scriptBlock=0`, and no
`SyncCoordinator` Script-registration event was captured. The app had not
been unlocked after the database replacement, so the exact wallet Script was
not registered in this run. Consequently this is **not** a valid exact-Script
historical-refilter control. It is retained as a diagnostic failed attempt,
not counted as PASS.

Evidence:

- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-runtime.log`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-after.db`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-room-no-d2-after.db`.

## 6. Android lifecycle status

The following required properties remain **NOT PROVEN**:

1. a valid no-D2 exact-Script control that historically filters through H;
2. production D2 import into a fresh Pocket destination on Android;
3. Android request instrumentation proving no historical exact-Script filter
   request at or below accepted H;
4. Pocket Room/application rebuild from imported native state;
5. exact-Script post-H transaction/block observation;
6. restart/process-death coherence after a real Android D2 import;
7. Android export/import duration, peak memory, temporary storage, and lock
   measurements;
8. fair device-level comparison with Pocket DB copy and Pocket-specific
   migration alternatives.

The immediate execution blocker is environmental and explicit: after the
control capture, `adb devices -l` returned an empty device list and Windows
reported no present Samsung/Android/ADB PnP device. The D2 destination could
therefore not be staged, unlocked, started, or observed. The captured source,
Room database, and host evidence remain in the disposable `_work` tree.

This blocker must not be converted into a PASS by using host-only adapter
tests or by inferring request behavior from a cursor value.

## 7. Current G3-1R1 decision

| Gate | Result | Evidence basis |
|---|---|---|
| Real wallet and exact registered Script | PASS | Pocket UI creation and real `FILTER_SCRIPTS` key in captured `store.db` |
| Real Script-bearing Pocket database | PASS, zero-closure qualification | 10,215-row real Pocket SQLite capture; selected cursor present; no selected matches |
| Pocket SQLite profile | PASS | Source comparison plus explicit adapter/profile check |
| Production D2 export/inspect/validate/import/reopen | PASS, host-side Pocket DB | New production test against captured Pocket `store.db` |
| No-D2 exact-Script historical refilter | HOLD | Initial control did not unlock/register the Script |
| D2 Android import and no-refilter proof | HOLD | Samsung disappeared from ADB before destination run |
| Room/application rebuild | HOLD | No Android D2 import occurred |
| Post-H exact-Script continuation | HOLD | No funded/matched Script transaction and no Android D2 run |
| Android restart/process death | HOLD | No post-import Android state |
| Android measurements/alternatives | HOLD | No device during the required operation |

**G3-1R1 classification: HOLD — POCKET PROFILE AND HOST PRODUCTION PATH
PROVEN; ANDROID REFERENCE-FLOW CLOSURE BLOCKED.**

The narrow Pocket adapter is within the frozen D2 boundary. The missing
Android lifecycle evidence is still required before G3-1 can be classified as
a successful reference-consumer integration.
