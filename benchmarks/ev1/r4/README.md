# EV1 R4 controlled protocol benchmark

This package reproduces the D2 selective exact-Script handoff mechanism through
the pinned CKB light-client protocol test path.

This is a controlled protocol benchmark. It is not a mainnet benchmark, an
Internet/network-throughput benchmark, a mobile benchmark, or a production
performance guarantee.

## Inputs

- D2 repository: `https://github.com/Ticoworld/ckb-script-port`
- Upstream repository: `https://github.com/nervosnetwork/ckb-light-client.git`
- Upstream revision: `12e29522ab7e078ada704d4ac04cbc0498009b7b`
- Backend: SQLite (`--no-default-features --features sqlite`)
- Linux/WSL2 with Bash, GNU coreutils, Rust/Cargo, and a working C compiler.
- The benchmark was exercised under Ubuntu in WSL2 with Rust 1.96.

## Clean setup

```bash
git clone https://github.com/Ticoworld/ckb-script-port.git
git clone https://github.com/nervosnetwork/ckb-light-client.git
cd ckb-light-client
git checkout 12e29522ab7e078ada704d4ac04cbc0498009b7b
git apply --ignore-space-change --ignore-whitespace \
  ../ckb-script-port/benchmarks/ev1/r4/upstream.patch
```

The D2 crate pins the same upstream revision. When building from a sibling
checkout, use a temporary Cargo source patch or the equivalent local path
override so Cargo resolves the patched checkout rather than an unpatched cache.
For example, create a temporary Cargo config containing:

```toml
[patch."https://github.com/nervosnetwork/ckb-light-client.git"]
ckb-light-client-lib = { path = "/absolute/path/to/ckb-light-client/light-client-lib" }
```

The absolute path is local configuration only and must not be committed.

Build the upstream worker and resolve its executable from Cargo JSON output:

```bash
cd ckb-light-client
export CARGO_TARGET_DIR=/tmp/ev1-r4-upstream-target
cargo test -p ckb-light-client-lib \
  --no-default-features --features sqlite \
  --no-run --message-format=json
```

Build the D2 worker with the same SQLite feature selection and resolve its test
executable using `--message-format=json`:

```bash
cd ckb-script-port
export CARGO_TARGET_DIR=/tmp/ev1-r4-d2-target
cargo test -p d2-script-handoff \
  --no-default-features --features sqlite \
  --no-run --message-format=json
```

Do not select a test binary by listing `target/debug/deps`.

## Run

Provide the two Cargo-resolved test executable paths. The runner refuses to
reuse an existing result root.

```bash
cd ckb-script-port
UPSTREAM_EXE=/path/to/ckb_light_client_lib-test \
D2_EXE=/path/to/d2_script_handoff-test \
RUN_ROOT=/tmp/ev1-r4-run \
SCENARIOS='h36 sparse moderate' \
REPEATS=1 \
bash benchmarks/ev1/r4/run.sh
```

For the final three-run workloads use `REPEATS=3`. The runner performs fixture
creation once per repetition before client timing, validates the filter cache,
uses the public export identity/backend/row checks, and uses fresh source,
baseline, and D2 storage directories.

Summarize a completed scenario without external Python packages:

```bash
python3 benchmarks/ev1/r4/parse-results.py /tmp/ev1-r4-run/sparse
```

## Frozen fixtures

H36 sanity fixture:

- H=36; one historical matching transaction; one indexed row; post-H block 39.

Sparse:

- H=10,000; 100 matching blocks; 100 transactions; 100 indexed rows;
  match gap 100; post-H transaction 10,003.

Moderate:

- H=5,000; 498 matching blocks; 996 transactions; four outputs per
  transaction; 3,984 indexed rows; match gap 10; post-H transaction 5,003.

The exact packed Script is recorded in the generated metadata and in the R4
report. The runner does not accept a caller-selected Script.

## Timing definitions

- Baseline destination: authority preparation plus historical rescan.
- D2 destination: authority preparation plus inspect, validate, import, and
  reopen.
- Total D2 transfer: export plus D2 destination.
- Post-H continuation is reported separately and is not used to claim a speedup.
- Provider/fixture preparation and provider copying are outside these clocks.

## Interpretation

The reproducible mechanism claim is that baseline begins historical filtering
at the historical start while D2 begins at H+1 and reaches equivalent Script
state. Wall-clock values are environment-specific. Whole-database copying is a
separate comparator and may be simpler for same-backend whole-install moves.

## Canonical R4 measurements

| Scenario | Baseline median | D2 destination median | Total D2 median |
|---|---:|---:|---:|
| Sparse | 45.17 s | 12.79 s | 12.79 s |
| Moderate | 28.62 s | 6.29 s | 6.42 s |

These are controlled-fixture measurements. They do not establish a universal
speed claim, and they do not establish faster post-H processing.
