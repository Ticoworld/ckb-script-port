# RP2-A — authority and replay harness

This directory contains disposable experimental infrastructure for the first
real-upstream D2 reproof milestone. It is not the D2 library, a production
importer, or a package-format definition.

The system under test is `nervosnetwork/ckb-light-client` at:

`12e29522ab7e078ada704d4ac04cbc0498009b7b`

The upstream checkout lives under the ignored `_work/upstream` directory. Its
test-only modifications are preserved as reviewable patches under
`patches/rp2/`.

## Entry point

From the project root, run:

```powershell
.\experiments\rp2-real-upstream\scripts\run-rp2a.ps1
```

The entry point verifies the upstream pin, applies only the recorded RP2-A
patches, builds the feature-specific upstream test binaries, runs the real
protocol baseline and negative controls serially, and invokes the independent
JSONL verifier.

The disposable run root is `experiments/rp2-real-upstream/run/`. It contains
databases, fixture output, event logs, build evidence, and summaries and is
ignored by Git. Reproducibility descriptions, schemas, patches, source, and
reports are tracked.

## What counts as evidence

The normal control must reach real `FilterProtocol`, accepted
`BlockFilters`, matched-block proof handling, `SyncProtocol`, and upstream
`filter_block`. A direct database write is permitted only inside a named
adversarial case and is emitted with an adversarial origin.

The verifier treats requested-but-unmatched history as historical work. It
does not accept existing rows, a cursor write, a minimum write, or an apparent
tip as replay-avoidance evidence.

RP2-A does not perform a D2 state handoff and does not claim D2 success.
