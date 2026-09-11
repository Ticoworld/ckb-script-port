# CKB Script Port

One light-client install has already synced the data for a CKB Script. CKB
Script Port lets that Script data be exported and reused by another install,
so the new install can continue instead of repeating the same historical work.

This is a Rust library for a narrow, controlled handoff of one exact packed
CKB Script plus its role (`lock` or `type`). It transports the Script-derived
index data and the referenced transaction data needed by the supported
light-client profile. The destination light client remains authoritative for
the chain.

The current API is pre-1.0 and the storage profile is deliberately pinned.
This repository contains the product library and its reproducible research and
acceptance evidence; it does not contain a command-line client.

## What it is

CKB Script Port provides four operations:

1. export one Script's supported derived state from a trusted source;
2. inspect and validate the deterministic artifact without mutation;
3. import it atomically into an offline, exclusively owned destination; and
4. continue normal light-client processing from the accepted handoff point.

The artifact is backend-neutral. Storage adapters translate between the
canonical artifact and supported native light-client storage.

## Why it exists

A wallet or application may have already paid the cost of scanning a Script's
history. Rebuilding a second light-client database, changing storage backends,
or restoring onto another device can otherwise repeat that historical work.
CKB Script Port carries the selected derived state while leaving chain
authority with the destination.

## How it works

```text
old install
    |
export already-synced Script data
    |
deterministic handoff artifact
    |
new install with its own chain authority
    |
offline, exclusive validation and import
    |
restart and continue from the next block
```

The destination must already know the same chain/genesis and the handoff block
hash. Import does not copy headers, consensus state, peer state, chain tip,
unrelated Scripts, wallet keys, or application caches.

## Supported profile and backends

The core upstream profile is pinned to:

```text
ckb-light-client@12e29522ab7e078ada704d4ac04cbc0498009b7b/storage-v1
```

The library has native RocksDB and SQLite builds. Pocket's embedded SQLite
layout is supported by a separate explicit profile adapter, not by guessing
from arbitrary SQLite files:

```text
pocket-node@6eda0b7a4601050b011591d41cc702f0dc7a7c38/
ckb-light-client@0.5.4/kv-v1
```

The public artifact format is version 1. Unknown format versions and
unsupported storage profiles fail closed.

## Quick check

From the repository root:

```powershell
cargo fmt --all -- --check
cargo test -p d2-script-handoff --no-default-features --features sqlite --offline
```

The SQLite feature avoids selecting the default RocksDB feature in the same
build. See [`docs/D2_V1.md`](docs/D2_V1.md) for the library API and lifecycle
requirements.

## Minimal library shape

The conceptual flow is:

```rust,ignore
use d2_script_handoff::{D2, ScriptRole, SqliteStorage, UpstreamAdapter};

let source = UpstreamAdapter::<SqliteStorage>::open_exclusive("source")?;
let exported = D2::new(source).export(&packed_script, ScriptRole::Lock)?;
std::fs::write("handoff.d2", &exported.bytes)?;

let destination =
    UpstreamAdapter::<SqliteStorage>::open_exclusive("destination")?;
let d2 = D2::new(destination);
let bytes = std::fs::read("handoff.d2")?;
d2.inspect(&bytes)?;   // no mutation
d2.validate(&bytes)?;  // destination authority and conflict checks
let result = d2.import(&bytes)?;
```

The source and destination must be quiescent. Normal protocol, filter,
synchronizer, and relayer workers must be stopped or covered by the supported
exclusive lifecycle guard. The destination should be closed and its normal
workers restarted after a successful import.

## Trust and safety boundary

The source is trusted to report its Script-derived state honestly. D2 checks
artifact structure, integrity, Script and role identity, chain binding,
handoff authority, closure, conflicts, resource limits, and lifecycle
preconditions. It cannot prove that a malicious source omitted historical
matches or falsely advanced its cursor.

The destination remains authoritative for:

- genesis, headers, tip, consensus, peers, and network state;
- reorg and rollback decisions;
- future filtering and proof processing; and
- unrelated Script registrations and indexed state.

## What it is not

CKB Script Port is not:

- a full light-client database backup or arbitrary snapshot;
- a trustless historical-completeness proof;
- a wallet-secret, mnemonic, or application-cache migration tool;
- a live importer or network snapshot service;
- a multi-Script atomic package;
- a discovery mechanism for unknown Scripts;
- an arbitrary-version migration system; or
- the PV1 historical-coverage proposal for `ckb-light-client`.

Several independent Script operations may be performed sequentially, but
cross-Script atomicity is outside the current product boundary.

## Repository guide

- [`docs/D2_V1.md`](docs/D2_V1.md) - developer guide, API shape, format, and
  lifecycle rules.
- [`docs/G3_FINAL_REFERENCE_PRODUCT_CHECKPOINT.md`](docs/G3_FINAL_REFERENCE_PRODUCT_CHECKPOINT.md)
  - final Pocket reference-consumer checkpoint.
- [`docs/G1_ACCEPTANCE_MATRIX.md`](docs/G1_ACCEPTANCE_MATRIX.md) and
  [`docs/G1_R1_LIFECYCLE_EVIDENCE.md`](docs/G1_R1_LIFECYCLE_EVIDENCE.md) -
  product lifecycle acceptance.
- [`docs/G2_SCALE_REALISM_REPORT.md`](docs/G2_SCALE_REALISM_REPORT.md) and
  [`docs/G2_ACCEPTANCE_MATRIX.md`](docs/G2_ACCEPTANCE_MATRIX.md) - scale,
  interruption, reorg, and profile qualification.
- [`docs/audits/`](docs/audits/) - historical source and RP2 evidence.
- [`experiments/rp2-real-upstream/`](experiments/rp2-real-upstream/) and
  [`patches/rp2/`](patches/rp2/) - reproducible research harnesses and
  test-only upstream patches.

Raw Pocket databases, Android application data, APKs, build directories, and
device logs are intentionally kept outside the public tree and are ignored by
`.gitignore`. The Pocket checkpoint documents their provenance and the limits
of the host-side reference flow.

