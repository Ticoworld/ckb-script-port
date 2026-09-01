#!/usr/bin/env python3
"""Compare RP2-D baseline/import reorg lifecycle evidence.

The comparison is intentionally service-level: raw authority rows and native
database layout are diagnostics, never pass criteria.
"""
import argparse
import json
from pathlib import Path


def load(path):
    with Path(path).open(encoding="utf-8") as fh:
        return json.load(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", required=True)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--import", dest="import_path", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()
    baseline = load(args.baseline)
    imported = load(args.import_path)
    b = baseline["baseline"]
    i = imported["import"]
    checks = {
        "reorg_protocol_selected": bool(b.get("reorg_protocol_selected") and i.get("reorg_protocol_selected")),
        "same_fork_point": b.get("fork_point") == i.get("fork_point"),
        "same_fork_tip": b.get("fork_tip") == i.get("fork_tip"),
        "same_filter_request_starts": b.get("filter_request_starts") == i.get("filter_request_starts"),
        # A selected reorg must re-request the detached interval from the fork
        # point (34 here); that is normal reorg recovery, not replay of the
        # pre-handoff main-chain interval 1..36.
        "reorg_filter_starts_at_or_after_fork": all(x >= 34 for x in i.get("filter_request_starts", [])),
        "old_a1_removed": bool(b.get("old_a1_removed") and i.get("old_a1_removed")),
        "replacement_a2_live": bool(b.get("replacement_a2_live") and i.get("replacement_a2_live")),
        "same_reorg_outpoint": b.get("reorg_a2_outpoint") == i.get("reorg_a2_outpoint"),
        "same_progress": b.get("progress_after") == i.get("progress_after"),
        "same_service_state_after": b.get("state_after") == i.get("state_after"),
        "authority_unchanged_during_import": imported.get("authority_unchanged_during_import") is True,
        "zero_replay_through_h_preserved": imported.get("zero_replay_through_h_preserved") is True,
        "reorg_lifecycle_converges": imported.get("reorg_lifecycle_converges") is True,
    }
    result = {
        "schema_version": 1,
        "experiment": "D2-RP2D-reorg-crash-correctness",
        "case": args.case,
        "checks": checks,
        "passed": all(checks.values()),
        "baseline": {
            "backend": baseline.get("backend"),
            "fork_point": b.get("fork_point"),
            "fork_tip": b.get("fork_tip"),
            "filter_request_starts": b.get("filter_request_starts"),
            "progress_after": b.get("progress_after"),
            "old_a1_removed": b.get("old_a1_removed"),
            "replacement_a2_live": b.get("replacement_a2_live"),
        },
        "import": {
            "backend": imported.get("backend"),
            "fork_point": i.get("fork_point"),
            "fork_tip": i.get("fork_tip"),
            "filter_request_starts": i.get("filter_request_starts"),
            "progress_after": i.get("progress_after"),
            "old_a1_removed": i.get("old_a1_removed"),
            "replacement_a2_live": i.get("replacement_a2_live"),
            "authority_unchanged_during_import": imported.get("authority_unchanged_during_import"),
        },
    }
    Path(args.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
