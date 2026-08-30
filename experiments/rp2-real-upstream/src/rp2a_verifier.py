#!/usr/bin/env python3
"""Independent, fail-closed verifier for RP2-A JSONL traces.

This verifier intentionally does not consume an importer result or a future
package success bit. It classifies only observed protocol/storage events.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REQUIRED = {
    "schema_version",
    "run_id",
    "client_id",
    "backend",
    "sequence",
    "event_type",
    "origin",
    "fields",
}


def load_events(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    events: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return [], [f"cannot read {path}: {exc}"]
    for line_number, line in enumerate(lines, 1):
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"{path}:{line_number}: invalid JSON: {exc}")
            continue
        if not isinstance(item, dict):
            errors.append(f"{path}:{line_number}: event is not an object")
            continue
        missing = REQUIRED - item.keys()
        if missing:
            errors.append(f"{path}:{line_number}: missing {sorted(missing)}")
        if item.get("schema_version") != 1:
            errors.append(f"{path}:{line_number}: unsupported schema_version")
        if item.get("backend") not in {"rocksdb", "sqlite"}:
            errors.append(f"{path}:{line_number}: invalid backend")
        if not isinstance(item.get("fields"), dict):
            errors.append(f"{path}:{line_number}: fields is not an object")
        events.append(item)
    sequences = [event.get("sequence") for event in events]
    if sequences != list(range(1, len(sequences) + 1)):
        errors.append(f"{path}: sequence is not contiguous from 1")
    return events, errors


def classify(events: list[dict[str, Any]], errors: list[str]) -> dict[str, Any]:
    if not events:
        return {"classification": "INCOMPLETE_TRACE", "errors": errors or ["no events"]}

    case = next(
        (event["fields"] for event in events if event["event_type"] == "case_started"),
        {},
    )
    event_types = [event["event_type"] for event in events]
    origins = [event["origin"] for event in events]
    normal_origins = {
        "normal_chain_proof",
        "normal_filter_scheduler",
        "normal_filter_processing",
        "normal_synchronizer",
        "registration",
    }
    direct = any("adversarial" in origin or "direct" in origin for origin in origins)
    has_normal_filter = any(
        event["event_type"] in {"get_block_filters_requested", "block_filters_accepted", "filter_block_entered"}
        and event["origin"] in normal_origins
        for event in events
    )
    accepted = [
        event for event in events if event["event_type"] == "block_filters_accepted"
    ]
    no_match = [
        event for event in accepted if event["fields"].get("match_count") == 0
    ]
    filter_blocks = [
        event for event in events if event["event_type"] == "filter_block_entered"
    ]
    authority_rejected = any(
        event["event_type"] in {"handoff_validation_rejected", "authority_validation_rejected"}
        for event in events
    )
    authority_accepted = any(
        event["event_type"] == "chain_authority_accepted" for event in events
    )
    unchanged = any(
        event["event_type"] == "authority_fingerprint_unchanged"
        and event["fields"].get("unchanged") is True
        for event in events
    )
    rows_only = any(
        event["event_type"] == "rows_only_shortcut" for event in events
    )
    shortcut = any(
        event["event_type"] in {"direct_progress_mutation", "direct_authority_mutation"}
        for event in events
    )
    direct_authority = any(
        event["event_type"] == "direct_authority_mutation" for event in events
    )
    approved_import = next(
        (
            event
            for event in events
            if event["event_type"] == "approved_import_transition"
            and event["origin"] == "approved_import_seam"
        ),
        None,
    )

    def import_trace_is_observable() -> bool:
        if approved_import is None:
            return False
        fields = approved_import["fields"]
        coverage_start = fields.get("coverage_start")
        coverage_end = fields.get("coverage_end")
        next_filter_start = fields.get("next_filter_start")
        if not all(isinstance(value, int) for value in (coverage_start, coverage_end, next_filter_start)):
            return False
        if coverage_start < 0 or coverage_end < coverage_start:
            return False
        if next_filter_start != coverage_end + 1:
            return False
        independent_queries = any(
            event["event_type"] == "import_state_observed"
            and event["origin"] == "independent_query_observer"
            and event["fields"].get("baseline_equal") is True
            and set(event["fields"].get("query_set", []))
            >= {"get_cells", "get_transactions", "script_status"}
            for event in events
        )
        independent_authority = any(
            event["event_type"] == "authority_fingerprint_unchanged"
            and event["origin"] == "independent_authority_observer"
            and event["fields"].get("unchanged") is True
            for event in events
        )
        if not independent_queries or not independent_authority:
            return False
        # A future import trace must not contain a normal request covering the
        # claimed interval. Requests after the imported boundary are valid.
        for event in events:
            if event["event_type"] != "get_block_filters_requested":
                continue
            start = event["fields"].get("start")
            if isinstance(start, int) and start <= coverage_end:
                return False
        return True

    expected = case.get("expected_classification")
    if errors:
        classification = "INCOMPLETE_TRACE"
    elif rows_only:
        classification = "ROWS_ONLY"
    elif direct_authority:
        classification = "AUTHORITY_INVALID"
    elif shortcut or direct and any(
        event["event_type"] in {"script_progress_after", "min_filtered_after"}
        for event in events
    ):
        classification = "DIRECT_PROGRESS_MUTATION"
    elif authority_rejected and unchanged:
        classification = "AUTHORITY_INVALID"
    elif not authority_accepted and case.get("requires_authority"):
        classification = "AUTHORITY_INVALID"
    elif import_trace_is_observable() and authority_accepted and unchanged:
        classification = "GENUINELY_NOT_REQUESTED"
    elif has_normal_filter and no_match and filter_blocks:
        classification = "NORMAL_FILTERED"
    elif has_normal_filter and no_match:
        classification = "REQUESTED_NO_MATCH"
    else:
        classification = "INCOMPLETE_TRACE"

    return {
        "classification": classification,
        "expected_classification": expected,
        "case": case.get("case"),
        "event_count": len(events),
        "filter_requests": [
            event["fields"] for event in events if event["event_type"] == "get_block_filters_requested"
        ],
        "accepted_ranges": [
            event["fields"] for event in accepted
        ],
        "filter_block_count": len(filter_blocks),
        "authority_accepted": authority_accepted,
        "authority_fingerprint_unchanged": unchanged,
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    files = sorted(args.events_dir.glob("*.jsonl"))
    results: list[dict[str, Any]] = []
    for path in files:
        events, errors = load_events(path)
        result = classify(events, errors)
        result["file"] = path.name
        results.append(result)

    failures: list[str] = []
    for result in results:
        expected = result.get("expected_classification")
        actual = result.get("classification")
        if expected and expected != actual:
            failures.append(f"{result['file']}: expected {expected}, got {actual}")
        if actual == "INCOMPLETE_TRACE":
            failures.append(f"{result['file']}: incomplete trace")

    summary = {
        "schema_version": 1,
        "files": results,
        "passed": not failures and bool(results),
        "failures": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
