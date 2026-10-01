# Historical Header Lookup Proposal

## Problem

A watched Script cursor can advance to height H while the light-client store has no `BlockNumber(H)` row. This occurs when the filter advances through unmatched ranges; the Script cursor is scan progress, not a complete historical header index.

## Why this matters

An active light-client consumer may need an authenticated historical header at H even when the store did not retain the height-to-hash mapping. A D2-style handoff is one example, but the capability is general to consumers needing an authenticated historical boundary.

## Reproduction

The real iBytes SQLite store had Script cursor H=72,000, a verified tip far ahead, and no `BlockNumber(72,000)` row. The existing offline D2 adapter correctly failed closed rather than treating an arbitrary RPC hash as trusted. The same sparse-storage behavior is expected for upstream SQLite/RocksDB profiles; it is not an iBytes schema incompatibility.

## Existing capabilities

The pinned client already has the `GetBlocksProof` request/response path, proof verification against accepted light-client chain state, MMR membership verification, and verified header/index storage writes. A candidate hash can be discovered externally or by a peer, but discovery is untrusted.

## Missing piece

There is no narrow public active-client operation that orchestrates candidate fetch, proof lifecycle, accepted-tip anchoring, and retrieval of the verified height mapping for an arbitrary historical H.

## Local implementation

The local patch is in the pinned checkout at commit `12e29522ab7e078ada704d4ac04cbc0498009b7b`:

- `light-client-lib/src/service/types.rs` defines a request carrying height, candidate hash, and accepted-tip anchor, plus pending/missing/verified/stale-anchor status.
- `light-client-lib/src/service/impls.rs` snapshots the accepted tip and queues the candidate through the existing `add_fetch_header` path. Polling returns typed stale-anchor status if the accepted tip changed and returns verified only when the persisted height mapping, header number, and candidate hash agree.
- `light-client-lib/src/tests/protocols/light_client/send_blocks_proof.rs` exercises the existing proof protocol with historical lookup requests.

The local iBytes `MobileLightClient` wrapper exposes this request/status pair for the Rust/SQLite reproduction. That wrapper is reference code, not proposed upstream client scope.

## Security model

- Candidate discovery is untrusted; an RPC response is never authority.
- Existing P2P proof and MMR verification remain authoritative and are not duplicated.
- The requested header must have the requested height and candidate hash, and its verified height mapping must be persisted before success.
- Each request is bound to a snapshot of the accepted tip. A changed anchor invalidates the request; the caller retries against the new accepted tip or fails closed.
- No D2 boundary check is removed or relaxed.

## Validation

The local upstream protocol tests cover a valid old candidate (including cached header data without a height mapping), wrong-height response, invalid fork/MMR proof, missing candidate, mapping persistence, and changed tip. The D2 SQLite regression suite verifies exact stored mapping, exact recent-header and exact-tip fallbacks, wrong-height rejection, and fail-closed sparse misses.

The real iBytes source at H=72,000 exported after proof-backed resolution. A fresh destination independently resolved H, imported without a source DB copy, continued at H+1, and resumed after restart. A later funded non-empty Script A handoff matched an ordinary-resync control after a spend/change. The multi-Script run transferred A but not registered Script B (which had no live cells). These are local Rust/SQLite-layer results, not iBytes D2 adoption or full iOS migration.

## Proposed upstream API

The local API is named `request_historical_header_proof` / `poll_historical_header_proof`. A maintainable public shape matching the existing service style is:

```rust
request_verified_header_at_height(
    height: BlockNumber,
    candidate_hash: H256,
) -> Result<HistoricalHeaderRequest>

poll_verified_header(
    request: &HistoricalHeaderRequest,
) -> Result<HistoricalHeaderStatus>
```

The request binds the requested height and candidate to an accepted-tip hash snapshot. Status is pending, missing, verified (with authenticated height/hash/anchor), or typed stale-anchor. Candidate discovery stays with the caller. On stale anchor, the caller obtains or reuses a candidate as untrusted input and starts a new request against the current accepted tip. The active client uses its existing peer/proof pipeline, verifier, and storage writes.

The exact naming and whether stale-anchor retry is service-owned or caller-owned should follow maintainers' service lifecycle conventions. The local experiment uses caller-managed retry; it does not require protocol changes.

## Non-goals

- No D2 integration in the upstream light client.
- No wallet migration feature or iBytes-specific behavior.
- No RPC trust, new wire message, proof format, consensus rule, or storage schema.
- No general historical header index.
- No claim that full-store copying should be replaced.
