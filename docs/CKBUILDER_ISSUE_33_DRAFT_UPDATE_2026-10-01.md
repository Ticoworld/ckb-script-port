# Draft update for CKBuilder issue #33 — not posted

The controlled R4 resync comparison is complete. On the specified SQLite fixtures, ordinary resync measured 45.17 s versus 12.79 s total D2 time at sparse H=10,000, and 28.62 s versus 6.42 s total D2 time at moderate H=5,000. These are controlled-fixture measurements, not mainnet or universal performance claims.

The investigation found a second independent recurrence in iBytes. Its real Rust/SQLite light-client path reproduced historical Script filtering; iBytes remains a development-stage project, so this is technical recurrence evidence, not user demand or D2 adoption.

Applying D2 to a real sparse iBytes store exposed a missing `BlockNumber(H)` mapping despite a persisted Script cursor. The boundary check stayed fail-closed. A local active-client lookup used the existing `GetBlocksProof`/MMR verification path; candidate discovery remained untrusted. The real source at H=72,000 exported after proof-backed resolution, and a fresh destination independently verified the same boundary and imported without copying the source database. Continuation at H+1 and restart/resume succeeded.

A later funded non-empty Script A handoff produced the same post-spend live-cell state as an ordinary-resync control. A two-Script source selectively transferred A; the destination did not receive B (B had no live cells). Whole same-version SQLite copying remains simpler for a full-store clone and is a valid, coarser alternative.

The remaining upstream-sized item is a small active-client API that orchestrates historical candidate fetching, existing proof verification, accepted-tip anchoring, and verified height-mapping retrieval. No new wire protocol, consensus rule, storage schema, or RPC trust is needed in the local design.

**Technical ask:** Would you prefer this request/status operation to live on `LightClientChainService` (with caller-managed stale-anchor retry, as in the local experiment), or should the public API be owned by a higher-level `LightClientService` wrapper?
