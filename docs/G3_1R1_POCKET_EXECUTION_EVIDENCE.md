# G3-1R1 Pocket executable reference-flow evidence

**Status:** G3-1R1 PASS - Pocket executable reference-flow closure complete

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
  Pocket-created database. The Android application consumes the resulting
  local light-client state through its normal runtime path; the Pocket
  checkout does not contain a direct call into the D2 library.
- **NOT PROVEN:** a required property for which no direct Pocket execution
  evidence exists.

## 2. Target and wallet

The published Pocket v1.8.3 package was replaced on a disposable test
installation by a debuggable build from the pinned Pocket checkout. The device
reported model `SM-S9180`, ABI `arm64-v8a`, and SDK 36. `run-as` was available
for the debug package, while the original release package was not debuggable.

A new wallet was created through Pocket's actual UI. No plaintext mnemonic,
private key, PIN hash, Android keystore material, or native `secret_key` file
was extracted. The temporary local Room database capture necessarily contains
Pocket's encrypted `key_material` row so that the disposable app database
could be staged and inspected; it is untracked test material, was never
committed, and was not decrypted. The wallet remains usable through the
device's normal authentication/recovery flow.

The captured wallet's exact registered identity was:

- packed Script length: 73 bytes;
- role: `lock`;
- packed Script:
  `490000001000000030000000310000009BD7E06F3ECF4BE0F2FCD2188B23F1B9FCC88E5D4B65A8637B17723BBDA3CCE80114000000BC5882C4309431EE23AD7BBAD4B5C3325539EEBD`;
- Pocket registration key: the Pocket `FILTER_SCRIPTS` prefix followed by
  that packed Script and role byte `00`.

The positive source database was captured from Pocket testnet after the wallet
was funded through the official faucet and a normal Pocket self-transfer was
later created. The capture was made after force-stopping the app; the native
secret-key path was deliberately excluded.

## 3. Real Pocket storage profile

The captured positive Pocket database is:

`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-real-pocket-source-1.db`

Observed facts:

| Property | Observation |
|---|---|
| SQLite schema | `kv(key BLOB PRIMARY KEY, value BLOB)` |
| Rows | 11,205 |
| Integrity | SQLite integrity check returned `ok` |
| Logical key families | transaction, CellLockScript, CellTypeScript, TxLockScript, TxTypeScript, BlockHash, BlockNumber, checkpoint/filter hash, Meta |
| exact Script status | present under `FILTER_SCRIPTS` |
| status value | big-endian cursor `22,370,055` |
| `MIN_FILTERED_NUMBER` | little-endian value `22,370,055` |
| handoff hash | `0x46c067702c9b8b9e4d633679bbdc8015914862f1b37fbe0cb0333ec04f08bdbf` |
| selected Script index rows | 2 |
| selected transaction-index rows | 2 |
| selected transaction closure rows | 2 |

This is a real registered Script-bearing Pocket database with two matched
faucet transactions and their exact transaction closure. The source cursor was
lowered only in a disposable copy before Pocket's real pinned filtering path
was resumed; the two matches were then materialized by Pocket itself. No index
or transaction rows were fabricated by the D2 test.

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
$env:D2_POCKET_SOURCE = "_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-real-pocket-source-1.db"
$env:D2_POCKET_DEST = "_work/g3-1-pocket-node/_g3-1r1-evidence/<new-disposable>.db"
$env:D2_POCKET_SCRIPT = "490000001000000030000000310000009BD7E06F3ECF4BE0F2FCD2188B23F1B9FCC88E5D4B65A8637B17723BBDA3CCE80114000000BC5882C4309431EE23AD7BBAD4B5C3325539EEBD"
cargo test -p d2-script-handoff --no-default-features --features sqlite,pocket-sqlite --offline production_pocket_export_validate_import --lib -- --ignored --nocapture --test-threads=1
```

The positive final run is recorded in
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-production-r1-final.log`:

```text
test pocket::tests::production_pocket_export_validate_import ... ok
result: 1 passed, 0 failed
pocket-source tip=22370060
pocket-export ... handoff_height=22370055 index_rows=2 transaction_index_rows=2 transaction_rows=2 artifact_bytes=1767
```

This test used production `D2::export`, canonical artifact encoding, inspect,
destination validation, atomic import, reopen, idempotent validation, and
idempotent re-import. It is a real Pocket storage/profile result with positive
Script-derived rows and closure. It is host-side D2 execution followed by
disposable Pocket application staging; the Pocket checkout has no direct D2
library call.

## 5. No-D2 exact-Script control — completed retry

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

The first attempt below is retained as a diagnostic failed attempt because the
application was still locked. It is not used as evidence. The retry staged the
same baseline, started Pocket, unlocked it through the normal PIN UI, and
captured the actual registration and pinned upstream request path.

The valid retry log is
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-unlocked.log`:

```text
setScripts ... startBlock=20410389
request block filter ... starts at 20410390
recieved block filters: start number: 20410390, filters count: 1000
recieved block filters: start number: 20411390, filters count: 204
```

This is the negative control required by R1. With the exact Script registered
at `H-17`, Pocket's real pinned upstream path requested and processed the
historical range containing `H=20410406`; it later continued from the live
tip. The native store and Room database were disposable copies, and no
production D2 code was involved in constructing this control.

Evidence:

- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-runtime.log`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-after.db`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-room-no-d2-after.db`.

The valid retry additionally produced:

- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-unlocked.log`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-no-d2-unlocked-current.db`;
- `_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-room-no-d2-unlocked-current.db`.

**NO_D2_HISTORICAL_REFILTER = PASS.**

## 6. Production D2 destination on Pocket

The production ignored test
`pocket::tests::production_pocket_export_validate_import` was rerun against
the positive testnet source and a newly created disposable Pocket `kv`
database. It used production `D2::export`, inspect, validate, atomic import,
reopen, and idempotent re-import:

```text
test pocket::tests::production_pocket_export_validate_import ... ok
test result: ok. 1 passed; 0 failed
pocket-source tip=22370060
pocket-export ... handoff_height=22370055 ... index_rows=2 transaction_index_rows=2 transaction_rows=2 artifact_bytes=1767
```

The fresh destination passed SQLite integrity and contained 11,205 rows after
the selected Script registration and six selected derived/closure rows were
installed (two cell-index, two transaction-index, and two transaction rows).
The final production run is recorded in
`pocket-testnet-production-r1-final.log`. This is a production D2 import into
a fresh Pocket storage destination. It is not a D2 importer call inside the
Pocket Android process: the Pocket checkout has no D2 integration surface, so
the resulting native store was staged into the disposable debug app sandbox
for runtime verification.

The imported native store and a fresh Room destination database (wallet/key
rows retained, application cache rows empty) were then staged into the
debuggable app sandbox. After normal unlock, Pocket rebuilt its application
view from the local light-client state: the two imported historical
transactions were visible, and normal continuation found the post-H outgoing
self-transfer. The Room state then contained three transactions, one balance
cache row, and persisted testnet progress through block `22,370,957`.

The clean D2 device log is
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-d2-clean-continuation.log`:

```text
setScripts ... network=TESTNET startBlock=22370055
request block filter ... starts at 22370056
recieved block filters: start number: 22370056, filters count: 898
all matched blocks downloaded, start_number=22370056, blocks_count=892, matched_count=1
Saved sync progress: block 22370947
Final balance: 1999999999000 shannons = 19999.99999 CKB
nativeGetTransaction: found committed tx 0xcfdba9...e6894
Fetched 3 transactions
```

Therefore:

**D2_NO_HISTORICAL_REFILTER_THROUGH_H = PASS** and
**D2_POST_H_CONTINUATION = PASS** for the real Pocket testnet runtime fixture.
The first request after accepting H began at H+1, and the one matched block
was later materialized as the exact Script's post-H transaction. Both facts
are observed in pinned upstream log output and Pocket application output, not
inferred from the cursor alone.

The post-H transaction was observed at block `22,370,275` (220 blocks above
H); its transaction key is the captured outgoing transaction
`0xcfdba9...e6894`. Pocket's native store retained the transaction row and the
new exact-Script cell-index rows after the continuation.

## 7. Restart, Room rebuild, and Android measurement

After the positive testnet continuation, Pocket was force-stopped and started
again. The restart log is
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-d2-posth-restart.log`.
It records registration at the persisted post-H point and immediately
reconstructed the same three-transaction application view:

```text
setScripts ... network=TESTNET startBlock=22370957
Final balance: 1999999999000 shannons = 19999.99999 CKB
nativeGetTransaction: found committed tx 0xcfdba9...e6894
Fetched 3 transactions
```

After that process death/reopen, the WAL-backed Room query returned testnet
`lightStartBlockNumber=22370055` and `localSavedBlockNumber=22370957` in the
clean continuation capture; the later measured restart registered at
`22371031`. SQLite integrity checks returned `ok` for both Room and native
storage, including the captured WAL files. The exact Script registration
remained present and unrelated native row families were not replaced by the
D2 operation.

The final testnet Android measurement is in
`_work/g3-1-pocket-node/_g3-1r1-evidence/pocket-testnet-d2-android-measure.log`
and `pocket-testnet-d2-android-meminfo.txt`, collected on the Samsung
SM-S9180:

- `adb shell am start` invocation: 142 ms (the process then performed normal
  unlock and local-state rebuild);
- total PSS: 293,146 kB;
- total RSS: 416,108 kB;
- restart registration: `startBlock=22371031`;
- application result: three transactions and the post-H exact-Script cells.

These are Pocket-process and normal-continuation measurements, not a claimed
Android-native D2 import benchmark. The D2 import itself remains a host-side
library operation whose output was staged into Pocket's disposable sandbox.

The strongest raw-copy comparison was also exercised on disposable device
paths: pushing the captured 1,884,160-byte native store plus 147,456-byte Room
database took 0.24 seconds over ADB. It is smaller operationally, but it
copies Pocket's whole native database and application database, is
backend/profile/version coupled, and carries unrelated chain state. Pocket's
existing encrypted key-backup flow was inspected separately; it restores
wallet key material, not light-client history. No Pocket-specific historical
migration alternative exists in the checkout.

## 8. Remaining lifecycle limits and decision

No required G3-1R1 property remains unproven. The following boundaries remain
explicit:

1. D2 export/import was invoked by the production host library; Pocket's
   checkout has no direct D2 API call. The imported native store was staged
   into a fresh Pocket destination and exercised by Pocket's real runtime.
2. Android measurements cover staging, restart, local-state rebuild, and
   continuation. They are not measurements of a D2 importer linked into the
   Pocket process.
3. No Pocket-specific historical migration implementation exists, so the
   alternative comparison is against the real full database copy and Pocket's
   existing key-backup path, not a nonexistent serializer.
4. The result is one exact Script and one role on testnet. It does not claim
   multi-Script practicality, wallet/app-cache migration, or production
   adoption.

## 9. Current G3-1R1 decision

| Gate | Result | Evidence basis |
|---|---|---|
| Real wallet and exact registered Script | PASS | Pocket UI creation and real `FILTER_SCRIPTS` key in captured `store.db` |
| Real Script-bearing Pocket database | PASS | 11,205-row testnet Pocket SQLite capture; selected cursor, two index rows, two transaction-index rows, and two closure transactions |
| Pocket SQLite profile | PASS | Source comparison plus explicit adapter/profile check |
| Production D2 export/inspect/validate/import/reopen | PASS, host-side Pocket DB | New production test against positive testnet `store.db`; 1,767-byte artifact |
| No-D2 exact-Script historical refilter | PASS | Unlocked retry registered at H-17 and logged requests starting at 20410390, through H |
| D2 destination import and no-refilter proof | PASS with boundary qualification | Production D2 imported a fresh Pocket `kv` destination on host; output was staged into Pocket; clean device log starts at H+1 |
| Room/application rebuild | PASS | Pocket rebuilt two imported transactions, then three after post-H continuation; WAL-backed sync progress persisted |
| Post-H exact-Script continuation | PASS | Pinned upstream matched one post-H block; Pocket materialized the outgoing transaction and exact Script cells |
| Android restart/process death | PASS within controlled boundary | Force-stop/reopen and WAL-backed native/Room integrity passed; no power-loss claim |
| Android measurements/alternatives | PASS with boundary qualification | Pocket runtime timing/memory and raw DB-copy timing measured; D2 importer was host-side and no Pocket-specific migration exists |

**G3-1R1 classification: PASS - POCKET EXECUTABLE REFERENCE-FLOW CLOSURE.**

The narrow Pocket adapter is within the frozen D2 boundary. The remaining
qualification is architectural rather than a failed gate: D2 remains a
separate production library, while Pocket consumes its staged native output
through the real application lifecycle. This does not claim Pocket adoption
or direct in-app D2 linkage.
