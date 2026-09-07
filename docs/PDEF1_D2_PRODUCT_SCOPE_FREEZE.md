# PDEF1 — D2 Product Definition / Scope Freeze

Status: **PDEF1 PASS — PROCEED TO G1**

This document freezes the smallest D2 product that can honestly expose the
capability earned by RP2. It is a product definition, not an implementation
plan that authorizes code changes. G1 must remain inside this boundary.

Repository HEAD reviewed: `a7462d63775d5b564a7f3c87f6703258b5aa0d24`

Accepted RP2 semantic checkpoint:
`5673744be3ec3e6318dd7df1aa24de59699d397b`

Research cutoff: 7 September 2026

## 1. Executive scope freeze

D2 v1 is a Rust library that exports and imports one exact packed CKB Script
plus role as a typed, deterministic, backend-neutral artifact.

The artifact carries the source's Script-derived index state, the validated
transaction closure required by that state, and one per-Script handoff
boundary. The destination independently establishes chain authority, checks
the handoff against that authority, and atomically installs only the accepted
Script-derived state and destination-local continuation metadata.

D2 v1 is an **offline, exclusive, trusted-source Script-state handoff**. It
is not a full light-client snapshot, consensus-state migration, trustless
historical proof, database-file backup, or PV1 coverage implementation.

The v1 operation is one exact `(packed Script, role)` per artifact and import.
Several independent artifacts may be imported sequentially, with the same
offline/exclusive lifecycle for each operation. Cross-Script atomicity is out
of scope.

The product boundary is complete when a developer can perform:

```text
source quiescence
  -> export deterministic artifact
  -> inspect and structurally validate
  -> destination authority check
  -> exclusive atomic import
  -> client restart
  -> ordinary continuation after H
```

The destination light client remains authoritative throughout this lifecycle.

## 2. Evidence basis: the RP2 contract

The normative evidence is the executable RP2 stack, not the earlier PB1
prototype or report language alone:

- [RP2-A report](audits/D2_RP2A_AUTHORITY_REPLAY_HARNESS_REPORT.md) and
  `patches/rp2/0001-rp2a-observer-and-negative-controls.patch`;
- [RP2-B report](audits/D2_RP2B_TYPED_HANDOFF_CORE_REPORT.md) and
  `patches/rp2/0002-rp2b-typed-script-handoff.patch`;
- [RP2-C report](audits/D2_RP2C_CROSS_BACKEND_PORTABILITY_REPORT.md) and
  `patches/rp2/0004-rp2c-cross-backend-transport.patch`;
- [RP2-D report](audits/D2_RP2D_REORG_CRASH_CORRECTNESS_REPORT.md) and
  patches `0005`, `0006`, and `0007`;
- tracked evidence manifests under
  `experiments/rp2-real-upstream/manifests`;
- the runners and evidence verifiers under
  `experiments/rp2-real-upstream`.

The disposable system under test was `ckb-light-client` pinned at:

```text
12e29522ab7e078ada704d4ac04cbc0498009b7b
```

The RP2 patches are test-only upstream patches. They are evidence of behavior
and required product semantics; they are not the D2 v1 implementation.

### RP2 evidence matrix

| Phase | Capability proven | Negative controls | Operational conditions | Important limitations |
|---|---|---|---|---|
| RP2-A | The real upstream filter/proof/synchronizer path could be observed and distinguished from direct cursor, minimum, authority, or rows-only mutation. | Direct progress mutation; direct minimum mutation; manual `LAST_STATE`; rows-only `filter_block`; wrong Script, role, genesis, hash, and future height. | Real pinned upstream; real packed blocks/headers/filters/proofs; RocksDB and SQLite feature builds; independent event verifier. | No handoff payload, importer, cross-backend transfer, continuation proof, reorg proof, or product API. |
| RP2-B | Typed S/H/P handoff for one exact packed Script+role; destination authority validation; atomic installation; service-level equivalence; post-H continuation and spend; idempotent reimport. | Wrong handoff hash/genesis/Script/role; cursor beyond authority; unsupported version; forged or incomplete closure; missing dependency; wrong outpoint/role. | Source and destination independently establish authority at H; import uses a native backend batch; fixture handoff was H=36. | Test-only seam; trusted source; bounded fixture; no public schema; no trustless completeness; no cross-backend or reorg claim by itself. |
| RP2-C | The same typed semantic artifact crossed RocksDB → SQLite and SQLite → RocksDB and was written by the native destination backend. | Unknown version; noncanonical/reordered/duplicate/truncated data; digest mismatch; wrong genesis/hash/Script/role; cursor beyond boundary; forged authority closure. | Canonical payload and digest; native destination writers; independent destination authority; no raw database/file copy. | Backend metadata was diagnostic only; no cross-version, public package stability, scale, crash, or Pocket claim. |
| RP2-D | Shallow-fork convergence; old-or-new coherent persisted S/H/P state across the exercised crash matrix; exclusive/offline rejection; artifact lifetime after validation; simultaneous-import busy/retry behavior. | Losing-fork artifact; live import; concurrent importer; conflicting lower-progress retry; artifact removal/replacement after validation; crash/reopen consistency. | Import requires quiescent workers and exclusive ownership; tested RocksDB/SQLite and both artifact directions; fresh-process verifier. | No power-loss proof; no kill inside native storage-engine commit; all commit-edge samples observed after native commit exit; no arbitrary deep-fork claim; no production lifecycle API. |

### Evidence classification

#### Proven within the accepted RP2 bounds

- Exact packed Script bytes plus role are the identity boundary.
- S/H/P state can be extracted, encoded, validated, and imported in the
  tested real-upstream seam.
- The destination does not import source chain authority.
- RocksDB and SQLite can consume the same semantic artifact in both directions.
- A successful import avoids the tested historical filter requests through H.
- The destination continues with ordinary filtering after H.
- A post-H spend and replacement state converge with an independently derived
  baseline.
- Repeated import is idempotent in the tested cases.
- Wrong authority, identity, role, version, closure, and conflict inputs are
  rejected before durable state.
- Unrelated Script state is preserved.
- A shallow reorg below H is handled by ordinary destination rollback and
  subsequent filtering.
- Import is an exclusive offline operation in the R1 test seam.
- The bounded process-abort/reopen tests observed coherent old or new state.

#### Implemented in the experimental harness but not fully proven as product behavior

- The typed exporter/importer and cross-backend envelope exist only in
  test-gated disposable upstream patches.
- Crash evidence does not include physical power loss, filesystem corruption,
  or termination inside native database commit.
- The fixture is small and does not establish realistic package size,
  memory, or import-time behavior.
- The verifiers independently check event and persisted-state evidence, but
  are not independent production storage implementations.
- The tested closure shape is not a claim that every future upstream query
  or storage version is covered.

#### Planned

- Production Rust library and supported adapters.
- Stable D2 v1 artifact schema and compatibility profile.
- Product-level conformance and adversarial suite.
- G2 scale/performance validation.
- G3 reference-consumer integration selected after G1/G2.

#### Not claimed

- Trustless historical completeness.
- PV1 interval or epoch semantics.
- Arbitrary light-client snapshot portability.
- Arbitrary upstream-version migration.
- Live import, power-loss durability, mobile readiness, or production Pocket,
  Neuron, or Fiber integration.

## 3. Exact D2 v1 capability

### Normative capability statement

Given a supported, trusted source light-client instance whose exact packed
Script and role have been indexed through a valid handoff boundary H, D2 v1
exports a deterministic artifact containing that Script's typed derived rows,
the referenced transaction closure, and the per-Script continuation state.

Given a destination light-client instance that has independently established
the same genesis and the block hash at H, is offline and exclusive, and uses a
supported storage adapter, D2 v1 validates and atomically installs the
artifact's accepted Script-derived state. The destination then resumes normal
light-client processing after the imported cursor.

This avoids reconstructing the tested exact-Script-derived view through H. It
does not transfer chain authority or prove that the source scanned every
historical block that it claims to have scanned.

### Source preconditions

The source must:

- use a supported D2 upstream adapter/profile;
- contain the exact packed Script registration under the requested role;
- be quiescent for export, with no concurrent mutation of the exported view;
- have a stable per-Script cursor that equals the artifact handoff boundary H;
- provide the destination-recognizable handoff block hash and genesis hash;
- export from typed upstream semantics rather than arbitrary raw key/value
  selection;
- be trusted by the caller to report its derived state honestly.

Live export is not a v1 promise. A stopped or otherwise explicitly quiescent
source is the supported product condition.

### Payload

The v1 semantic payload contains:

- D2 format version;
- exact packed Script bytes;
- role (`lock` or `type`);
- exact Script-derived index rows for that Script and role;
- transaction-index rows for that Script and role;
- every referenced transaction row required by the exported indexes;
- cursor;
- handoff height H;
- handoff block hash;
- genesis hash;
- deterministic canonical ordering and an integrity digest;
- an upstream adapter/compatibility profile needed to decide whether the
  destination can interpret the typed state.

The v1 payload does not contain a PV1 `completed_ranges` ledger. It contains
one handoff point, not a historical coverage proof.

### Destination preconditions

The destination must already have:

- an initialized supported light-client storage instance;
- independently validated genesis and chain authority;
- the destination-recognized block hash at H;
- a compatible D2 adapter/profile;
- no active protocol/filter/synchronizer/relayer workers;
- exclusive ownership of the import operation;
- enough storage and resources to validate and commit the artifact.

If the destination cannot validate H against its own authority, import fails
closed without durable Script-state mutation.

### Acceptance

The destination validates, at minimum:

- known D2 format version;
- supported upstream adapter/profile;
- exact Script bytes and role;
- genesis equality;
- handoff height/hash equality with destination authority;
- cursor equal to the handoff boundary for v1;
- canonical row ordering and uniqueness;
- valid typed storage prefixes and key lengths;
- complete references from Script-derived rows to transaction closure rows;
- valid transaction encodings;
- absence of chain-authority, consensus, peer, or unrelated global rows;
- no conflicting destination row;
- no destination cursor regression;
- resource limits needed to avoid unbounded allocation or write work;
- payload digest/checksum.

Digest validation detects accidental or unauthenticated payload alteration. It
does not authenticate the source.

### Import result

One accepted artifact commits, in one native destination transaction:

- the exact Script-derived rows;
- the validated transaction closure;
- the exact Script+role registration and cursor;
- destination-local scheduler metadata derived from all local registrations.

The source global minimum is not imported. If the destination maintains
`MIN_FILTERED_NUMBER`, it is recomputed locally from destination registrations.

The import preserves unrelated destination Script state. A repeated identical
import is idempotent. A conflicting artifact is rejected without partial
mutation.

### Continuation

After a successful import and client restart, normal destination filtering
continues after H. The destination remains responsible for all post-H
filtering, proofs, transactions, spends, reorgs, and future state.

## 4. User and developer problem

The narrow problem is real at the technical level but not yet demonstrated as
production adoption:

> A consumer has already derived exact-Script history through H on one valid
> light-client instance and needs another supported instance to obtain that
> accepted derived view without reconstructing the same tested historical
> Script view through H.

### Beneficiary classification

| Beneficiary | Classification | Evidence and limits |
|---|---|---|
| A developer moving a light-client store between supported RocksDB and SQLite environments | Proven technical scenario | RP2-C directly proves this bounded case. No external deployment or user demand is established. |
| Application restore or device/backend replacement involving an embedded light client | Plausible reference beneficiary | The problem is consistent with restore and backend-change workflows, but D2 has no application integration yet. |
| Pocket-like embedded client | Plausible reference beneficiary | Repository archaeology found an embedded client, full-history mode, separate Room caches, and a real lifecycle boundary. No D2 import method or end-to-end D2 use case exists. |
| Neuron-like wallet | Speculative | D-BOOTSTRAP discussed a logical cross-consumer adapter, but no current D2 integration or proven exact use case exists. |
| Fiber | Speculative | The PV1 material identifies duplicated coverage concerns, but D2 has no Fiber integration or channel-state migration. |
| Generic wallet backup, cloud backup, or multi-wallet migration | Speculative and out of scope | Requires application secrets, caches, policy, and broader product semantics not earned by RP2. |

The primary v1 user is therefore a developer integrating a supported CKB light
client, not an end-user wallet product. Pocket is the leading plausible G3
reference beneficiary, not a current D2 customer claim.

## 5. Product boundary and primary shape

### Selected v1 shape: Rust library/crate with explicit storage adapters

D2 v1 will be a Rust library with:

- a backend-neutral semantic artifact model;
- canonical encode/decode;
- source export;
- standalone inspection and validation;
- destination authority validation;
- atomic destination import;
- explicit adapters for the supported `ckb-light-client` storage profiles;
- a product-level conformance suite.

The library is the primary product surface. A user-facing CLI is not required
for v1. A test/reference executable may be used by the conformance suite, but
it is not a product promise.

### Alternatives considered

| Shape | Assessment | Decision |
|---|---|---|
| Rust library/crate | Natural fit for the Rust upstream, typed storage seam, native transactions, and application integration. Keeps authority in the destination adapter and permits backend-neutral artifacts. | **Selected.** |
| Library plus CLI | Useful for manual transfers, but adds configuration, process lifecycle, filesystem staging, and UX before a reference consumer exists. | Defer; a CLI may follow a real integration need. |
| Direct `ckb-light-client` extension | Gives the strongest semantic ownership, but turns D2 into an upstream API/release project and risks redesigning the client. | Not the primary D2 product shape. Use a narrow supported adapter boundary where required. |
| Standalone export/import utility | Cannot safely own destination authority, live-client lifecycle, or native transactional semantics without a client integration layer. | Reject as v1 primary shape. |
| Raw database/file migration tool | Backend- and version-coupled, transfers authority accidentally, cannot safely merge one Script into an existing destination, and contradicts RP2's boundary. | Explicitly reject. |

The selected shape does not authorize copying the test-only upstream patches
unchanged. G1 must rederive a supported adapter boundary and keep the
destination-authority contract explicit.

## 6. Minimum semantic API

Method names and module names remain provisional. These operations are frozen.

### Export

`EXPORT` must:

- identify one exact packed Script and role;
- read the source's current accepted cursor;
- require that cursor to be the handoff boundary H;
- obtain H's block hash and the source genesis identity;
- collect exact Script-derived rows;
- collect and validate the required transaction closure;
- exclude consensus and unrelated global state;
- produce deterministic artifact bytes and digest;
- return counts and the accepted handoff metadata.

### Inspect and validate

`INSPECT` must decode without opening a destination database and return:

- format/profile;
- exact Script and role;
- H and handoff hash;
- genesis hash;
- row counts;
- closure counts;
- digest;
- resource estimates or limits relevant to safe processing.

`VALIDATE_FOR_DESTINATION` must additionally check destination authority,
supported adapter/profile, existing state, conflicts, and lifecycle
preconditions before any durable write.

### Import

`IMPORT` must:

- require offline/exclusive destination ownership;
- validate the complete owned artifact before mutation;
- bind H and its hash to destination authority;
- atomically install S/H/P and local scheduler metadata;
- preserve unrelated state;
- reject stale, conflicting, malformed, or unsupported artifacts;
- return idempotent success for an identical already-installed artifact.

### Result and rejection

Successful results must expose:

- imported exact Script and role;
- accepted H and handoff hash;
- artifact digest;
- imported row counts;
- resulting cursor;
- whether the operation was newly committed or idempotent;
- destination-local resulting scheduler state where relevant.

Rejections must identify a stable semantic category, such as malformed,
unsupported version/profile, authority mismatch, identity mismatch, incomplete
closure, conflict, stale progress, busy lifecycle, or resource limit.

## 7. Artifact semantics

### Semantically required

| Field or property | V1 status | Reason |
|---|---|---|
| Magic/type discriminator | Required | Prevents accidental interpretation of unrelated files. |
| D2 format version | Required | Unknown versions must fail closed. |
| Genesis identity | Required | Binds the handoff to the destination chain. |
| Exact packed Script | Required | Defines the state being moved. |
| Role | Required | Lock and type namespaces are distinct. |
| Handoff height H | Required | Defines the boundary being accepted. |
| Handoff block hash | Required | Destination independently validates the boundary. |
| Cursor | Required | Defines the destination continuation point; v1 requires cursor = H. |
| Canonical row ordering | Required | Makes artifacts deterministic and validation unambiguous. |
| Script-derived rows | Required | The primary transported state. |
| Referenced transaction closure | Required | Needed for the tested service queries and relationships. |
| Integrity digest/checksum | Required | Detects accidental or unauthenticated payload changes. |
| Supported adapter/profile identifier | Required | Prevents interpreting incompatible typed storage semantics. |

### Diagnostic only

- source backend name;
- source process identifier;
- source instance identity;
- creation timestamp;
- host and toolchain information;
- human-readable network label when genesis is already present.

Diagnostic fields must not become source authority and must not affect semantic
acceptance except where an explicit adapter/profile compatibility rule says so.

### Out of scope

- signatures and provider authentication;
- remote provider discovery;
- timestamps as freshness authority;
- source process identity as trust authority;
- source global `MIN_FILTERED_NUMBER` as imported state;
- `LAST_STATE`, headers, checkpoints, peer state, proof queues, or unrelated
  Script rows;
- PV1 completed ranges or coverage epochs.

The exact encoding—canonical JSON, a binary encoding, or another deterministic
representation—is provisional until G1. The semantic fields, ordering rule,
version failure behavior, and digest responsibility are frozen.

## 8. Trust model

### Trusted source

Trusted source means the caller controls or accepts the source light-client
instance as an honest producer of its exact-Script-derived state. It does not
mean the artifact is signed, publicly authenticated, or independently proven
complete.

The source may be relied upon to provide the rows and cursor it claims. The
destination may not rely on the source to establish chain authority.

### Destination verification

The destination must independently verify:

- genesis identity;
- H and the block hash at H;
- exact packed Script and role;
- format/profile compatibility;
- canonical structure, row uniqueness, and digest;
- typed key/value validity;
- complete Script-index-to-transaction-closure references;
- absence of authority/global/unrelated rows;
- existing destination conflicts and cursor ordering;
- exclusive lifecycle state;
- resource limits before allocation and commit.

### What D2 detects

D2 v1 detects, in the supported semantic model:

- malformed or truncated artifacts;
- noncanonical ordering or duplicate entries;
- digest mismatch;
- wrong genesis;
- wrong handoff hash or height;
- wrong Script or role;
- unsupported format/profile;
- missing referenced transaction closure;
- invalid typed rows;
- conflicting destination rows;
- stale/lower-progress import conflicts;
- attempted authority or unrelated-state import;
- live or competing import lifecycle violations.

### What D2 cannot detect

D2 v1 cannot detect a trusted source that:

- omits valid historical Script-derived rows;
- claims a cursor after work it never performed;
- provides internally consistent but incomplete derived state;
- omits an historical interval not represented in the artifact;
- intentionally supplies a false but structurally valid view.

Such a source can cause the destination to skip historical filtering through H.
That is an accepted consequence of the trusted-source model. D2 v1 must state
this plainly and must not describe the artifact as a completeness proof.

## 9. Destination authority contract

D2 v1 must never import source authority for:

- `LAST_STATE`;
- chain tip;
- headers or `LAST_N_HEADERS`;
- consensus state;
- peer or network state;
- proof queues;
- global chain configuration;
- source `MIN_FILTERED_NUMBER`;
- unrelated Script registrations or indexes;
- arbitrary raw authority key prefixes.

D2 may write the destination's exact Script registration and cursor because
that is the per-Script continuation state being handed off. D2 may also update
the destination's local `MIN_FILTERED_NUMBER`, but only by recomputing it from
all destination registrations. It must never import the source value as
authority.

This is the principal protection against regressing to the D-BOOTSTRAP
snapshot model.

## 10. Single-Script and multi-Script boundary

D2 v1 is **one exact packed Script plus role per artifact and import**.

Sequential independent imports are allowed. Each operation must satisfy the
same offline/exclusive lifecycle and has its own atomicity boundary.

There is no multi-Script artifact, no cross-Script transaction, and no atomic
all-wallet restore in v1. Shared transaction rows may be reused by sequential
artifacts when their typed bytes agree; conflicting shared rows reject the
operation.

## 11. Backend contract

D2 v1 promises a backend-neutral semantic artifact, not arbitrary backend
support.

The initial supported adapter set is:

- upstream RocksDB storage;
- upstream SQLite storage;
- RocksDB source to SQLite destination;
- SQLite source to RocksDB destination;
- same-backend import where useful.

Adapters map native upstream representations into the canonical D2 model and
write accepted state through the destination's native transaction mechanism.
No database file copy, raw dump import, or source backend key layout is part of
the contract.

Backend identity is diagnostic only. Adapter/profile and D2 format compatibility
are semantic because they determine whether the typed state can be interpreted
safely.

## 12. Lifecycle contract

### Export

The source must be stopped or otherwise explicitly quiescent. No live export
race is supported. The exporter reads a stable source view and owns the
decoded artifact before transfer.

### Import

The destination must be offline with protocol, filter, synchronizer, and
relayer workers quiescent. One importer acquires exclusive ownership. Live
import is rejected before any mutation.

Two importers racing for one destination produce one accepted owner and one
busy rejection. A retry after the winner commits is idempotent if the artifact
is identical. A conflicting or lower-progress retry is rejected.

The artifact must be fully decoded, structurally validated, and held as an
owned immutable object before the destination transaction begins. The importer
must not reopen or depend on a mutable source artifact path after validation.

The supported restart lifecycle is:

```text
stop/quiesce -> validate -> exclusive import -> close/reopen -> restart client
```

The bounded RP2 crash contract is coherent old-or-new state after the exercised
process abort points, with retry possible. V1 must not claim physical power
loss, filesystem-corruption recovery, or a kill inside native engine commit.

## 13. Reorg contract

Before import, the destination must recognize the artifact's genesis and H
hash. If it cannot, import fails closed and does not install Script-derived
state.

After import, the destination's ordinary light-client rollback and proof
machinery remains authoritative. If a later reorg invalidates H, the imported
state is ordinary destination state and must be rolled back/rebuilt by the
upstream machinery.

RP2 proved this for the tested shallow fork below H and the tested upstream
fixture. D2 v1 may claim that bounded behavior only. It must not claim
arbitrary-depth fork safety or introduce D2-specific authority rollback.

## 14. Versioning contract

These version domains remain separate:

| Domain | V1 rule |
|---|---|
| D2 artifact format | Explicit format version; unknown versions reject. |
| Upstream storage/profile | Explicit supported adapter/profile; no arbitrary layout interpretation. |
| `ckb-light-client` version | Only explicitly tested/pinned versions or profiles are supported. No automatic migration. |
| D2 API | Separate library API versioning; API changes must not be inferred from artifact version. |

An artifact from an unsupported upstream profile is rejected, even if its
bytes look structurally valid. Future cross-version support requires an
explicit converter or a newly tested adapter; it is not a hidden compatibility
fallback.

PV1 is not a v1 dependency. If upstream later exposes interval coverage or
epoch semantics, a future D2 format/profile may consume them explicitly.

## 15. Stable versus provisional interfaces

### Stable v1 semantics

- exact packed Script plus role identity;
- trusted-source model;
- destination-owned chain authority;
- one handoff boundary H plus hash;
- deterministic artifact and integrity digest;
- backend-neutral semantic model;
- one Script per artifact/import;
- offline/exclusive import;
- atomic destination installation;
- unrelated-state preservation;
- fail-closed conflict and authority validation;
- idempotent repeated import;
- ordinary destination continuation after H;
- no historical refilter through accepted H in the supported scenario;
- no PV1 coverage ledger.

### Provisional implementation details

- crate name and module layout;
- exact serialization encoding;
- exact method names and error enum names;
- storage-adapter trait layout;
- streaming versus buffered encoding;
- compression;
- CLI and file-transfer UX;
- batching and resource-tuning knobs;
- platform-specific lock implementation;
- internal event/log schema.

G1 must freeze the implementation choices needed for compatibility, but must
not mistake them for a broader product promise.

## 16. What D2 v1 explicitly does not claim

The following are normative non-goals:

- no trustless historical completeness;
- no proof that a source omitted nothing;
- no PV1 completed-range or coverage-epoch ledger;
- no replacement for chain, header, or consensus synchronization;
- no transfer of consensus authority;
- no arbitrary full light-client snapshot;
- no raw database-file backup or restore;
- no arbitrary multi-Script migration;
- no historical discovery of unknown Scripts;
- no wallet secrets or app-cache migration;
- no global multi-wallet backup system;
- no signed public snapshot network or provider marketplace;
- no live import;
- no power-loss or filesystem-corruption durability claim;
- no kill-during-native-storage-engine commit claim;
- no arbitrary deep-fork claim;
- no arbitrary upstream-version migration;
- no mainnet-scale, mobile, or memory claim before G2;
- no Pocket, Neuron, or Fiber integration in G1;
- no Fiber channel-state migration;
- no grant or ecosystem-adoption claim.

## 17. Minimum G1 shipped artifacts

G1 must produce the smallest usable product, not another harness:

1. A production-quality Rust D2 core library implementing the frozen semantic
   operations.
2. A canonical v1 artifact schema/encoding with deterministic bytes, explicit
   versioning, and digest/checksum validation.
3. Supported `ckb-light-client` storage adapters for the agreed upstream
   profile and RocksDB/SQLite paths.
4. A source exporter for one exact Script+role.
5. Offline inspection and destination-specific validation.
6. An atomic destination importer that preserves unrelated state and owns the
   destination lifecycle checks.
7. Product documentation for the trust model, authority boundary, lifecycle,
   compatibility, and rejection semantics.
8. An executable product-level conformance and adversarial suite covering the
   G1 acceptance criteria below.

A public CLI, Pocket integration, cloud transfer service, and reference wallet
are not required for G1. The library and conformance suite must nevertheless
be runnable without understanding the RP2 patch runners.

## 18. G1 acceptance criteria

All G1 criteria are required unless explicitly marked G2 or G3.

### G1 required

- Export from a supported real upstream RocksDB source.
- Export from a supported real upstream SQLite source.
- Import RocksDB artifact into SQLite destination.
- Import SQLite artifact into RocksDB destination.
- Preserve exact packed Script bytes and role.
- Produce deterministic artifact bytes and a stable digest for identical state.
- Reject malformed, truncated, noncanonical, duplicate, reordered, and
  digest-invalid artifacts.
- Reject unsupported D2 format versions and upstream profiles.
- Reject genesis mismatch.
- Reject handoff hash/height mismatch.
- Reject wrong Script and wrong role.
- Reject missing or malformed transaction closure.
- Reject attempted authority, consensus, peer, global, or unrelated-state
  import.
- Reject conflicting existing rows and stale/lower-progress imports.
- Preserve unrelated destination Script state.
- Accept an identical repeated import idempotently.
- Require offline/exclusive destination lifecycle.
- Reject live import before durable mutation.
- Make one concurrent importer win and the other fail busy; permit safe retry.
- Validate and own the artifact before beginning the destination transaction.
- Atomically install S/H/P and destination-local scheduler metadata.
- Reopen after successful import and continue normally.
- Demonstrate no historical Script filter requests through accepted H in the
  supported fixture.
- Demonstrate post-H continuation and a post-H spend/replacement.
- Demonstrate the bounded process-abort/reopen old-or-new result.
- Demonstrate shallow reorg rollback remains destination-owned.
- Reject losing-fork or otherwise unrecognized handoff authority.
- Document that source omission and false completeness are not detectable.

### G2, not G1

- Realistic long histories and large derived state.
- Package-size, import-time, memory, and storage benchmarks.
- Compression and streaming optimization.
- Mobile filesystem and resource behavior.
- More realistic interruption and power-loss approximations.
- Deeper or broader reorg stress beyond the accepted fixture.
- Repeated sequential Script imports at realistic scale.

### G3, not G1

- A real consumer integration.
- JNI/Kotlin/Android lifecycle integration.
- Room/app-cache reconciliation.
- Wallet candidate-discovery policy.
- Neuron or Fiber integration.

## 19. G2 boundary

G2 exists to answer whether D2's saved historical work is materially cheaper
than rescanning at realistic state sizes and whether the lifecycle remains
safe under resource pressure.

G2 should measure:

- long histories;
- large Script-derived indexes and transaction closures;
- artifact size and transfer cost;
- export/import time;
- peak memory;
- storage amplification and free-space requirements;
- repeated sequential imports;
- realistic interruption and filesystem behavior;
- mobile constraints only if a G3 consumer requires them.

G2 does not automatically include cross-version migration. That requires a
separate compatibility decision after a real profile exists.

## 20. G3 boundary

G3 means one validated real-consumer integration selected after G1 and the
relevant G2 measurements.

The selected consumer must:

- actually embed or depend on `ckb-light-client`;
- maintain exact-Script-derived state worth restoring;
- have a real restore, backend-change, or device-change scenario;
- obtain meaningful value by avoiding historical reconstruction;
- be able to isolate light-client state from unrelated application caches;
- provide a safe offline lifecycle insertion point.

Pocket is the leading plausible reference beneficiary because repository
inspection found embedded light-client state, full-history behavior, separate
Room state, and a lifecycle where live import would be unsafe. Pocket remains
unintegrated and is not a G1 requirement.

G3 must not silently expand D2 into wallet backup, Room migration, candidate
policy, JNI redesign, or application-state migration.

## 21. Product value versus alternatives

| Alternative | Authority/risk | What it lacks | When D2 is preferable |
|---|---|---|---|
| Rescan historical Script state | Strong destination authority; potentially expensive and slow. | Repeats the work D2 is meant to avoid. | When a trusted source already has the exact view and the historical range is costly. |
| Copy the entire light-client database | Transfers authority and unrelated state; backend/version coupling. | Selective merge, backend neutrality, clean authority separation. | When only one Script should move into an existing destination. |
| Backend-file backup/restore | Strong file-level coupling; usually same backend/version/path; fragile around live clients. | Typed validation, cross-backend transfer, destination-owned authority. | D2 is preferable for supported cross-backend or selective restore. |
| Application-specific export/import | Can move app caches and policy. | Does not restore the light-client's indexed Script view or prove continuation. | D2 provides the lower-level light-client state that an application can compose with its own restore logic. |
| Custom migration scripts | Fast to write but tied to raw layouts and one version. | Stable semantics, fail-closed validation, conformance evidence. | D2 is preferable when the operation must survive supported backend differences. |
| Upstream storage-copy tooling | Could be efficient and semantically close to the client. | Usually copies broader state and may not support selective merge. | D2 is preferable only when selective exact-Script handoff and backend-neutral transfer matter. |

D2's value does reduce to selective, typed, authority-preserving state
transfer. That is narrower than a general backup product, but it is not the
same as copying rows: the value is the combination of exact identity,
transaction closure, destination authority binding, native atomic import,
backend-neutral representation, and continuation semantics.

If a future upstream-native export/import API provides all of those semantics,
D2 should consume or wrap it rather than duplicate it.

## 22. Strongest rival

The strongest rival is a `ckb-light-client`-native typed export/import API,
possibly combined with a whole-client backup facility.

That rival has advantages:

- it owns storage semantics directly;
- it can align export/import with reorg and scheduler internals;
- it can avoid a separate adapter's interpretation of raw layout;
- it can evolve with the client.

D2 remains justified only if it provides a useful product boundary around that
native seam:

- deterministic portable artifact;
- selective one-Script transfer;
- cross-backend adapter behavior;
- explicit trusted-source and destination-authority contract;
- offline lifecycle and atomic import;
- application-facing result and rejection semantics.

D2 must not become a competing second storage model. If upstream later owns a
fully equivalent portable typed handoff, D2's artifact/lifecycle wrapper may
become thin; that is a success condition, not a reason to duplicate upstream
authority.

## 23. Remit / Sluice completeness check

The valuable lifecycle is:

```text
source derived state
  -> quiescent export
  -> inspect/validate
  -> artifact transfer
  -> destination authority check
  -> exclusive atomic import
  -> restart/reopen
  -> continuation after H
  -> conflict and retry behavior
  -> ordinary reorg behavior
```

G1 must complete that lifecycle for the supported adapter/profile and both
backends. Stopping at a serializer, row extractor, or test-only upstream patch
would be another respectable prototype that misses the valuable lifecycle.

G1 may stop before a real consumer. Reference-consumer adoption belongs to G3.
That is a deliberate product boundary, not an unfinished handoff core.

## 24. Technical product value versus funding value

### Technical product value

D2 v1 has a real but narrow technical value: it can avoid repeated exact-Script
historical reconstruction while preserving destination-owned chain authority
and permitting supported backend changes. It is most valuable where a full
history scan is expensive and a whole-database copy is unsafe or too broad.

The value is not yet quantified at realistic scale and has not been validated
in a deployed consumer.

### Grant/funding value

The current evidence supports a bounded engineering product definition, not an
adoption or ecosystem grant claim. A future funding case would be stronger
after:

- G1 produces a usable library;
- G2 demonstrates material performance/value on realistic histories;
- G3 validates one real consumer workflow.

The grant-hunt PV1 lane remains separate. PV1 is an upstream contribution
candidate and is not a D2 v1 dependency.

## 25. Open questions before G1

These are implementation decisions, not unresolved product-boundary blockers:

1. Which exact upstream commit/profile is the first supported G1 adapter?
2. What canonical encoding best meets deterministic validation and resource
   limits: canonical JSON or a binary representation?
3. What platform-specific mechanism provides the offline/exclusive lock?
4. What artifact-size and row-count limits are required for safe decoding?
5. How should the library expose owned artifact bytes versus a stream?
6. What stable rejection-code taxonomy should applications receive?
7. What is the supported packaging/distribution model for the Rust crate?
8. What exact native upstream API seam is required so G1 does not depend on
   test-only patch internals?

None of these questions justifies adding PV1, live import, a CLI, or a
multi-Script package to v1.

## 26. Final G1 decision

**PDEF1 PASS — PROCEED TO G1.**

The product boundary is coherent and useful after correct scoping:

- one exact Script plus role;
- trusted source;
- deterministic backend-neutral artifact;
- destination-owned authority;
- offline/exclusive atomic import;
- bounded continuation and reorg semantics;
- no historical completeness claim;
- no PV1 dependency;
- no consumer integration requirement in G1.

G1 is authorized only to implement and validate this library boundary. It is
not authorized to implement PV1, redesign `ckb-light-client`, add live import,
turn the artifact into a full snapshot, or expand into Pocket/app-cache
migration.

