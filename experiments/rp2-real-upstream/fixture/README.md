# RP2-A fixture

The executable fixture is constructed by the test-only upstream module using
`MockChain::new_with_dummy_pow`, `MockRunningChain`, genuine packed CKB
transactions and headers, `SnapshotExt::get_block_filter_data`, and the real
upstream proof builders. It is a deterministic dev/dummy-PoW chain, not a
testnet or mainnet fixture.

The current foundation creates blocks 0 through 8, registers a valid
always-success-derived Script A lock, creates A activity through a real
transaction, leaves blocks 1 through 4 as the historical unmatched control
range, and uses block 8 as the authority/handoff boundary H. The generated
manifest records the actual genesis/block hashes and packed Script bytes.

The complete A/B/type/reorg fixture belongs to later RP2 milestones. This
milestone intentionally stops after proving that the measuring instrument can
observe real filtering and reject shortcuts.
