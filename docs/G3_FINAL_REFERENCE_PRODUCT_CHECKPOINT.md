# G3 Final Reference Product Checkpoint

**Classification:** G3 PASS — REAL REFERENCE CONSUMER PROVEN  
**Accepted G3-0:** `b86e0a958d50a676c3e062419d4c1194c2b342c3`  
**Accepted G3-1R1:** `6d9840902a4ce794b8ebe9a3ad38f816f864edf8`  
**Decision date:** 11 September 2026

This checkpoint closes G3 for the bounded Pocket reference flow. It does not
turn D2 into a complete Pocket wallet migration, a multi-Script package, a
mobile-integrated library, or a claim of Pocket adoption.

## 1. Executive scope freeze

D2 has a real reference-consumer result for this capability:

> A trusted source can hand one exact packed Pocket lock Script's typed
> derived light-client state and referenced transaction closure to a fresh
> destination through the production D2 library; the destination keeps chain
> authority, starts ordinary filtering at `H+1`, rebuilds Pocket application
> state from local light-client data, observes later activity, and remains
> coherent after restart.

The Pocket execution was real, but the D2 call was host-side. Pocket consumed
the resulting native light-client database after it was staged into a
disposable debuggable application sandbox. The selected Pocket checkout has no
direct D2 library integration surface.

## 2. Accepted evidence

The authoritative execution record is
[`G3_1R1_POCKET_EXECUTION_EVIDENCE.md`](G3_1R1_POCKET_EXECUTION_EVIDENCE.md),
with the historical and retry matrices in
[`G3_1_ACCEPTANCE_MATRIX.md`](G3_1_ACCEPTANCE_MATRIX.md).

The accepted facts are:

| Fact | Evidence |
|---|---|
| Pocket source | v0.5.4 source profile, checkout `6eda0b7a4601050b011591d41cc702f0dc7a7c38` |
| Device | Samsung SM-S9180, `arm64-v8a`, SDK 36 |
| Real source | UI-created Pocket mnemonic wallet and 11,205-row SQLite `kv` store |
| Registered identity | One 73-byte packed lock Script; no type Script registration |
| Handoff | `H = 22,370,055`, with the destination-recognized handoff hash |
| Production artifact | 1,767 bytes; 2 Script-index rows, 2 transaction-index rows, 2 closure transactions |
| Negative control | No-D2 exact Script registered at `H-17`; pinned upstream requested the historical range through H |
| D2 destination | First relevant request began at `H+1`; no historical refilter through H was observed |
| Continuation | One real post-H matched block/transaction was materialized by Pocket |
| Application state | Pocket rebuilt two imported transactions, then three after continuation |
| Restart | Force-stop/reopen preserved native and Room coherence and the three-transaction view |

The run used production `D2::export`, inspection, validation, import, reopen,
and idempotent re-import. It did not call the old RP2 importer.

## 3. Repository lineage reconciliation

The requested historical start was `7e96fbb`. The actual R1 execution start was
already its descendant `8aedf42` because the initial R1 profile/evidence work
had been committed before the remaining execution work continued. The complete
linear sequence is:

| Commit | Parent | Purpose | Files changed | Production semantics changed? | Evidence impact |
|---|---|---|---|---|---|
| `e6293dc` | `7e96fbb` | Add Pocket profile and initial handoff evidence | `Cargo.lock`; `crates/d2-script-handoff/Cargo.toml`; `src/lib.rs`; new `src/pocket.rs`; new Pocket evidence doc; G3-1 matrix | Yes — adds the explicit Pocket SQLite adapter/profile | Establishes the real Pocket profile test seam and initial evidence |
| `8aedf42` | `e6293dc` | Correct Pocket capture security wording | `docs/G3_1R1_POCKET_EXECUTION_EVIDENCE.md` | No | Corrects the statement about disposable encrypted key material |
| `f0aa0e6` | `8aedf42` | Support Pocket recent-header handoff | `crates/d2-script-handoff/src/pocket.rs` | Yes — reads the pinned Pocket `LAST_N_HEADERS` fallback when a direct block-number record is absent | Makes the real captured Pocket handoff hash resolvable and strengthens the production test assertions/output |
| `6d98409` | `f0aa0e6` | Close the Pocket executable reference flow | Pocket evidence doc and G3-1 matrix | No | Records the completed positive flow, negative control, restart, continuation, and R1 PASS |

The reflog records these four commits in the same order on `master` on 10
September 2026. There is no merge or detached-history ambiguity. The known
R1 working-tree changes at the `8aedf42` starting point were subsequently
represented by `f0aa0e6` and `6d98409`; no final D2 production change remains
untracked. The accepted result therefore has a clean lineage:

## LINEAGE CLEAN

Every change that affected G3-1R1 is represented in repository history, and no
mystery or untracked D2 production change influenced the accepted result.

The separate Pocket checkout contains only disposable untracked evidence
material; it is not part of the D2 repository or production history.

## 4. Pocket Script-registration archaeology

The Pocket source was inspected rather than inferred from wallet terminology.
`WalletEntity` stores one address-derived wallet identity. The registration
path decodes that address into one lock `ScriptStatus`. `registerAllWalletScripts`
then creates one such owned status per selected wallet.

Pocket's native key is `FILTER_SCRIPTS` followed by the packed Script and a role
byte (`00` for lock and `01` for type). The normal wallet path in the selected
checkout registers lock Scripts. DAO type Scripts are queried/filtered by
application code; they are not registered as a second wallet type Script in
the observed registration path.

| Pocket case | Code-derived registration shape |
|---|---|
| One basic created wallet/account | One owned lock Script. The real test wallet measured exactly this: 1 registered Script, 1 lock, 0 type. |
| One mnemonic restore | One owned lock Script plus discovery candidates. The import path derives 10 account-axis candidates and 41 chain-axis candidates. The first registration policy includes at most 5 pending account candidates plus all pending/found chain candidates, so the code permits up to 47 registered lock statuses for that parent during discovery. This is a discovery set, not an account-level shared Script. |
| Multiple wallets | One owned lock Script per selected `WalletEntity`, plus any candidate statuses associated with parent wallets. |
| `ALL_WALLETS` | Registers the selected wallets' owned lock Scripts together, ordered by activity and capped at three wallets; candidate statuses are additional. |
| `BALANCED` | Filters the wallet set by saved progress, always keeps the active wallet, drops wallets lagging the maximum by more than 100,000 blocks, then applies the same three-wallet cap. The registered set can therefore change over time. |
| Script roles | The Pocket wallet registration path observed here is lock-only. The D2 role remains explicit and can distinguish lock from type where an upstream profile supports both. |

The real test wallet was created, not mnemonic-restored into an existing
history. Its captured Room database contained one wallet row and zero
`sub_account_candidates` rows. Its native store contained one `FILTER_SCRIPTS`
registration, one lock registration, and zero type registrations. No private
key, mnemonic, PIN hash, or decrypted key material was extracted or recorded.

Only Scripts for which a source has an exact registered derived state can be
handed off. Pocket remains responsible for discovering addresses/candidates
and deciding which registered identities require preservation. D2 does not
discover unknown Scripts or claim to migrate a complete wallet's discovery
history.

## 5. One-Script operation practicality

### Case A — one Script

**PRACTICAL.** The real Pocket beneficiary exercised exactly one operation. The
observed fixture produced a 1,767-byte artifact and the production host-side
export/validate/import/reopen conformance body completed in 0.07 seconds after
compilation. This is a fixture measurement, not a mainnet or Android import
benchmark.

### Case B — ordinary single Pocket wallet

**PRACTICAL for the owned wallet state.** A newly created single wallet has one
owned lock Script and therefore one D2 operation. A mnemonic restore can also
run Pocket's separate candidate-discovery path; if candidate histories are
present, each exact candidate would require its own independent D2 operation
under the frozen v1 contract. That candidate-heavy restore is not claimed as a
complete wallet migration.

### Case C — multiple-wallet Pocket user

**MARGINALLY PRACTICAL, not blocking the frozen claim.** Under `ALL_WALLETS` or
`BALANCED`, the owned-wallet portion is one operation per selected wallet, with
at most three selected simultaneously by Pocket. Candidate discovery can add
more independently registered identities. No multi-Script artifact or full
multi-wallet Pocket migration was fabricated to improve this result.

For the measured one-Script wallet, the total artifact is 1,767 bytes and the
closure has no overlap question because only one Script was present. For a
multi-operation migration, artifact size and import time should be treated as
approximately additive only as a planning estimate; closure duplication and
per-Script history can change the result. No honest Pocket multi-Script artifact
size or Android-linked D2 import time was measured here. This is acceptable for
G3 because the accepted product claim is the exact-Script handoff, not complete
wallet migration.

## 6. D2/Pocket product boundary

## D2 BOUNDARY SURVIVES

D2 owns:

- exact packed Script plus role identity;
- deterministic backend-neutral artifact encoding;
- selected derived-state rows and transaction closure;
- structural, identity, authority, closure, conflict, and lifecycle validation;
- atomic import through an explicit Pocket storage profile;
- preservation of destination chain authority.

Pocket owns:

- mnemonic and keys;
- wallet identity and Script discovery;
- migration trigger and per-Script orchestration;
- Room/application caches and UI;
- wallet policy, registration strategy, and post-import rebuild.

The Pocket-specific work added one narrow storage adapter and executable
reference evidence. It did not replace D2 with a Pocket serializer, key
migration, Room migration, or application-specific migration function.

## 7. Strongest alternatives and final value check

### Mnemonic plus rescan

This remains the better recovery path when the old source state is gone: keys
permit Pocket to derive the identity and ordinary filtering can rebuild history.
It is also the slower path when a valid source light-client view already exists,
which is the situation D2 addresses. D2 does not prove that a source omitted no
history.

### Full Pocket database copy

This is simpler and faster for a same-version, same-application file move. The
disposable device comparison copied the native store plus Room database in
0.24 seconds over ADB. It is not a substitute for D2's boundary: it is
backend-, schema-, version-, and application-layout-coupled; transfers
unrelated state and caches; is not selective to one Script; and risks carrying
source-local chain state as if it were destination authority. D2 is preferable
when the destination must retain authority, when only selected Script state is
wanted, or when the storage backend/profile changes.

### Pocket-specific selective migration

Pocket could theoretically add a small selective migration helper. The current
checkout contains no historical-state migration function of that kind. Such a
helper would still have to define packed identity, closure, authority checks,
atomicity, conflict handling, and profile/version coupling. A Pocket-only
helper could be simpler for one fixed application, but it would not provide the
reusable backend-neutral layer demonstrated by D2. The alternative review did
not show that a stronger alternative makes the proven D2 capability
negligible.

**Product-value recheck: NO material weakening found.** The raw-copy path wins
on speed for a narrow same-app file move; D2 retains value as a selective,
authority-preserving, cross-profile handoff library. The value is bounded and
conditional, not universal.

## 8. GitHub issue readiness

## GITHUB ISSUE JUSTIFIED

No issue was opened or drafted. Maintainer validation is now the logical next
external step because the lineage is clean, the real Pocket flow is complete,
the D2 boundary survives, and one-Script operation is practical for the actual
reference wallet.

Facts supportable in a future public issue are:

- Pocket v0.5.4 from checkout `6eda0b7a4601050b011591d41cc702f0dc7a7c38`;
- Samsung SM-S9180 ARM64 device;
- exact-Script handoff `H = 22,370,055`;
- no-D2 negative control filtering historically through H;
- D2 destination first filter request at `H+1`;
- real post-H continuation and Pocket application rebuild;
- restart/process coherence;
- host-side D2 staging boundary, one Script only, trusted source, no full
  wallet/app-cache migration, and no adoption claim.

## 9. Limitations preserved

This checkpoint does not claim:

- direct D2 linkage inside Pocket;
- multi-Script atomic packages or complete multi-wallet migration;
- migration of mnemonic, keys, Room state, or app caches;
- historical completeness or source non-omission;
- arbitrary Pocket/ckb-light-client version compatibility;
- mainnet-scale, power-loss durability, or arbitrary-depth reorg safety;
- Pocket adoption or maintainer validation.

## 10. Final decision

The two remaining G3 questions are closed:

1. The G3-1R1 repository/evidence lineage is clean.
2. One exact Script per operation is practical for the real single-wallet
   Pocket reference flow; candidate-heavy restore and multi-wallet orchestration
   remain explicit bounded caveats rather than hidden claims.

Therefore:

## G3 PASS — REAL REFERENCE CONSUMER PROVEN

This is a reference-consumer checkpoint, not a grant-ready or adoption claim.
The safe next step is external maintainer/reference validation of the frozen
boundary; no D2 feature expansion is authorized by this checkpoint.
