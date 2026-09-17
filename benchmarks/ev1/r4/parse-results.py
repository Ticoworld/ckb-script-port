#!/usr/bin/env python3
"""Summarize one or more runner repetition directories."""

import pathlib
import re
import statistics
import sys


def elapsed(path: pathlib.Path) -> float:
    match = re.search(r"elapsed_s=([0-9.]+)", path.read_text())
    if not match:
        raise ValueError(f"missing elapsed_s in {path}")
    return float(match.group(1))


def value(root: pathlib.Path, name: str) -> float:
    evidence = root / "evidence"
    if name == "baseline_destination":
        return elapsed(evidence / "baseline-preparation.time") + elapsed(evidence / "baseline-rescan.time")
    if name == "d2_destination":
        return sum(elapsed(evidence / f"d2-{part}.time") for part in ("preparation", "inspect", "validate", "import", "reopen"))
    if name == "d2_total_transfer":
        return elapsed(evidence / "export.time") + value(root, "d2_destination")
    raise KeyError(name)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: parse-results.py RUN_ROOT/scenario")
    scenario = pathlib.Path(sys.argv[1])
    runs = sorted(scenario.glob("run-*/run.json"))
    if not runs:
        raise SystemExit(f"no run.json files under {scenario}")
    roots = [path.parent for path in runs]
    for name in ("baseline_destination", "d2_destination", "d2_total_transfer"):
        raw = [value(root, name) for root in roots]
        print(f"{name}: raw={raw} median={statistics.median(raw):.2f}")


if __name__ == "__main__":
    main()
