#!/usr/bin/env python3
"""Compare a cross-backend RP2-C import with its destination-backend oracle.

The comparator consumes only service-level JSON emitted by the real upstream
workers.  It intentionally treats raw backend rows as diagnostic input rather
than as a portability oracle.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} is not a JSON object")
    return value


def equal(left: Any, right: Any) -> bool:
    return json.dumps(left, sort_keys=True, separators=(",", ":")) == json.dumps(
        right, sort_keys=True, separators=(",", ":")
    )


def contains_outpoint(state: dict[str, Any], outpoint: str) -> bool:
    objects = state.get("cells", {}).get("objects", [])
    return any(
        f"0x{cell.get('out_point', {}).get('tx_hash', '')[2:]}"
        + f"{int(cell.get('out_point', {}).get('index', '0x0'), 16):08x}"
        == outpoint
        for cell in objects
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--import", dest="import_path", type=Path, required=True)
    parser.add_argument("--tampered", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source = load(args.source)
    baseline = load(args.baseline)
    imported = load(args.import_path)
    tampered = load(args.tampered)

    a0 = baseline["a0_outpoint"]
    a1 = baseline["a1_outpoint"]
    a2 = baseline["a2_outpoint"]
    baseline_at_h = baseline["state_at_h"]
    imported_at_h = imported["state_at_h"]
    baseline_after = baseline["state_after"]
    imported_after = imported["state_after"]
    baseline_starts = [int(value) for value in baseline["filter_request_starts"]]
    imported_starts = [int(value) for value in imported["filter_request_starts"]]
    imported_authority_before = imported["authority_before_import"]
    imported_authority_after = imported["authority_after_import"]

    checks = {
        "source_backend_distinct_from_destination": source["backend"] != imported["backend"],
        "artifact_version": imported.get("artifact_version") == "rp2-cross-backend-fixture-v1",
        "artifact_digest_matches_tampered_backend": imported.get("artifact_digest")
        == tampered.get("artifact_digest"),
        "tampered_backend_metadata_does_not_change_semantics": equal(
            imported["state_at_h"], tampered["state_at_h"]
        )
        and equal(imported["state_after"], tampered["state_after"])
        and imported["progress_after"] == tampered["progress_after"],
        # The full fingerprint intentionally changes when S/H/P rows are
        # installed.  The worker separately records the C-only fingerprint;
        # that explicit invariant is the authority check here.
        "authority_unchanged_during_import": imported["authority_unchanged_during_import"] is True,
        "query_equivalent_at_h": equal(baseline_at_h, imported_at_h),
        "query_equivalent_after": equal(baseline_after, imported_after),
        "progress_equivalent_at_h": baseline["progress_at_h"] == imported["progress_at_h"],
        "progress_equivalent_after": baseline["progress_after"] == imported["progress_after"],
        "pre_h_spent_a0": not contains_outpoint(baseline_at_h, a0)
        and not contains_outpoint(imported_at_h, a0),
        "handoff_live_a1": contains_outpoint(baseline_at_h, a1)
        and contains_outpoint(imported_at_h, a1),
        "post_h_spent_a1": not contains_outpoint(baseline_after, a1)
        and not contains_outpoint(imported_after, a1),
        "post_h_live_a2": contains_outpoint(baseline_after, a2)
        and contains_outpoint(imported_after, a2),
        "zero_replay_through_h": all(start > baseline["authority"]["height"] for start in imported_starts)
        and (baseline["authority"]["height"] + 1) in imported_starts,
        "baseline_normal_history": baseline.get("historical_filtering_observed") is True,
        "ordinary_post_h_continuation": (baseline["authority"]["height"] + 1) in imported_starts,
        "idempotent_reimport": imported["idempotent_reimport"] is True,
        "unrelated_script_preserved": imported["unrelated_script_preserved"] is True,
        "global_min_recomputed_locally": isinstance(imported.get("recomputed_min_filtered"), int),
    }
    checks["lifecycle_converges"] = all(
        checks[key]
        for key in (
            "pre_h_spent_a0",
            "handoff_live_a1",
            "post_h_spent_a1",
            "post_h_live_a2",
        )
    )

    result: dict[str, Any] = {
        "schema_version": 1,
        "experiment": "D2-RP2C",
        "case": args.case,
        "source_backend": source["backend"],
        "destination_backend": imported["backend"],
        "upstream_revision": imported["upstream_revision"],
        "artifact_version": imported["artifact_version"],
        "artifact_digest": imported["artifact_digest"],
        "script_hash": imported["script_hash"],
        "role": "lock",
        "handoff_height": imported["authority"]["height"],
        "handoff_hash": imported["authority"]["hash"],
        "genesis_hash": imported["authority"]["genesis_hash"],
        "checks": checks,
        "query_equivalent_at_h": checks["query_equivalent_at_h"],
        "query_equivalent_after": checks["query_equivalent_after"],
        "progress_equivalent": checks["progress_equivalent_at_h"] and checks["progress_equivalent_after"],
        "authority_unchanged_during_import": checks["authority_unchanged_during_import"],
        "zero_replay_through_h_preserved": checks["zero_replay_through_h"],
        "baseline_filter_request_starts": baseline_starts,
        "import_filter_request_starts": imported_starts,
        "baseline_progress_at_h": baseline["progress_at_h"],
        "import_progress_at_h": imported["progress_at_h"],
        "baseline_progress_after": baseline["progress_after"],
        "import_progress_after": imported["progress_after"],
        "pre_h_spent_outpoint": a0,
        "handoff_live_outpoint": a1,
        "post_h_spent_outpoint": a1,
        "replacement_live_outpoint": a2,
        "imported_s_count": imported["imported_index_rows"],
        "imported_h_count": imported["imported_transaction_rows"],
        "imported_categories": {
            "S": ["script-index", "transaction-index"],
            "H": ["TxHash transaction closure"],
        },
        "recomputed_min_filtered": imported["recomputed_min_filtered"],
        "idempotent_reimport": imported["idempotent_reimport"],
        "unrelated_script_preserved": imported["unrelated_script_preserved"],
        "source_process_id": source["process_id"],
        "destination_process_id": imported["process_id"],
        "tampered_backend_metadata_accepted_semantically": checks[
            "tampered_backend_metadata_does_not_change_semantics"
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
