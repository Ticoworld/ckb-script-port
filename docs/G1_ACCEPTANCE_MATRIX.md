# G1 Acceptance Matrix

This matrix is the product-level record for G1. `PASS` means the requirement
has executable evidence from the production `d2-script-handoff` package.
Evidence inherited from RP2 is labelled as a fixture or oracle; it is not
counted as a production implementation.

The matrix is intentionally allowed to contain `HOLD`/`PENDING` results. A
G1 PASS requires every required row to be PASS.

| Requirement | Test/evidence | Result | Notes |
|---|---|---|---|
| 1. Production Rust package builds | `cargo check -p d2-script-handoff --offline` and feature test builds | PASS | Rust 1.96; package is a workspace member. |
| 2. Formatting passes | `cargo fmt --all -- --check` | PASS | |
| 3. Lint/static checks pass | `cargo clippy -p d2-script-handoff --no-default-features --features sqlite --offline -- -D warnings` | PASS | SQLite lint path verified; default-feature clippy remains a separate native build gate. |
| 4. Complete test suite passes | SQLite unit/product suite; default-feature suite | PASS | Current default and SQLite suites: 16 passed, 1 ignored, 0 failed. |
| 5. Deterministic artifact | `artifact::tests::deterministic_round_trip`; cross-backend export runner | PASS | Canonical bytes and digest are stable for identical state. |
| 6. Unsupported format rejected | `artifact::tests::rejects_decoded_unknown_version...` | PASS | Unknown D2 versions fail closed. |
| 7. Malformed artifact rejected | magic, truncation, trailing bytes, digest tests | PASS | |
| 8. Resource bounds enforced | bounded row/artifact decode tests; adapter prefix limit | PASS | Safe default limits are in `src/limits.rs`. |
| 9. Exact Script identity preserved | production export/import and wrong-Script rejection test | PASS | Identity is packed Script bytes plus role. |
| 10. Role identity preserved | production wrong-role rejection test | PASS | Lock and type namespaces remain distinct. |
| 11. Genesis mismatch rejected | production authority rejection test | PASS | Destination genesis is read independently. |
| 12. Handoff mismatch rejected | production handoff-hash rejection test | PASS | Height/hash is checked against destination storage. |
| 13. Transaction closure validated | artifact closure checks and packed transaction validation | PASS | Closure is exactly the set referenced by index rows. |
| 14. Missing closure rejected | `artifact::tests::rejects_missing_and_unexpected_closure` | PASS | |
| 15. Conflicting destination rejected | production conflicting-row test; in-memory contract test | PASS | No conflicting row is overwritten. |
| 16. Stale destination/artifact relationship handled per PDEF1 | in-memory stale test; upstream status check | PASS | An existing cursor above artifact H rejects; lower destination cursor may advance to H. |
| 17. Duplicate accepted import idempotent per contract | production and in-memory repeated-import tests | PASS | Complete identical state returns `idempotent = true`. |
| 18. Unrelated destination state preserved | `production_adapter_reopens_and_preserves_unrelated_state` | PASS | Only the selected Script namespace and local derived scheduler value are touched. |
| 19. Forbidden global authority not imported | typed prefix validation; authority fields excluded from `Artifact` | PASS | Source tip, headers, LAST_STATE, LAST_N_HEADERS, peers, and source MIN are not payload fields. |
| 20. RocksDB → SQLite handoff | `scripts/run-g1-cross-backend.ps1` | PASS | Production exporter/importer; real native feature builds. Fixture is bounded. |
| 21. SQLite → RocksDB handoff | `scripts/run-g1-cross-backend.ps1` | PASS | Production exporter/importer; real native feature builds. Fixture is bounded. |
| 22. Restart after successful import | `production_adapter_reopens_and_preserves_unrelated_state` | PASS | Reopens native storage and validates idempotent state. |
| 23. Rejected import leaves coherent destination | authority/conflict/lifecycle rejection tests | PASS | Rejections occur before the native commit. |
| 24. Post-H continuation | production reorg/refilter fixture and continuation boundary assertions | HOLD | Direct storage refilter is exercised; full pinned protocol continuation still needs a product-level fixture. |
| 25. No historical refilter through H in earned fixture | RP2 verifier evidence; production artifact cursor test | HOLD | The production test does not yet instrument the full upstream filter request path. |
| 26. Shallow reorg case passes | `production_adapter_reorg_remains_destination_owned` | HOLD | Native rollback/re-filter is exercised, but not the complete accepted RP2 fork/convergence fixture. |
| 27. Offline/exclusive import enforced | protocol activity and exclusive-lock tests | PASS | Enforceable boundary is the D2 lifecycle guard plus OS advisory lock. |
| 28. Concurrent importer behavior passes | controlled held-exclusive contention test | HOLD | Lock rejection is tested; two independent importer processes with one winner are not yet product-tested. |
| 29. Source omission is explicit non-detectable limitation | `docs/D2_V1.md` trust/non-claims section and PDEF1 | PASS | D2 does not claim historical completeness. |
| 30. Documentation matches implementation | `docs/D2_V1.md`, this matrix, source review | PASS | The docs describe the current implemented API and keep unproven lifecycle claims qualified. |

## Evidence classification

- **New production test:** tests in `crates/d2-script-handoff/src` use the
  public D2 operations and supported upstream storage adapters.
- **Reused fixture:** the bounded native storage shape follows the accepted
  RP2 semantic state, but the G1 tests do not call the old RP2 importer.
- **Reused oracle:** RP2 verifier and evidence remain historical evidence for
  the semantic seam only.

The current HOLD rows are not G2 scale work. They are required G1 lifecycle
evidence gates from PDEF1 and must be resolved before declaring G1 complete.
