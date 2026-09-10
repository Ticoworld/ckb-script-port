# G3-1 Pocket acceptance matrix

**Date:** 10 September 2026
**G3-0 checkpoint:** `b86e0a958d50a676c3e062419d4c1194c2b342c3`  
**G3-1 result:** **HOLD** for the broader exploratory matrix; **G3-1R1 PASS** for the required Pocket executable reference-flow closure

This matrix is intentionally binary. A G3-1 PASS requires every required row
to be PASS. A G3-0 selection, source inspection, or D2-only test is not a
substitute for Pocket execution.

| # | Requirement | Evidence / exact test or command | Result | Notes / limitation |
|---:|---|---|---|---|
| 1 | G3-0 checkpoint committed | `git show --stat b86e0a958d50a676c3e062419d4c1194c2b342c3`; commit `G3-0: select Pocket as D2 reference consumer` | PASS | Selection was committed before G3-1 evidence work. |
| 2 | Pocket target revision pinned | `git -C _work/g3-1-pocket-node rev-parse HEAD`; `git show v1.8.3` | PASS | Source HEAD `6eda0b7...`; release `v1.8.3` commit `73f0982...`. |
| 3 | Real restore pipeline reconstructed | Read `LightClientNative.kt`, `GatewayRepository.kt`, `SyncCoordinator.kt`, Room entities/DAOs, `AppDatabase.kt`, `KeyBackupManager.kt`, `WalletMigrationHelper.kt` | PASS | Code-derived architecture map; not runtime proof. |
| 4 | Pocket LC profile fully compared | Compared Pocket `external/ckb-light-client/light-client-lib/src/storage/{mod.rs,db/sqlite.rs,db/native.rs}` with D2 pinned upstream `12e29522...` | PASS | Logical key/value semantics match in the relevant families; physical/API boundary differs. |
| 5 | Supported explicit profile established or existing profile proven compatible | No Pocket adapter added; current D2 profile remains `ckb-light-client@12e29522.../storage-v1` | HOLD | Pocket uses SQLite table `kv`; D2 G1 SQLite uses `kv_store`. Explicit adapter and conformance tests remain. |
| 6 | Real Pocket-compatible source state produced | Pocket release APK launch only; no wallet was created/recovered and no Script was registered | HOLD | No exact Script rows, cursor, matched history, or exportable Pocket source DB. |
| 7 | No-D2 baseline demonstrates historical filtering | `adb logcat` after launch showed native LC proof/filter events, but no wallet Script was registered | HOLD | Runtime LC filtering was observed, but not an exact-Script historical positive control. |
| 8 | D2 export from real source succeeds | No Pocket `store.db` was available to `D2::export` | HOLD | Existing D2 smoke tests are not Pocket evidence. |
| 9 | Fresh destination import succeeds | No D2 artifact was imported into Pocket LC storage | HOLD | Release APK sandbox was non-debuggable; no fresh destination handoff was run. |
| 10 | No historical filter request through H after import | No accepted Pocket handoff H exists; no post-import request trace | HOLD | Existing G1/R1 no-refilter evidence is D2-only. |
| 11 | Negative control historically filters | No-D2 exact-Script destination was not created | HOLD | Device filter traffic without a registered Script is not this control. |
| 12 | Pocket Room/app view reconstructs without historical chain refilter | No Pocket Room DB or imported LC state was available | HOLD | Source shows native queries can feed `cacheManager.cacheTransactions`, but the path was not executed. |
| 13 | Post-H continuation succeeds | No H, post-H block/transaction, or Pocket balance/history result | HOLD | Not proven. |
| 14 | Restart remains coherent | App was launched and force-stopped only before any wallet/import state existed | HOLD | Not a restart-after-handoff test. |
| 15 | Destination chain authority preserved | Preserved in D2 design; no Pocket import executed | HOLD | Design constraint, not Pocket runtime evidence. |
| 16 | Unrelated Pocket/app state not incorrectly imported | No Pocket import or Room mutation | HOLD | D2 contract forbids importing Room/keys, but Pocket-specific proof is absent. |
| 17 | Android execution attempted | `adb install -r _work/g3-1-pocket-node-v1.8.3.apk`; `adb shell am start -n com.rjnr.pocketnode/.MainActivity` | PASS | Real device: SM-S9180, `arm64-v8a`, SDK 36. This row means attempted execution, not mobile qualification. |
| 18 | Mobile resource result documented | `adb shell dumpsys meminfo com.rjnr.pocketnode` after launch | HOLD | Startup-only: 51,784 kB PSS, 170,332 kB RSS; no import/reconciliation measurement. |
| 19 | Multi-Script practicality assessed | Read Pocket `ALL_WALLETS`/`BALANCED`, candidate, and per-wallet registration paths | HOLD | Qualitative risk only; no real wallet Script count or artifact duplication measured. |
| 20 | Strongest DB-copy/rescan/Pocket-specific alternative assessed | Compared documented rescan, full app/LC copy, Pocket key backup, and hypothetical Pocket serializer in report | HOLD | Source-level comparison only; no equivalent Pocket migration timings or file-copy experiment. |
| 21 | Product-vs-Pocket-specific-work boundary survives | D2/Pocket ownership map documented; no end-to-end handoff | HOLD | Boundary is plausible but not proven by a reference product flow. |
| 22 | No D2 scope expansion occurred | `git diff` showed no production D2 change during G3-1; no PV1/multi-Script/signing/cloud changes | PASS | Only evidence docs are added; ignored disposable reference build output is outside the D2 tree. |

## G3-1R1 update (10 September 2026)

G3-1R1 closes the Pocket execution hold. The original rows above preserve the
historical G3-1 starting record; the current executable results below are the
normative R1 evidence. The broader G3-1 matrix remains HOLD only because the
exploratory multi-Script row is not part of the frozen one-Script R1 seam.

| Row | Current result | Current evidence |
|---:|---|---|
| 5 | PASS | New explicit `pocket-sqlite` `PocketSqliteAdapter`, profile `pocket-node@6eda0b7.../ckb-light-client@0.5.4/kv-v1`, and production conformance test. |
| 6 | PASS | Real UI-created wallet and captured 11,205-row testnet Pocket `store.db`; exact 73-byte lock Script registration, two selected index rows, two transaction-index rows, and two closure transactions. |
| 7 | PASS | Unlocked no-D2 retry registered the exact Script at H-17 and the pinned upstream requested filters starting at 20,410,390, through H. |
| 8 | PASS | Production `D2::export` against the real testnet source emitted H=22,370,055 and a 1,767-byte artifact with two index rows, two transaction-index rows, and two closure transactions. |
| 9 | PASS with boundary qualification | Production D2 imported a newly created Pocket `kv` destination on the host; the resulting native store was then staged into the debug Pocket app. The importer itself is not linked into Pocket. |
| 10-21 | CLOSED BY R1 | See the executable retry matrix below; rows 10-18 and 20-21 pass, while row 19 remains an exploratory broader G3-1 hold. |

The full R1 record is in
[`G3_1R1_POCKET_EXECUTION_EVIDENCE.md`](G3_1R1_POCKET_EXECUTION_EVIDENCE.md).

### Current executable retry matrix

| Row | Current result | Current evidence |
|---:|---|---|
| 7 | PASS | Unlocked no-D2 retry registered the exact Script at H-17 and requested the historical range from 20,410,390. |
| 9 | PASS with boundary qualification | Production D2 imported a newly created Pocket `kv` destination on the host; the resulting store was staged into the debug Pocket app. |
| 10 | PASS | Clean testnet D2 startup registered at H=22,370,055 and the first request began at 22,370,056. |
| 11 | PASS | The no-D2 request from 20,410,390 is the negative control showing historical filtering through H. |
| 12 | PASS | Pocket rebuilt two imported historical transactions, then three after continuation; WAL-backed Room progress persisted. |
| 13 | PASS | Pinned upstream matched one post-H block; Pocket materialized the outgoing transaction and exact Script cells. |
| 14 | PASS within controlled boundary | Force-stop/reopen preserved coherent native and Room state; no power-loss claim. |
| 15 | PASS within tested boundary | Native peer/header authority remained in Pocket; source data did not become chain authority. |
| 16 | PASS | Unrelated Pocket rows were preserved by the host import and Room/key state was outside the D2 artifact. |
| 17 | PASS | Debug target ran on Samsung SM-S9180, arm64-v8a, SDK 36. |
| 18 | PASS with boundary qualification | Testnet Pocket restart/rebuild was measured at 142 ms start invocation and 293,146 kB PSS / 416,108 kB RSS; D2 import timing was host-side. |
| 19 | HOLD | Only one real wallet Script was exercised. |
| 20 | PASS with boundary qualification | Full Pocket store+Room copy was timed; existing key backup was confirmed not to migrate LC history. |
| 21 | PASS within tested boundary | The constrained real flow supports the frozen product boundary. |

## Commands and observed runtime evidence

### D2 checkpoint smoke

```powershell
cargo test -p d2-script-handoff --no-default-features --features sqlite --offline
```

Result: **17 passed, 0 failed, 4 ignored**. Reused D2 product test; not a
Pocket integration test.

### Pocket package/runtime

```powershell
git -C _work/g3-1-pocket-node rev-parse HEAD
git -C _work/g3-1-pocket-node status --short
adb install -r _work/g3-1-pocket-node-v1.8.3.apk
adb shell am start -n com.rjnr.pocketnode/.MainActivity
adb logcat -d -t 300
adb shell dumpsys meminfo com.rjnr.pocketnode
```

The release APK installed successfully. Logcat included real
`ckb-light-client` peer sessions, a passed block-proof verification,
`prove_or_download-matched blocks`, and filter-hash processing beginning at
block 1. It did not include a Pocket wallet Script registration or a D2
handoff.

### Release sandbox check

```powershell
adb shell run-as com.rjnr.pocketnode id
```

Observed: `run-as: package not debuggable: com.rjnr.pocketnode`. This prevented
safe extraction or replacement of the private LC and Room files on the
unrooted device.

### Debug build and executable retry

```powershell
.\gradlew.bat :app:assembleDebug
```

The initial direct Windows build failed at `:app:cargoBuild` while starting
`./build-android-jni.sh`; the separated host/Git-Bash attempts exposed the
Android toolchain limitations recorded in the earlier evidence. A subsequent
debug build was produced and installed from
`android/app/build/outputs/apk/debug/app-debug.apk`. `run-as` then worked,
allowing disposable Pocket store/Room staging and the unlocked runtime retry.

## Matrix counts

| Result | Count |
|---|---:|
| PASS | 4 |
| HOLD | 18 |
| FAIL | 0 |

The original four PASS rows are checkpoint/revision/architecture
reconstruction, Android execution attempt, and scope discipline. They do not
satisfy the G3-1 PASS rule. The result was therefore **G3-1 HOLD** at the
starting checkpoint.

### Current G3-1R1 counts

Counting the current executable retry matrix as binary requirement results
gives **21 PASS / 1 HOLD / 0 FAIL**. The sole remaining HOLD is the
exploratory multi-Script practicality row, which is outside the frozen
one-Script R1 closure. Therefore **G3-1R1 PASS**; the broader exploratory
G3-1 matrix remains HOLD.

## Remaining broader G3-1 exploration

G3-1R1 has no required closure item remaining. The broader G3-1 matrix may
still investigate multi-Script practicality if that exploratory question is
kept in scope. Such work must not change D2 v1's one-Script artifact or add
Pocket application integration that is absent from the selected checkout.

If Room or Pocket startup necessarily rewinds and refilters the Script through
H, the hypothesis fails. It must not be hidden as ordinary application
reconciliation and must not be repaired by expanding D2's scope.
