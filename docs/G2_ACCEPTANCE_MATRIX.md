# G2 acceptance matrix

Date: 9 September 2026  
G2 start checkpoint: `89e2627dd8edd0a38dbfd07528e799ff6008ab09`  
Pinned upstream: `ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1`

The scale evidence is generated under ignored `_work/g2-scale-*` roots. The
workers use the production `D2::export`, `D2::inspect`, `D2::validate`, and
`D2::import` facade. Workload construction and the rescan comparator use the
pinned upstream native `Storage::filter_block` path. These are controlled
synthetic histories, not mainnet measurements.

| Requirement | Test/evidence | Result | Notes |
|---|---|---:|---|
| 1. G1 full regression preserved | `cargo fmt`; both feature `check`, `clippy`, and `test`; `scripts/run-g1-cross-backend.ps1` | PASS | Both backend suites: 17 passed, 0 failed, 4 ignored. Cross-backend runner passed both directions. |
| 2. Realistic workload matrix documented | `scripts/run-g2-scale.ps1`; `docs/G2_SCALE_REALISM_REPORT.md` | PASS | Control, three realistic-synthetic densities, and two stress closure shapes are recorded. |
| 3. RocksDB export scale measured | `_work/g2-scale-realistic-20260909b`, `_work/g2-scale-stress-unique-20260909b`, `_work/g2-scale-stress-shared-20260909b` | PASS | Three repeats for control/realistic workloads; two for stress workloads. |
| 4. SQLite export scale measured | Same scale roots | PASS | Same workload definitions and deterministic artifact bytes as RocksDB. |
| 5. RocksDB import scale measured | Scale summaries, all destination directions | PASS | Fresh-destination production imports, with reopen timing. |
| 6. SQLite import scale measured | Scale summaries, all destination directions | PASS | Fresh-destination production imports, with reopen timing. |
| 7. Cross-backend realistic workload passes | RocksDB ↔ SQLite runs in the scale runner | PASS | Sparse, moderate, dense, unique-stress, and shared-stress artifacts imported in both directions. |
| 8. Artifact amplification quantified | Export JSON `artifact_bytes` and row-payload metric | PASS | Artifact is about 1.065–1.074× semantic row key/value payload in measured workloads. |
| 9. Closure amplification quantified | Workload row/closure counts and artifact sizes | PASS | Shared stress reaches 40,000 index rows and 2,500 closure transactions; unique stress reaches 20,000 index rows and 10,000 closure transactions. |
| 10. Validation remains bounded | Production inspect/validate timings, G1 malformed/limit tests | PASS | Validation completed through the 10.78 MiB artifact; malformed, count, ordering, digest, and limit adversaries remain fail-closed. |
| 11. Import remains bounded | Fresh production imports and sampled RSS | PASS | Shared-stress SQLite imports completed in about 16–26 seconds with about 75–79 MiB sampled RSS. |
| 12. D2 vs rescan measured | Pinned native filter replay in each scale summary; optional `scripts/run-g2-protocol.ps1` attempt | PASS | Measured CPU/storage replay comparator; the larger protocol fixture hit a pinned-upstream epoch-provider overflow during preparation, so no network result is claimed. |
| 13. D2 vs DB-copy assessed fairly | `docs/G2_SCALE_REALISM_REPORT.md` alternative analysis | PASS | Same-backend native copy is faster, while D2 is selective, backend-neutral, and preserves destination authority. |
| 14. Interruption/reopen matrix passes within claimed boundary | `scripts/run-g2-interruption.ps1`, RocksDB and SQLite, 3 cases each | PASS | Controlled termination after validation/preparation and before native commit; retry and reopen were coherent. |
| 15. No partial logical state after tested kill windows | Interruption summaries and G1 atomic batch tests | PASS | The tested pre-commit kill window left no installed D2 state; native-engine commit kill and power loss remain outside G2 evidence. |
| 16. Deeper bounded reorg matrix passes or exact envelope documented | `scripts/run-g2-reorg.ps1`; `_work/g2-reorg-sqlite-20260909d/evidence` plus rejected 30/40 and 32/40 attempts | PASS | Production D2 import plus pinned upstream reorg passed at fork 33 → tip 38. Forks at 30/40 and 32/40 were rejected by upstream `InvalidSamples(451)` before mutation; no arbitrary-depth claim is made. |
| 17. Repeated independent Script operations remain coherent | `upstream::tests::production_g2_repeated_independent_script_operations_remain_coherent`, both feature builds | PASS | Two independent exact packed Scripts were exported/imported sequentially, reopened, and revalidated. No multi-Script atomic package was added. |
| 18. SQLite/mobile-style resource profile measured | Scale process RSS, artifact, SQLite destination, reopen measurements | PASS | SQLite feasibility is measured; the 78.6 MiB sampled stress peak is a resource risk, not a mobile viability claim. |
| 19. Supported profile coupling assessed | Local pinned checkout comparison with `v0.5.5-rc1` | PASS | Classification: moderately coupled. Logical storage keys were stable in the comparison, but filtering and storage APIs changed; new profiles require explicit adapter work. |
| 20. Product-value kill gate survives | D2/rescan/copy comparison | PASS | Product value is conditional, not a universal speed win: D2 removes repeated exact-Script reconstruction and enables selective cross-backend handoff under destination authority. |

## Result

`20 PASS / 0 HOLD / 0 FAIL` within the explicit G2 evidence boundaries. The
result qualifies D2 v1 for realism and bounded interruption conditions; it does
not qualify mainnet scale, mobile deployment, power-loss durability, arbitrary
reorg depth, or arbitrary upstream-version compatibility.
