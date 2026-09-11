# G3-0 reference consumer selection

**Research cutoff:** 9 September 2026  
**G3-0 start checkpoint:** `1d2e85ef53bfe94c79ec0a9a665cd64ba0dce860`  
**G2 classification:** PASS — REALISM QUALIFIED  
**Scope:** beneficiary/product-fit review only; no D2 production code or consumer integration was changed.

## Executive result

G3-0 **PASS — REFERENCE CONSUMER SELECTED**.

The selected consumer is **Pocket Node**, the maintained native Android CKB
wallet in `RaheemJnr/pocket-node`.

The selection is based on a concrete current product shape, not historical
association with the project:

- Pocket embeds `ckb-light-client` through JNI and stores the native client
  state separately from its Room application database.
- Pocket exposes new/recent/custom/full-history synchronization choices, and
  its user documentation describes full-history synchronization as an
  hours/overnight operation.
- The repository has an open issue describing history disappearing after
  mnemonic restore, and merged fixes for multi-hour rescue rescans, custom
  restore starts, and incomplete historical activity caching.
- The native lifecycle already has initialization, start, and stop operations,
  and the native storage paths are supplied through a generated configuration.
  This is a plausible quiescent insertion point for D2's existing
  offline/exclusive contract.

The selection has a strict qualification: D2 is useful for Pocket when the
old light-client state is still available and can be exported before or during
an intentional device/install transfer. D2 cannot recreate an old light-client
view from a mnemonic after the source database has already been lost. The
seed/key backup and D2 artifact therefore remain separate parts of any real
Pocket flow.

The exact G3-1 boundary is one real Pocket wallet/network and one exact packed
lock Script plus `lock` role per D2 operation. Pocket may orchestrate several
independent operations sequentially, but G3-1 must not add a multi-Script D2
artifact. Pocket remains the owner of wallet identity, address/sub-account
policy, Room state, UI caches, secrets, and application rescan policy.

## 1. Checkpoint and evidence method

### Repository checkpoint

The local project was verified at:

```text
HEAD: 1d2e85ef53bfe94c79ec0a9a665cd64ba0dce860
working tree: clean at start of review
```

The governing local material was reread:

- `docs/PDEF1_D2_PRODUCT_SCOPE_FREEZE.md`
- `docs/D2_V1.md`
- `docs/G1_ACCEPTANCE_MATRIX.md`
- `docs/G1_R1_LIFECYCLE_EVIDENCE.md`
- `docs/G2_SCALE_REALISM_REPORT.md`
- `docs/G2_ACCEPTANCE_MATRIX.md`

A cheap G1/G2 smoke check was run from this checkpoint:

```powershell
cargo test -p d2-script-handoff --no-default-features --features sqlite --offline
```

Result: 17 passed, 0 failed, 4 ignored (the ignored tests are explicit
cross-backend/worker tests). No production D2 change was needed for G3-0.

### Sources and evidence classes

The review used:

1. Current public repository pages, source files, release pages, issues, and
   merged pull requests.
2. The local provenance checkouts used during review (their machine-local
   paths are intentionally omitted here).
3. The checked-in D-BOOTSTRAP Probe 4 and PV1 evidence manifests.
4. Read-only local `git`, `rg`, and file inspection commands.

Evidence labels in this document mean:

- **MEASURED:** an executed benchmark or test result.
- **CODE-DERIVED:** behavior read directly from source/schema/configuration.
- **USER-REPORTED:** an issue or user-facing report in the consumer repository.
- **INFERRED:** a product-fit conclusion from the preceding evidence.
- **NOT RUN:** no consumer binary, Android device, emulator, or real user flow
  was executed in G3-0.

The D2 repository remains the authority for D2 semantics. The external
repositories establish beneficiary fit and integration constraints; they do
not alter PDEF1, G1, or G2 claims.

## 2. Frozen D2 contract used for the fit test

D2 v1 is a trusted-source, offline/exclusive Rust library that transports one
exact packed Script plus role, typed Script-derived rows, transaction-index
rows, referenced transaction closure, cursor, and one handoff height/hash in a
deterministic backend-neutral artifact. The destination's own light client
remains authoritative for chain identity, headers, tip, consensus, reorgs,
and future filtering.

G2 qualified the product as **CONDITIONALLY BENEFICIAL**. It is not universally
faster than replay and is not a replacement for a whole-client backup. Its
specific value is selective, typed, authority-preserving state transfer,
including supported RocksDB/SQLite crossing, when the source has already done
the historical work.

D2 v1 does not provide a coverage interval ledger, trustless completeness,
application-cache migration, wallet-secret migration, arbitrary multi-Script
bundles, live import, mobile production validation, or arbitrary upstream
version conversion.

## 3. Consumer discovery inventory

| Consumer | Repository / revision inspected | Light-client use | State model | Migration model | Current maintenance |
|---|---|---|---|---|---|
| **Pocket Node** | [RaheemJnr/pocket-node](https://github.com/RaheemJnr/pocket-node), `main` at `6eda0b7a4601050b011591d41cc702f0dc7a7c38`; release `v1.8.3` | Native Android wallet; embedded Rust LC through JNI; local balance/history/transaction queries | Native LC `store.db`/`network` paths plus Room `pocket_node.db`, encrypted key material, sync progress and app caches | Recovery phrase/key backup restores wallet identity; LC history must be reindexed unless old LC state is separately retained | **Current maintained candidate.** Release page shows `v1.8.3`; repository has active 2026 commits/issues/PRs |
| **Neuron** | [nervosnetwork/neuron](https://github.com/nervosnetwork/neuron), `develop` at `9bca6e7d1e1885ad92410f172dbe9e7b958f0637`; `.ckb-light-version` `v0.5.4` | Desktop wallet can launch bundled LC and access it via local RPC | Native LC store; TypeORM SQLite application chain DB; LevelDB descriptions; transaction/cell/DAO/asset caches | Mnemonic/keystore restore creates wallet/address state and start block; application materializes LC transactions into its own stores | **Current maintained candidate**, but whole-wallet desktop state is broader than D2 |
| **Fiber / fiber-ffi** | [nervosnetwork/fiber](https://github.com/nervosnetwork/fiber), plus [joii2020/fiber-ffi](https://github.com/joii2020/fiber-ffi), local FFI revision `774ea9020bde7905acd9f0eec2c9acd46bfbd91d` | FFI work embeds/bridges LC data for a payment/channel node | Fiber owns channel, payment, watchtower, wallet, and node state; LC-derived script data is subordinate | Fiber has its own storage migration and backup/restore model | **Current ecosystem project**, but its principal recovery problem is explicitly outside D2 |
| **ChainPay** | [toastmanAu/chain-pay](https://github.com/toastmanAu/chain-pay) | Electron renderer embeds `@nervosnetwork/ckb-light-client-js` with IndexedDB/OPFS | Browser/WASM LC storage, Zustand treasury config, application UI state | No demonstrated LC backup/restore; reset/resync is documented as deferred | Current public application, but backend and lifecycle do not match G1 adapters |
| **Retric Pocket Wallet** | [RetricSu/pocket-wallet](https://github.com/RetricSu/pocket-wallet) | Browser LC through `ckb-light-client-js`; localStorage and browser storage | Script registration and queries in React context; no D2-shaped portable state | No evidenced backup/restore or migration path | Public but small/low-evidence candidate |
| **lc-snapshots** | Local `D-BOOTSTRAP/repos/light-client-snapshots` provenance checkout, `3c5006d1ddb711939822a50e3c42d62b3ba5d7b3` | Snapshot publisher/exporter, not a consumer | Per-script payloads and publication manifests; no destination importer in the inspected status | Publication/export planning only | Tool/prototype, not a beneficiary |
| **iBytes** | [toastmanAu/iBytes](https://github.com/toastmanAu/iBytes), `main` at `703ec09b1075fd34020cdfe7eff88eaa89c1b744` | Proposed iOS embedded SQLite wallet | Product plan rather than shipped consumer | No current restore/migration implementation | Planning-stage; not eligible as current beneficiary |
| **Wyltek Wallet** | [toastmanAu/wyltek-wallet](https://github.com/toastmanAu/wyltek-wallet), `main` at `b1f4ee9fb589a6daaa5cdb332517388a19f26368` | RPC path shipped; embedded LC explicitly planned | Wallet/Room/SQLCipher/key backup, no current LC state | App/key plans only | Hard architectural mismatch |
| **Cellora** | Local `D-BOOTSTRAP/repos/cellora`, `a534c38f248c0406eeafee94adadb8c2c9072f8a` | CKB indexer using CKB RPC/Postgres, not an LC exact-Script consumer | Server-side indexed blocks/cells and API cursors | Indexer migration/checkpoints, not D2 state | Not a D2 beneficiary |
| **ckb-light-client-lite** | [toastmanAu/ckb-light-client-lite](https://github.com/toastmanAu/ckb-light-client-lite), `main` at `1fdc8c4c8a77a5754f4d6752c873f27e79764532` | Constrained build/distribution derivative | LC build/storage profile, not a consuming application | No user migration path | Tool/build project |
| **WASM demo** | `officeyutong/ckb-light-client-wasm-demo` | Demonstration of browser LC | Demo state only | No real restore flow | Demo only |
| **Ckb-Node / launcher** | `RaheemJnr/Ckb-Node`; `toastmanAu/nervos-launcher` | Incomplete node/launcher work; no evidenced exact-Script user state transfer | Node/service state | No relevant consumer restore path | Not eligible |

The discovery did not find an existing D2 import implementation in Pocket,
Neuron, Fiber, or the other candidates. This is expected at G3-0 and is why
the selection gate precedes G3-1.

## 4. RP2/G2 evidence relevant to beneficiary fit

The repository's prior evidence is sufficient to test whether a consumer's
state shape is compatible with D2, but it is not consumer integration evidence.

| Evidence | What it establishes | Fit implication |
|---|---|---|
| RP2-A/B/C/D and G1/R1 | Exact Script+role, typed rows, transaction closure, cursor/handoff, destination authority, native backend writes, continuation/reorg/crash/exclusivity seam | A consumer with an independently managed LC store can be an adapter target |
| D-BOOTSTRAP Probe 4, `probe4-summary.json` | Pocket/Neuron-like state can be represented as independent exact-Script units; a logical cross-consumer run avoided historical filter scans and did not carry consensus or app-cache state | Supports a reusable lower-layer responsibility, but explicitly was not a Neuron binary or Pocket integration |
| G2 scale report | D2 is conditionally beneficial; stress artifact was 10.78 MiB, sampled SQLite import RSS about 78.6 MiB and import about 24.9 s | A mobile beneficiary needs a real device/resource test in G3-1; no mobile viability claim follows |
| PV1 summary | Current LC and consumer caches expose a current cursor/start value, not complete historical coverage intervals | Pocket's rescan/coverage policy cannot be silently replaced by a D2 cursor |

The Probe 4 cross-consumer run is marked **REUSED ORACLE / NOT PRODUCT
EVIDENCE**. It had equal logical views and zero historical filter scans, but it
did not execute a Pocket or Neuron product binary.

## 5. Selected candidate: Pocket Node

### Current version and real product flow

The inspected Pocket repository is a native Android CKB wallet. Its README
describes an embedded light client running on-device through JNI, and the user
guide says balances, history, and transactions are obtained locally. The
latest inspected release is `v1.8.3`; the release page records community
reported wallet and Nervos DAO fixes.

Relevant public sources:

- [Pocket Node repository](https://github.com/RaheemJnr/pocket-node)
- [Pocket Node v1.8.3 release](https://github.com/RaheemJnr/pocket-node/releases/tag/v1.8.3)
- [Pocket Node user guide](https://github.com/RaheemJnr/pocket-node/blob/main/docs/USER_GUIDE.md)

The current recovery shape is:

```text
old install/device
  -> recovery phrase or encrypted key backup
  -> wallet/address reconstruction
  -> exact Scripts registered with the embedded LC
  -> historical filtering and local transaction/cell reconstruction
  -> Room/UI caches populated
```

The user guide describes Recent as approximately 200,000 blocks, Custom as a
selected historical height, and All History as a genesis scan that can take
hours or overnight. It also explains that changing the sync mode causes a new
sync from the selected start point.

This is **USER-REPORTED plus CODE-DERIVED** evidence of a rescan burden. It is
not evidence that D2 is already a Pocket feature.

### State ownership

| State | Owner | D2 treatment |
|---|---|---|
| Exact LC Script registration, Script-derived index rows, transaction index, referenced transaction closure, current filtered cursor | Embedded `ckb-light-client` storage | D2 candidate payload, subject to the supported profile and exact Script+role boundary |
| LC headers, tip, peer/network state, consensus/proof state, global scheduling | Embedded LC | Destination-owned; never imported as source authority |
| Wallet IDs, derived addresses, sub-account candidates, address discovery policy | Pocket application/wallet policy | Pocket retains and must establish the target Script identity |
| `sync_progress` (`walletId`, network, light start, local saved block) | Pocket Room application DB | Not automatically replaced by D2; G3-1 must define the safe Pocket-side cursor reconciliation |
| Room transactions, balance/DAO caches, pending broadcasts, contacts, UI state | Pocket application/cache | Not in D2 v1; Pocket must materialize or reconcile its own view |
| Encrypted mnemonic/private key material and Android Keystore state | Wallet/security layer | Never in D2 |

The key distinction is that D2 can shorten the LC's historical filter work, but
it does not restore the complete Pocket application database. A successful
integration must prove the application can consume the imported LC view without
mistaking D2's cursor for a proof of historical completeness.

### Code-level evidence pack

The current Pocket source inspected included:

| File / type | Observed behavior |
|---|---|
| `android/app/src/main/java/com/nervosnetwork/ckblightclient/LightClientNative.kt` | JNI `nativeInit`, `nativeStart`, `nativeStop`, status, tip/genesis/header, Script, cell, transaction, and broadcast surfaces exist |
| `.../data/gateway/GatewayRepository.kt` | Creates per-network `data/<network>/store.db` and `network` paths, rewrites the LC config to absolute paths, then initializes/starts JNI |
| `.../data/gateway/SyncCoordinator.kt` | Calls native `setScripts`, records per-wallet start/local progress, clamps or deliberately permits rewinds, and reads native Script status |
| `.../data/database/entity/SyncProgressEntity.kt` | Room table keyed by `(walletId, network)` with `lightStartBlockNumber` and `localSavedBlockNumber` |
| `.../data/database/dao/SyncProgressDao.kt` | Persists and separately updates registration/start and local processed progress |
| `.../data/gateway/RescanPolicy.kt` | Encodes a rescue-rescan decision for zero-live-cell cases |
| `.../data/sync/SyncStallDetector.kt` | Treats forward and backward progress changes as rebaselining events |
| `.../data/database/AppDatabase.kt` | Room database version 15; contains wallet, key material, sync progress, transaction, balance/header/cache, pending, contact, and sub-account entities |
| `.../data/wallet/KeyBackupManager.kt` | Encrypts key material in separate backup files using Argon2id/AES-GCM-era format handling; does not back up LC state |
| `.../data/migration/WalletMigrationHelper.kt` | Migrates Room-side wallet/progress data; not a portable LC Script-state handoff |

Public source links:

- [LightClientNative.kt](https://github.com/RaheemJnr/pocket-node/blob/main/android/app/src/main/java/com/nervosnetwork/ckblightclient/LightClientNative.kt)
- [SyncCoordinator.kt](https://github.com/RaheemJnr/pocket-node/blob/main/android/app/src/main/java/com/rjnr/pocketnode/data/gateway/SyncCoordinator.kt)
- [SyncProgressEntity.kt](https://github.com/RaheemJnr/pocket-node/blob/main/android/app/src/main/java/com/rjnr/pocketnode/data/database/entity/SyncProgressEntity.kt)
- [KeyBackupManager.kt](https://github.com/RaheemJnr/pocket-node/blob/main/android/app/src/main/java/com/rjnr/pocketnode/data/wallet/KeyBackupManager.kt)

The local checkout also shows Pocket's vendored LC library declares version
`0.5.4`, uses bundled SQLite, and comments out the RocksDB dependency. D2's
supported profile is the pinned upstream revision
`12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1`, so this is a **moderate
profile-adapter task**, not an exact G3-0 compatibility claim.

### Current burden and issue/PR evidence

The strongest evidence is not the README alone:

- [Open issue #431](https://github.com/RaheemJnr/pocket-node/issues/431) reports
  that restoring the same mnemonic creates a new local wallet instance whose
  visible transaction history is reset, and suggests re-indexing the same
  address with recent/full/custom choices.
- [Merged PR #360](https://github.com/RaheemJnr/pocket-node/pull/360) records a
  real zero-live-cell case where a rescue rewind caused scans “for hours” and
  fixes a per-launch rescan loop by persisting a per-wallet/network latch.
- [Merged PR #362](https://github.com/RaheemJnr/pocket-node/pull/362) records a
  custom restore height being ignored in favor of the recent window and a
  restore point applying only after restart.
- [Merged PR #388](https://github.com/RaheemJnr/pocket-node/pull/388) fixes
  incomplete full-history materialization into the Room activity cache.
- [Merged PR #407](https://github.com/RaheemJnr/pocket-node/pull/407) documents
  that balances and past amounts depend on the sync reaching the time funds
  first arrived.

This yields beneficiary level **B3**: an active user-facing issue and current
product documentation report the burden. It also yields **B2**: the code and
merged fixes demonstrate workarounds for rescan start, rewind, progress, and
cache reconstruction. There is no evidence of a Pocket owner requesting D2,
so this is not B4.

### Exact D2 fit

The proposed G3-1 flow is:

```text
Pocket source LC state
  -> stop/quiesce Pocket and acquire the D2 SQLite adapter boundary
  -> D2::export(exact packed lock Script, role=lock)
  -> deterministic artifact transfer
  -> restore the same Pocket wallet identity separately
  -> stop/quiesce destination JNI/Room sync writers
  -> D2 inspect/validate/import into destination LC SQLite state
  -> close/reopen native LC and Pocket
  -> Pocket reads the imported LC view and continues from H+1
```

The exact work D2 can remove is the destination's repeated historical LC
filter/index pass through accepted H for the selected Script, plus the need to
copy or merge the entire source LC database merely to move that Script's
derived state. D2 cannot remove:

- mnemonic/private-key restoration;
- Pocket address and sub-account discovery;
- Room transaction/balance/DAO/UI cache reconciliation;
- any additional Script operations that Pocket chooses to perform;
- post-H chain verification, filtering, spends, or reorg handling;
- recovery after the only source copy of the old LC database has been lost.

That is enough real work to justify a reference integration, provided G3-1
proves that Pocket's application layer can consume the imported rows without
silently starting a historical refilter.

### Strongest alternatives for Pocket

| Alternative | Why it is strong | Why D2 can still be preferable | D2 limitation |
|---|---|---|---|
| Full historical rescan | Works from mnemonic alone and leaves destination LC authoritative | No source database is needed, but it repeats the documented hours/overnight work and is awkward for recovery UX | D2 cannot help if the old source state is already gone |
| Copy the whole Android app/LC database | Potentially fastest if the old device and exact build/storage are accessible | Android sandboxing, backend/version coupling, unrelated state, and chain-authority transfer make it a poor selective device-transfer contract | Same-backend whole-state copy wins when whole-state cloning is truly the requirement |
| Pocket key backup / recovery phrase | Necessary for secrets and wallet identity | D2 composes with it by carrying non-secret LC-derived state | Key backup alone omits LC history |
| Pocket-specific rescan/progress logic | Already integrated and can handle app policy | D2 can supply the expensive derived LC view beneath it | Existing logic remains necessary for scripts, caches, and coverage policy |

The strongest rival is therefore **Pocket's own recovery phrase plus ordinary
rescan**, not a strawman. D2's advantage is conditional: a planned old-state
transfer can avoid the historical pass while preserving the destination's
chain authority and avoiding a whole-database copy.

### Multi-Script practicality

Pocket supports multiple wallets, HD sub-accounts, candidate discovery, and
multiple lock variants. A normal full wallet can therefore need more than one
exact Script. D2 v1 remains one Script+role per operation. Sequential imports
are acceptable for G3-1 only if:

1. Pocket chooses the exact Script set itself;
2. every operation remains independently validated and atomic;
3. overlapping transaction closure is handled idempotently;
4. the app does not present a partially restored multi-Script wallet as
   complete;
5. no new D2 multi-Script artifact is introduced.

If a normal reference flow requires hundreds or thousands of operations, that
is a G3-1 product risk and may kill the fit. G3-0 does not assume it away.

### SQLite/mobile-style fit

Pocket is the strongest mobile-shaped candidate, but mobile viability is not
proven. G2 measured a largest completed stress artifact of about 10.78 MiB,
sampled SQLite import RSS of about 78.6 MiB, and about 24.9 seconds for shared
stress SQLite import. The correct classification is:

**RISKY — NEEDS DEVICE PROOF IN G3-1.**

There is no obvious architectural blocker because Pocket already embeds SQLite
LC state and exposes a stop/start JNI lifecycle. Android memory pressure,
temporary storage, activity/process death, and actual UI/cache behavior remain
unanswered.

### Score

| Dimension | Score | Evidence |
|---|---:|---|
| Real beneficiary evidence | 4/4 | Current released Android wallet with embedded LC and active product work |
| Migration/rescan pain | 4/4 | User guide, open restore-history issue, hours-long scan and merged rescan fixes |
| D2-specific work removed | 3/4 | Historical LC refilter and whole-DB selective-transfer burden; source artifact still required and Room remains |
| Fit with frozen D2 contract | 2/3 | Exact lock Script and native SQLite fit; multi-Script orchestration and app progress remain |
| Superiority to strongest alternative | 3/3 | Better selectivity/authority boundary than app/LC DB copy; avoids rescan when source exists |
| Integration feasibility | 1/2 | JNI lifecycle/path exists, but Android bridge, profile adapter, and Room reconciliation are real work |
| Version/profile feasibility | 1/2 | Vendored `0.5.4` versus D2 pinned `12e2952...`; moderate adapter qualification required |
| Reference-product value | 2/2 | A real mobile wallet recovery/sync path exercises the actual D2 responsibility |
| **Total** | **20/24** | **STRONG G3 CANDIDATE** |

### Verdict

**SELECTED.** Pocket Node is suitable for one bounded G3-1 reference
integration, with the source-artifact and single-Script qualifications above.

## 6. Secondary candidate: Neuron

### Evidence pack

The inspected Neuron checkout is `develop` at
`9bca6e7d1e1885ad92410f172dbe9e7b958f0637`, package version `0.204.1`, and
`.ckb-light-version` `v0.5.4`. The public repository remains current and
maintained, and its latest release page is [Neuron 0.204.1](https://github.com/nervosnetwork/neuron/releases/tag/v0.204.1).

Neuron's light synchronizer:

- obtains Script statuses from the LC `get_scripts` RPC;
- associates them with application `SyncProgress` by exact Script hash;
- calls `get_transactions` over a per-Script block range;
- writes transaction hashes and then enriches/persists transaction data;
- advances per-Script `syncedBlockNumber` and application-level progress.

The important inspected files are:

- [`light-synchronizer.ts`](https://github.com/nervosnetwork/neuron/blob/develop/packages/neuron-wallet/src/block-sync-renderer/sync/light-synchronizer.ts)
- [`sync-progress.ts`](https://github.com/nervosnetwork/neuron/blob/develop/packages/neuron-wallet/src/database/chain/entities/sync-progress.ts)
- [`services/sync-progress.ts`](https://github.com/nervosnetwork/neuron/blob/develop/packages/neuron-wallet/src/services/sync-progress.ts)
- [`controllers/wallets.ts`](https://github.com/nervosnetwork/neuron/blob/develop/packages/neuron-wallet/src/controllers/wallets.ts)
- [`export-history.ts`](https://github.com/nervosnetwork/neuron/blob/develop/packages/neuron-wallet/src/utils/export-history.ts)

The `sync_progress` entity has exact Script components/hash, `scriptType`,
wallet ID, `lightStartBlockNumber`, `localSavedBlockNumber`,
`syncedBlockNumber`, cursor, delete flag, and address type. `clearWalletProgress`
resets local/synced progress. Mnemonic/keystore import creates wallet/address
state and a start block, while the application later rebuilds its own
transaction and cell materialization. The application DB is TypeORM SQLite,
with additional LevelDB transaction descriptions and application-specific
DAO/asset/cache state.

The local D-BOOTSTRAP Probe 4 reconstruction found:

- deleting the LC store repeats historical filtering and also clears relevant
  application chain rows;
- restoring a wallet through `importMnemonic` does not carry LC indexed state;
- if the application DB is lost while LC state survives, historical filtering
  can be avoided but local LC enumeration, a thin adapter, and possible
  predecessor fetches remain;
- the cross-consumer logical experiment rebuilt Neuron-like transaction/output
  views from a Pocket-like exact-Script package with zero historical filter
  scans, but it did not run the Neuron binary.

### Fit and limits

D2 would remove the LC historical filter/reconstruction portion of a Neuron
restore, but it would not restore the Neuron wallet database, TypeORM rows,
LevelDB descriptions, DAO/asset policy, generated addresses, or secrets. On a
desktop system, copying the whole application/light-client installation is a
stronger alternative for same-version whole-wallet restore. D2 is useful only
for a selective Script handoff, backend boundary, or authority-preserving
lower-layer restore.

### Score

| Dimension | Score | Evidence |
|---|---:|---|
| Real beneficiary evidence | 3/4 | Current maintained wallet with actual LC mode and Script progress code |
| Migration/rescan pain | 3/4 | Start-block and per-Script progress/reset/rebuild logic; no direct current D2 request found |
| D2-specific work removed | 2/4 | Avoids LC historical work but leaves substantial application reconstruction |
| Fit with frozen D2 contract | 2/3 | Exact Script rows fit; many scripts and app-owned state do not |
| Superiority to strongest alternative | 1/3 | Whole desktop DB/application restore can be stronger for whole-wallet recovery |
| Integration feasibility | 1/2 | Child-process/RPC lifecycle is possible but invasive and not exercised |
| Version/profile feasibility | 2/2 | Native LC profile family is close, though exact build/profile still needs conformance |
| Reference-product value | 2/2 | A real application would exercise the lower-layer boundary |
| **Total** | **16/24** | **POSSIBLE G3 CANDIDATE; not selected** |

### Verdict

**NOT SELECTED.** Neuron is credible, but the first reference integration
would spend too much effort rebuilding Neuron's application-owned state while
demonstrating only a partial benefit. It remains a reasonable future
candidate if a selective light-client restore is a real Neuron requirement.

## 7. Killed consumers and exact reasons

| Consumer | Score / status | Why it looked promising | Exact killer |
|---|---:|---|---|
| Fiber / fiber-ffi | 10/24; **KILL** | Current payment ecosystem with LC/FFI and explicit mobile/storage work | The valuable state is Fiber channel/payment/watchtower/node state. D2 explicitly does not migrate that state; LC Script state is not the principal recovery artifact. Hard architectural mismatch overrides score |
| ChainPay | 8/24; **KILL** | Current-looking payroll/treasury application with embedded LC and comments about expensive history | LC is WASM in Electron renderer IndexedDB/OPFS; no current backup/restore flow; no G1 backend/lifecycle match; D2 would require a new storage profile and invented user path |
| Retric Pocket Wallet | 6/24; **KILL** | Real browser wallet uses exact Script registration and LC transaction queries | No evidence of material migration/rescan pain or backup/restore; browser storage is outside the supported native profile; maintenance/user evidence is too weak |
| iBytes | 2/24; **KILL** | Proposed iOS embedded SQLite wallet with multiple accounts | Repository is a build plan, not a shipped maintained consumer with an existing migration burden |
| Wyltek Wallet | 2/24; **KILL** | Wallet/security/database work and possible future mobile consumer | README says RPC is shipped and embedded LC is planned; no current exact-Script LC state |
| Cellora | n/a; **KILL** | CKB data/indexing and cursor work | PostgreSQL full/indexer service, not ckb-light-client-derived Script state and not a client restore beneficiary |
| lc-snapshots | n/a; **KILL AS CONSUMER** | Per-Script portable snapshot/export shape overlaps the data problem | Publisher/tooling repository; inspected status had no destination importer or real consumer restore flow |
| ckb-light-client-lite | n/a; **KILL AS CONSUMER** | SQLite/musl constrained distribution could help embedded deployments | It is a build/distribution derivative, not an application with user-owned Script history or migration pain |
| WASM demo | n/a; **KILL** | Demonstrates browser LC | Demo/fixture only; no real user recovery or maintained product path |
| Ckb-Node / nervos-launcher | n/a; **KILL** | Names suggest local-node/mobile availability | No evidenced exact-Script-derived consumer state handoff or restore path |

Fiber's current official repository and [fiber-ffi documentation](https://github.com/joii2020/fiber-ffi) were useful negative evidence: they show a real LC boundary but also make clear that Fiber-specific RPC, channel, payment, and node policy are application responsibilities. This is precisely the kind of state D2 must not absorb.

## 8. Candidate ranking

1. **Pocket Node — 20/24 — SELECTED, STRONG G3 CANDIDATE.**
2. **Neuron — 16/24 — POSSIBLE, not selected.**
3. **Fiber / fiber-ffi — 10/24 — killed by hard state-ownership mismatch.**
4. **ChainPay — 8/24 — killed by backend/lifecycle and missing user path.**
5. **Retric Pocket Wallet — 6/24 — killed by insufficient burden evidence.**
6. iBytes, Wyltek, Cellora, lc-snapshots, ckb-light-client-lite, WASM demo,
   Ckb-Node, and launcher — killed as plans/tools/demos or hard mismatches.

At most one candidate is selected. The selection is Pocket Node.

## 9. Why D2 removes real work for Pocket

The narrow real problem is:

> A Pocket user or operator who still has a functioning old installation has
> already paid the cost of deriving one wallet Script's historical LC view;
> a new supported Pocket installation should be able to receive that derived
> view without repeating the same historical filter pass or copying the whole
> authority-bearing database.

D2 removes, for the selected Script:

- historical Script filtering/indexing through H on the destination;
- backend-specific raw database layout dependence;
- transfer of unrelated Scripts and global chain state;
- the need for Pocket to treat source headers/tip/consensus as authority;
- a portion of the recovery-time rescan and its network/battery/storage cost.

D2 does not remove the need to:

- restore keys and wallet identity;
- decide which Scripts Pocket owns;
- rebuild or reconcile Pocket Room state;
- handle sub-account discovery and candidate policy;
- continue normal LC verification after H.

This is meaningful lower-layer work, but it is not a complete wallet restore.

## 10. Product versus demo test

The selection passes the product-vs-demo test at the **selection** stage:

```text
existing maintained Android wallet
  -> existing restore/rescan burden
  -> D2 inserted below the app's wallet policy
  -> exact Script state transported selectively
  -> app retains keys/caches/policy
  -> destination LC continues under its own authority
```

It would fail G3-1 if the result were only a disposable sidecar, fake Script,
synthetic database, or JNI-independent demo. G3-1 must use a real Pocket build,
real native SQLite state, a real wallet-derived exact Script, the existing
Pocket lifecycle, and an observable app-level continuation result.

No Pocket binary, Android device, emulator, or user-facing workflow was run in
G3-0. That is deliberately a G3-1 gate, not hidden evidence.

## 11. Integration feasibility and ownership

Classification for Pocket is:

**EXTERNAL INTEGRATION POSSIBLE, WITH POCKET-SIDE PATCH REQUIRED.**

The integration boundary is technically visible from the current code:

- JNI already has stop/start lifecycle calls.
- Pocket already constructs native LC config paths and separates network data.
- Pocket already knows the exact Script and role it registered.
- Pocket already has Room-side progress and cache code that can be reconciled
  around a successful LC import.

The likely G3-1 work is a Pocket-side integration or narrowly scoped adapter,
not a redesign of ckb-light-client and not a change to D2 semantics. Maintainer
cooperation may be needed for a production merge, but no maintainer was
contacted in G3-0.

The cheapest thing that could kill G3-1 is a disposable-profile experiment
showing either of the following:

1. Pocket's vendored SQLite storage cannot be safely mapped to the pinned D2
   profile without importing unsupported semantics or changing D2's boundary.
2. After a successful native import, Pocket's application flow still rewinds
   and refilters the selected Script through H, or cannot reconstruct a
   coherent Room/UI view from the imported state without full replay.

If either occurs, stop and report G3-1 HOLD/FAIL. Do not add coverage epochs,
multi-Script bundles, app-cache migration, or a new snapshot product to rescue
the integration.

## 12. D2, PV1, and Pocket's progress state

PV1 remains an upstream-only proposal/primitive for ckb-light-client's own
historical coverage representation. It is not part of this selection or D2
v1.

Pocket currently has consumer-side values such as `registeredFromBlock`, Room
sync progress, rescue-rescan flags, and candidate discovery policy. Those are
not equivalent to a ckb-light-client completed-interval ledger. D2 v1 carries
one handoff cursor/boundary and does not claim that every historical interval
was completely scanned.

Therefore:

1. D2 does not transport authoritative historical coverage state.
2. The D2 cursor is a starting/continuation boundary for the trusted source's
   derived state, not a trustless completeness proof.
3. A future PV1 implementation could remove some Pocket-side duplication of
   coverage bookkeeping and could be consumed by a future D2 profile.
4. PV1 would not make D2's artifact transport, transaction closure,
   backend-neutral encoding, selective import, destination authority checks,
   or atomic lifecycle obsolete.
5. D2 would not solve PV1's upstream problem: persistent disjoint completed
   intervals, delete/re-add epochs, and authoritative coverage semantics.

The projects are complementary layers, not duplicates. G3-1 must not depend on
PV1.

## 13. Grant-shape observation

This is not a funding decision. On the evidence available at G3-0:

- Pocket could support a future mobile wallet infrastructure or recovery case
  study if G3-1 demonstrates a real user flow.
- Neuron could support a desktop wallet/state-boundary case study, but its
  application-state scope is broader than D2.
- Fiber has a clearer funding story around its own payment/mobile state, not
  around D2's frozen responsibility.
- No candidate currently supplies a demonstrated D2-specific funding shape.

Classification: **NO CLEAR FUNDING SHAPE YET**. Technical product value and
grant value remain separate.

## 14. Open uncertainties before G3-1

These are real selection-to-integration questions, not reasons to expand D2:

1. **Profile conformance:** Can Pocket's vendored `0.5.4` SQLite store be
   safely adapted to D2's pinned `12e2952.../storage-v1` profile?
2. **Room reconciliation:** Which Pocket application rows must be rebuilt from
   the imported LC view, and can that be done without historical LC refilter?
3. **Single-Script UX:** Is one Script per operation acceptable for a normal
   Pocket account, or does sequential orchestration become unusable?
4. **Android resources:** Are G2's artifact/RSS/import numbers acceptable on a
   real supported Android device?
5. **Lifecycle enforcement:** Can Pocket reliably stop all JNI/Room/sync writers
   before D2 opens and imports the native store?
6. **Source availability:** What Pocket user/operator flow creates and stores
   the D2 artifact before the old device or database disappears?

The sixth item is especially important. It determines whether the integration
is a planned device/backend transfer product or merely an experiment that does
not help the seed-only recovery path reported in issue #431.

## 15. Final G3-0 decision

**G3-0 PASS — REFERENCE CONSUMER SELECTED**

**Selected consumer:** Pocket Node.  
**Why:** It is current, real, embedded, exact-Script-driven, and has direct
code/issue evidence of historical sync and restore burden.  
**G3-1 boundary:** One real Pocket wallet/network, one exact packed lock Script
plus `lock` role per D2 operation, old-state artifact export, destination
offline/exclusive native SQLite import, Pocket-side Room reconciliation, reopen,
and post-handoff continuation.  
**Cheapest G3-1 killer:** Profile mismatch or an app-level full historical
refilter after import, showing that D2 cannot remove real Pocket work inside
the frozen contract.

G3-1 has not begun.
