# G3-1 Pocket reference integration

**Research/execution date:** 9 September 2026  
**G3-1 starting D2 HEAD:** `1d2e85ef53bfe94c79ec0a9a665cd64ba0dce860`  
**G3-0 checkpoint:** `b86e0a958d50a676c3e062419d4c1194c2b342c3`  
**D2 HEAD after the G3-0 checkpoint and G3-1 evidence:** recorded by the final commit  
**Classification:** **G3-1 HOLD — INTEGRATION VALUE PLAUSIBLE BUT UNQUALIFIED**

## 1. Executive result

G3-0 selected Pocket Node because it is a current native Android CKB wallet
with an embedded `ckb-light-client`, a separate application database, and
current user-facing historical-sync choices. G3-1 did not prove the planned
handoff hypothesis end to end.

The real Pocket release APK was installed and launched on a connected Android
device. Its embedded light client initialized, connected to peers, and emitted
normal filtering/proof events. The APK is non-debuggable, however, so its
private `store.db` and Room database could not be inspected or replaced using
the available device access. A debug APK could not be produced in this
Windows environment because Pocket's JNI build hook assumes a Unix shell and
the available Rust/Windows linker combinations failed before producing a
usable APK.

No Pocket wallet was created or recovered, no exact wallet Script was
registered, no Pocket-generated Script-bearing source database was produced,
and no D2 artifact was imported into Pocket. Consequently the following
central claims remain unproven:

```text
Pocket source state
  -> production D2 export
  -> fresh Pocket destination
  -> production/profile-compatible import
  -> Room reconciliation
  -> post-H continuation from H+1
  -> no historical filtering through H
```

This is a HOLD because the code and product fit remain plausible, not because
the evidence demonstrated a semantic contradiction in D2. G3-1 must not be
called a Pocket reference integration until the missing executable gates are
closed.

## 2. Scope and evidence rule

This phase tested one narrow hypothesis:

> When an old Pocket installation still has valid light-client state, can one
> exact packed lock Script's derived state be handed to a fresh Pocket
> destination and continued after H without refiltering that Script through H?

The test did not evaluate seed-only recovery. Pocket's keys, wallet identity,
Script discovery, Room data, application caches, UI, and recovery policy stay
outside D2. No PV1 semantics, multi-Script artifact, signing, cloud transport,
or application-cache migration was added.

Evidence labels in this report are:

- **EXECUTED:** directly run during G3-1.
- **CODE-DERIVED:** observed from pinned source/configuration.
- **PUBLIC:** current public release, guide, issue, or pull-request evidence.
- **CARRIED FORWARD:** an accepted G3-0 result, not a G3-1 integration proof.
- **NOT PROVEN:** required evidence that was not obtained.

## 3. Checkpoints and repositories

### D2 repository

The G3-0 selection commit was created before G3-1 work:

```text
G3_0_CHECKPOINT_HEAD = b86e0a958d50a676c3e062419d4c1194c2b342c3
commit = G3-0: select Pocket as D2 reference consumer
branch = master
```

The D2 tree was clean at the start of G3-1. The accepted G2 parent was
`1d2e85ef53bfe94c79ec0a9a665cd64ba0dce860`. The D2 smoke regression was rerun
after the investigation:

```powershell
cargo test -p d2-script-handoff --no-default-features --features sqlite --offline
```

Result: **17 passed, 0 failed, 4 ignored**. This confirms the existing D2
product core still reproduces its accepted local contract; it is not Pocket
integration evidence.

### Pocket target

The separate disposable checkout was:

```text
_work/g3-1-pocket-node
repository: https://github.com/RaheemJnr/pocket-node
tested source HEAD: 6eda0b7a4601050b011591d41cc702f0dc7a7c38
stable release: v1.8.3
release commit: 73f0982b7c6ae6aa10b8e42f6dec8abfa9ceb327
```

The tested source HEAD is 23 commits after the v1.8.3 release tag, so the
release APK and the source tree are recorded separately. The release APK
installed on the device was the published v1.8.3 artifact. The Pocket source
checkout had no tracked changes after the attempts; build outputs and the
temporary Android build workaround were confined to the ignored disposable
workspace.

Public references:

- [Pocket Node repository](https://github.com/RaheemJnr/pocket-node)
- [Pocket Node v1.8.3 release](https://github.com/RaheemJnr/pocket-node/releases/tag/v1.8.3)
- [Pocket user guide](https://github.com/RaheemJnr/pocket-node/blob/main/docs/USER_GUIDE.md)
- [restore-history issue #431](https://github.com/RaheemJnr/pocket-node/issues/431)
- [rescan-loop fix PR #360](https://github.com/RaheemJnr/pocket-node/pull/360)

## 4. Pocket target facts

| Item | Observed value | Evidence class |
|---|---|---|
| Pocket stable release | `v1.8.3`, release commit `73f0982...` | PUBLIC / CODE-DERIVED |
| Source tree used for archaeology | `main` at `6eda0b7...` | EXECUTED |
| Embedded light-client package | `ckb-light-client-lib` version `0.5.4` | CODE-DERIVED: `external/ckb-light-client/light-client-lib/Cargo.toml` |
| Recoverable upstream Git commit | Not separately recoverable; the embedded source has no nested Git repository | CODE-DERIVED |
| Android compile/min/target SDK | 36 / 26 / 35 | CODE-DERIVED: `android/app/build.gradle.kts` |
| Pocket native ABI configuration | `arm64-v8a`, `armeabi-v7a`; optional x86_64 build flag | CODE-DERIVED |
| Device attempted | Samsung SM-S9180, ABI `arm64-v8a`, SDK 36 | EXECUTED |
| JNI surface | `nativeInit`, `nativeStart`, `nativeStop`, `nativeSetScripts`, `nativeGetScripts`, `nativeGetCells`, `nativeGetTransactions` and related queries | CODE-DERIVED: `LightClientNative.kt` |
| LC database | `filesDir/data/<network>/store.db` | CODE-DERIVED: `GatewayRepository.kt` |
| LC network data | `filesDir/data/<network>/network` | CODE-DERIVED: `GatewayRepository.kt` |
| Room database | `pocket_node.db` | CODE-DERIVED: `AppModule.kt` |
| Room schema version | 15 | CODE-DERIVED: `AppDatabase.kt` |
| Room sync table | `sync_progress`, PK `(walletId, network)` | CODE-DERIVED |
| Room sync fields | `lightStartBlockNumber`, `localSavedBlockNumber`, `updatedAt` | CODE-DERIVED |

## 5. Pocket restore and synchronization architecture

The inspected architecture is:

```text
Pocket wallet/key flow
  -> derive address and exact lock Script
  -> GatewayRepository chooses sync start
  -> SyncCoordinator calls JNI nativeSetScripts
  -> embedded ckb-light-client filters blocks into store.db
  -> Pocket reads native cells/transactions
  -> Pocket derives balances/history and writes Room caches
  -> Room/UI owns the application presentation state
```

### Native LC initialization

`GatewayRepository.initializeNode` copies a network TOML asset, rewrites the
store and network paths to the Pocket private directory, calls
`LightClientNative.nativeInit`, and then calls `nativeStart`. The source also
contains comments that in-process reinitialization is not reliable because
`nativeStop` can block while peers are connected and `nativeInit` rejects an
already initialized client. This is important for a future D2 integration:
the product boundary likely requires process-level quiescence or a Pocket-side
restart protocol, not a simple in-process boolean.

### Script registration and progress

`GatewayRepository.registerAccount` obtains the native tip and existing local
progress, chooses a block based on sync mode/progress, constructs
`JniScriptStatus(script=..., scriptType="lock", blockNumber=...)`, and calls
`setScriptsAndRecord`. `SyncCoordinator.setScriptsAndRecord` invokes
`nativeSetScripts`, stores the per-wallet start block in Room, and maintains an
args-to-wallet mapping for progress fan-out.

Pocket's `sync_progress` is application-owned bookkeeping. It is not the
light client's canonical Script-index storage and is not part of D2 v1.

### Local state reads and Room materialization

`GatewayRepository.refreshBalance` reads native cells and native transactions,
walks pagination, subtracts spent outpoints, and derives live balance. It has
an explicit zero-cell rescue path that can rewind the Script registration to
roughly 100 blocks before the earliest observed transaction.

`GatewayRepository.getTransactions` walks native transaction pages, groups
cell interactions, resolves headers, derives direction/DAO presentation, and
calls `cacheManager.cacheTransactions` to upsert the resulting application
records into Room. This shows that local LC rows can be the input to Room
reconstruction, but source inspection alone does not prove that every startup
path after an external LC import avoids Pocket's rescan policies.

### Secrets and application state

`KeyBackupManager` handles encrypted key material, while `WalletMigrationHelper`
handles Room-side wallet/progress migrations. `AppDatabase` contains wallets,
key material, sync progress, transactions, balance/header caches, DAO rows,
pending records, contacts, and sub-account candidates. None of those are
silently imported by D2.

## 6. Profile conformance result

### Classification: EXPLICIT PROFILE ADAPTER REQUIRED

The comparison did not find a change to the logical D2 responsibility, but it
did find a physical/profile boundary that the current D2 adapter does not
support.

The Pocket `0.5.4` storage source preserves the relevant logical semantics:

- key prefixes `0`, `32`, `64`, `96`, `128`, `160`, `192`, `208`, and `224`;
- `TxHash`, cell Script, transaction Script, block, checkpoint, and meta key
  families;
- raw Script identity as code hash + hash type + raw args;
- role byte `0` for lock and `1` for type in Script-filter metadata;
- big-endian block/index portions in Script index keys;
- Script index values that are transaction hashes;
- transaction values containing block number, transaction index, and serialized
  transaction;
- `ScriptStatus { script, script_type, block_number }`;
- `LAST_STATE` carrying little-endian total difficulty followed by the tip
  header;
- rollback code that deletes/rebuilds Script-derived index rows and updates
  Script progress.

The material profile difference is the SQLite representation and API boundary:

| Profile | Physical store | API/source boundary | Result |
|---|---|---|---|
| D2 G1 profile | `kv_store(key BLOB PRIMARY KEY NOT NULL, value BLOB NOT NULL)` plus index | Pinned upstream `StorageBackend` / `LightClientStorage` traits at `12e2952...` | Existing D2 `UpstreamAdapter` |
| Pocket embedded profile | `kv(key BLOB PRIMARY KEY, value BLOB)` with Pocket's direct storage implementation | No `storage_trait.rs`; Pocket's own `Storage` methods | Requires explicit adapter |

Pocket's release build comments out the RocksDB dependency and uses SQLite for
the Android light client. Therefore the observed Pocket target is SQLite-only
for this integration, even though D2 G1 supports both RocksDB and SQLite.

The correct G3-1 response is a narrowly named Pocket profile adapter that
reads/writes the `kv` table and preserves the existing canonical artifact and
authority semantics. No such adapter was added in this phase because a real
Pocket Script-bearing source and destination could not be constructed; adding
one without that executable conformance target would turn an unverified
mapping into product code.

This is not a MATERIAL SEMANTIC MISMATCH on the evidence available. It remains
an explicit adapter qualification gate.

## 7. Real Android execution

### What was executed

The published v1.8.3 APK was downloaded and installed with:

```powershell
adb install -r _work\g3-1-pocket-node-v1.8.3.apk
adb shell am start -n com.rjnr.pocketnode/.MainActivity
```

The app launched to the real Pocket onboarding screen. After a clean launch,
logcat showed the embedded `ckb-light-client` connecting to peers, passing a
block proof, entering `prove_or_download-matched blocks`, and processing a
filter-hash request with `start: 1, len: 2000`. This is genuine runtime
evidence for Pocket's embedded LC, but no wallet Script had been registered.

The startup-only memory sample was:

```text
TOTAL PSS: 51,784 kB
TOTAL RSS: 170,332 kB
Native Heap: 15,992 kB
```

It is not an import, historical sync, or reconciliation measurement and must
not be used as a mobile viability result.

### What was not possible

The release package reported by `run-as`:

```text
run-as: package not debuggable: com.rjnr.pocketnode
```

Consequently the LC database and Room database could not be extracted or
replaced on the unrooted device. No wallet was created: a deliberate attempt
to enter the create flow reached the handset's Samsung secure-wallet pattern
prompt and was backed out. The Pocket process was force-stopped afterward.

A debug build was attempted. The observed blockers were:

1. Gradle `:app:assembleDebug` could not start `./build-android-jni.sh` on
   Windows.
2. The script's global Android `RUSTFLAGS` contaminated host build-script
   linking.
3. The PATH-selected Windows Rust/linker combinations failed respectively on
   Android target discovery, the missing Android stub header, missing MSVC
   `link.exe`, and GNU `-lgcc` libraries.

These are environment/build reproducibility findings, not evidence that the
Pocket Rust source is semantically invalid. They prevent the required
debuggable end-to-end test in this workspace.

## 8. Real source-state construction and baseline

### Source state

**NOT PROVEN.** No Pocket wallet was created or recovered, so there is no
Pocket-generated exact packed Script, no registered Script cursor, no matched
transaction history, and no source `store.db` suitable for D2 export.

The actual LC runtime did create/use its disposable network state and perform
ordinary chain filtering/proof work. That state is not a Script-bearing
beneficiary fixture and cannot satisfy the source-state gate.

Required future record, not fabricated here:

```text
NETWORK:
SCRIPT / ROLE:
START BLOCK:
HANDOFF H / HASH:
MATCHED HISTORY:
SOURCE DB:
POCKET STATE CREATION PATH:
```

### No-D2 rescan baseline

**NOT PROVEN for an exact Pocket Script.** The device log demonstrates that
the embedded client can issue ordinary filter work, but because no wallet was
created and no Script was registered, it is not a valid positive control for
historical filtering of the selected Script.

The code-derived baseline is nevertheless clear: new or recovered wallets
choose a sync window in `registerAccount`, and Pocket's guide documents
recent/custom/full-history modes. The public guide describes full history as
an hours-scale/overnight operation, and issue/PR history records user-visible
restore/rescan problems. Those facts justify the beneficiary hypothesis but
do not replace a measured G3-1 control.

## 9. D2 handoff, refilter, Room, and continuation results

All rows in this section are **NOT PROVEN** in the Pocket integration.

### D2 export

No production `D2::export` was run against a Pocket-generated source database.
The existing D2 G1 exporter was only smoke-tested against its supported pinned
profile. Pocket's `kv` profile was not silently treated as the G1 `kv_store`
profile.

### Fresh destination import

No fresh Pocket destination LC database received a D2 artifact. The required
exclusive stop/import/reopen sequence was therefore not exercised through
Pocket's lifecycle.

### No historical refilter through H

No accepted Pocket handoff H exists in this run, so there is no valid
post-import request trace. The existing G1/R1 no-refilter evidence is D2
production evidence, not Pocket evidence.

### Room/application reconciliation

No Pocket Room database was populated or inspected in this run. Source code
shows a plausible local path—native LC transaction/cell queries feed Room
cache writes—but it does not prove that Pocket's startup, zero-cell rescue,
candidate discovery, or sync coordinator will not intentionally rewind the
imported Script. This is a required G3-1 gate.

### Post-H continuation

**NOT PROVEN.** No H, post-H block, post-H transaction, Pocket balance, or
Pocket history result was observed.

### Restart/process death

The release app was launched and force-stopped as a runtime check, but no
imported Script state existed. This is not a restart-after-handoff result.

### Destination authority

The D2 contract still requires Pocket's destination LC to own headers, tip,
consensus/proof state, rollback, and future filtering. No source authority was
imported. This is a preserved design requirement, not an executed Pocket
result.

## 10. Real migration unit and multi-Script practicality

The G3-1 unit remains one exact packed lock Script plus `lock` role. Pocket's
actual code derives and registers more than one application-relevant Script in
some flows: it has multiple wallets, sub-account candidates, and an
`ALL_WALLETS`/`BALANCED` registration strategy. `CMD_SET_SCRIPTS_ALL` replaces
the registered set, and candidate registration is part of that orchestration.

The practical future flow would therefore be sequential independent D2
operations coordinated by Pocket, with Pocket retaining wallet and candidate
policy. No atomic multi-Script package was added.

Classification: **UNQUALIFIED PRODUCT RISK**, not a proven blocker. The normal
number of Scripts and closure overlap were not measured because no wallet was
created. A later G3-1 retry must record Script count, duplicate closure bytes,
and total artifact size rather than assume one Script is representative.

## 11. Resource and mobile result

G2 recorded a stress artifact of approximately 10.78 MiB, sampled SQLite RSS
of approximately 78.6 MiB, and approximately 24.9 seconds for the shared
stress SQLite import. Those are D2/G2 measurements, not Pocket-device
measurements.

The only G3-1 device measurement is startup idle memory (51.8 MiB PSS / 170.3
MiB RSS). There is no Pocket export, artifact transfer, import, Room rebuild,
or long-history measurement.

Classification: **MOBILE UNTESTED / RESOURCE RESULT HOLD**. The phone and ABI
were available, but the non-debuggable release and failed debug build
prevented the required operation-level qualification.

## 12. Alternatives attack

### Mnemonic plus rescan

This is Pocket's strongest recovery alternative because it works after the old
device is lost. It is also the reason D2 cannot claim seed-only recovery. When
the old LC state is still available, D2 could remove the selected Script's
historical refilter and network dependence; that advantage was not measured
in Pocket.

### Full Pocket database copy

A same-device/full-install copy could be faster when the requirement is to
clone the whole application and the exact Pocket version, database schema,
keys, native store, and Android sandbox can all be moved safely. It carries
unrelated chain/application state, is coupled to file layout and versions, and
does not establish a selective destination-owned handoff. D2's proposed value
is selectivity and backend/profile mediation, not speed for whole-state
cloning. No live file-copy experiment was performed.

### Pocket-specific migration

Pocket could add its own serialization and restoration of LC rows, Room data,
and app state. That might be simpler for a Pocket-only migration, but it would
couple the mechanism to Pocket's application schema and would tempt transfer
of keys, caches, and global LC authority. D2 remains valuable only if the
reusable lower-layer artifact/adapter boundary removes meaningful work for
more than one consumer. G3-1 did not yet demonstrate that in execution.

### Current verdict on alternatives

The alternatives do not kill the hypothesis from source evidence alone. The
actual comparison remains **UNQUALIFIED** because no equivalent Pocket timing,
bytes, restart, or Room result was obtained.

## 13. Product responsibility versus Pocket-specific work

The intended boundary is coherent on paper:

| D2 owns | Pocket owns |
|---|---|
| Exact-Script derived-state portability | Keys and wallet identity |
| Canonical deterministic artifact | Script discovery and wallet/sub-account policy |
| Transaction closure and validation | Migration trigger and user experience |
| Cross-backend/profile adapter | Room database and application caches |
| Exclusive atomic LC import | Balance/history/DAO presentation |
| Destination authority preservation | Restart and scheduling policy |

The boundary survives the code archaeology, but not yet the product-vs-demo
test. The missing proof must show that Pocket-specific reconciliation is a
thin consumer operation over already-imported local LC state, rather than a
second historical scan that makes D2 irrelevant.

Current result: **BOUNDARY PLAUSIBLE, REFERENCE PRODUCT UNPROVEN**.

## 14. Source-artifact creation reality

D2 helps only while the old source installation/database exists. Pocket's
current public recovery flow is mnemonic-based after device loss, while the
proposed D2 flow needs an intentional export moment before reset, replacement,
or backend transfer. No export UI, background backup, cloud path, or automatic
artifact creation was implemented or tested.

The credible future trigger is:

```text
old Pocket install is healthy
  -> user/developer explicitly stops sync and exports one Script artifact
  -> artifact is moved by an external mechanism
  -> new Pocket install restores keys normally
  -> Pocket imports the LC artifact before resuming sync
```

Whether Pocket can expose that trigger without a large new UX/storage product
remains open.

## 15. G3-1 acceptance summary

The detailed binary matrix is in
[`G3_1_ACCEPTANCE_MATRIX.md`](G3_1_ACCEPTANCE_MATRIX.md). In summary:

- checkpoint and target archaeology passed;
- Pocket architecture/profile comparison passed at the code level;
- the explicit adapter, real source state, D2 handoff, no-refilter proof,
  Room reconciliation, post-H continuation, and restart-after-import gates
  remain HOLD;
- Android execution was attempted and proved native LC startup, but did not
  qualify a migration operation;
- no D2 scope expansion occurred.

## 16. Final classification

**G3-1 HOLD — INTEGRATION VALUE PLAUSIBLE BUT UNQUALIFIED**

Exact blockers:

1. **Pocket profile adapter:** the current D2 adapter does not support
   Pocket's `kv` SQLite profile. A narrowly explicit adapter is required and
   must be tested against a genuine Pocket-created database.
2. **Real source/destination state:** no Pocket wallet Script-bearing source
   and fresh destination were produced, so export/import and authority checks
   were not exercised.
3. **Application proof:** no instrumented Pocket run established no refilter
   through H, local Room reconstruction, post-H continuation, or restart
   coherence.
4. **Mobile operation result:** startup was measured, but import and
   reconciliation resource behavior was not.

The cheapest next resolution is a disposable debuggable Pocket build or an
equivalent controlled Pocket test target that exposes the same JNI/storage
profile. It must create a real wallet Script, populate state through the
actual filtering path, and allow the D2 profile adapter and Pocket-side
reconciliation to be exercised. If Room rebuild requires a historical
refilter, the reference hypothesis should be marked FAIL rather than rescued
by expanding D2.

## 17. Known limitations

- No Pocket source state with a matched exact Script was created.
- No D2 production export/import was run against Pocket storage.
- No Pocket-specific profile adapter was added.
- No D2 artifact was installed into Pocket's LC database.
- No H/post-H transaction continuation was observed.
- No no-D2 exact-Script positive control was observed.
- No Room database was inspected or reconciled.
- No import/restart/process-death test was run on Pocket state.
- The Android measurement is startup-only.
- The build investigation exposed Windows toolchain/build-script blockers;
  it did not establish a Pocket source defect.
- Multi-Script totals and closure duplication remain unmeasured.
- No maintainer or beneficiary was contacted.
- No production D2 semantics were changed.

## 18. Reference-product and funding observation

**REFERENCE PRODUCT MIXED / NOT YET PROVEN.** Pocket is a stronger
beneficiary candidate than a synthetic demo and provides B3/B2 evidence from
its current product and code. G3-1 did not yet show that D2 removes real work
in a user-completable Pocket migration.

Funding classification remains separate: **NO CLEAR FUNDING CONCLUSION**. A
successful Pocket handoff could produce a reference-product case study, but
this run does not establish adoption, maintainer commitment, or funding value.

## 19. Safe next action

Do not begin another consumer integration or expand D2. Resolve the three
technical blockers in a disposable, debuggable Pocket target: obtain a real
Script-bearing source, implement/test only the explicit Pocket profile adapter
if required, and run the instrumented D2-to-Pocket lifecycle. If any of those
tests show mandatory historical LC refiltering or that Pocket-specific work
dominates the value, classify G3-1 FAIL.
