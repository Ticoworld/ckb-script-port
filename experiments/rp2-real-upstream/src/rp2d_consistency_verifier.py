#!/usr/bin/env python3
"""Fail-closed checker for RP2-D reopen classifications.

The checker consumes only fresh-process reopen observations and the crash
matrix.  It does not trust the import worker's success bit.  Its fallback
derivations support evidence captured before the optional S/H/P fields were
added to the reopen worker.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--crash-matrix", type=Path)
    parser.add_argument("--r1-evidence", type=Path,
                        help="JSON array/object containing R1 safety observations")
    parser.add_argument("--commit-race", type=Path,
                        help="JSON array of commit-edge race observations")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.crash_matrix and not args.r1_evidence and not args.commit_race:
        parser.error("at least one evidence input is required")
    matrix = load(args.crash_matrix) if args.crash_matrix else []
    rows = []
    failures = []
    for item in matrix:
        reopen = item.get("reopen") or {}
        expected = item.get("expected")
        s_complete = reopen.get("s_complete")
        h_complete = reopen.get("h_complete")
        p_complete = reopen.get("p_complete")
        if s_complete is None:
            s_complete = bool(reopen.get("a_registered") and reopen.get("a1_live"))
        if h_complete is None:
            h_complete = bool(reopen.get("a1_live"))
        if p_complete is None:
            p_complete = bool(reopen.get("a_registered"))
        authority_unchanged = item.get("authority_before") == reopen.get("authority_fingerprint")
        coherent = (
            expected in {"OLD_COMPLETE", "NEW_COMPLETE"}
            and reopen.get("consistency") == expected
            and reopen.get("b_registered") is True
            and reopen.get("a_type_registered") is True
            and ((not s_complete and not h_complete and not p_complete)
                 if expected == "OLD_COMPLETE"
                 else (s_complete and h_complete and p_complete))
            and item.get("crash_exit_code", 0) != 0
            and item.get("retry_exit_code") == 0
            and authority_unchanged
        )
        classification = expected if coherent else "TORN_INVALID"
        row = {
            "backend": item.get("backend"),
            "source_artifact_backend": item.get("source_artifact_backend"),
            "stage": item.get("stage"),
            "expected": expected,
            "classification": classification,
            "s_complete": s_complete,
            "h_complete": h_complete,
            "p_complete": p_complete,
            "global_minimum": reopen.get("global_minimum"),
            "authority_observed": bool(reopen.get("authority_fingerprint")),
            "authority_unchanged": authority_unchanged,
            "unrelated_script_present": reopen.get("b_registered") is True,
            "retry_exit_code": item.get("retry_exit_code"),
        }
        rows.append(row)
        if not coherent:
            failures.append(row)
    result = {
        "schema_version": 1,
        "experiment": "D2-RP2D-persisted-state-consistency",
        "rows": rows,
        "checked": len(rows),
        "passed": bool(rows) and not failures,
        "failures": failures,
    }
    safety_rows = []
    safety_failures = []
    if args.r1_evidence:
        raw = load(args.r1_evidence)
        if isinstance(raw, dict):
            raw = raw.get("safety_evidence", raw.get("rows", []))
        for item in raw:
            mode = item.get("mode")
            if mode == "live-import-rejected":
                coherent = bool(item.get("rejected_before_mutation")
                                and item.get("authority_unchanged_on_rejection")
                                and item.get("offline_retry_succeeded"))
            elif mode in {"artifact-remove", "artifact-replace"}:
                coherent = bool(item.get("owned_object_model")
                                and item.get("original_artifact_removed_or_replaced")
                                and item.get("import_succeeded")
                                and item.get("authority_unchanged"))
            elif mode == "simultaneous-import":
                same = item.get("same_artifact") or {}
                conflict = item.get("conflicting_artifact") or {}
                coherent = bool(same.get("first_committed")
                                and same.get("second_rejected_busy")
                                and same.get("retry_idempotent")
                                and conflict.get("rejected_after_winner")
                                and item.get("persisted_state_coherent")
                                and item.get("authority_unchanged"))
            else:
                coherent = False
            row = {"mode": mode, "backend": item.get("backend"), "coherent": coherent}
            safety_rows.append(row)
            if not coherent:
                safety_failures.append(row)

    commit_rows = []
    commit_failures = []
    commit_input = args.commit_race
    if commit_input:
        raw = load(commit_input)
        if isinstance(raw, dict):
            raw = raw.get("commit_race", raw.get("rows", []))
        for item in raw:
            classification = (item.get("reopen") or {}).get("consistency") or item.get("classification")
            authority_before = item.get("authority_before")
            authority_after = (item.get("reopen") or {}).get("authority_fingerprint")
            coherent = bool(item.get("commit_enter_observed")
                            and item.get("crash_exit_code", 0) != 0
                            and classification in {"OLD_COMPLETE", "NEW_COMPLETE"}
                            and item.get("reopen_exit_code", 1) == 0
                            and item.get("retry_exit_code", 1) == 0
                            and authority_before == authority_after)
            row = {
                "backend": item.get("backend"),
                "trial": item.get("trial"),
                "classification": classification,
                "commit_enter_observed": bool(item.get("commit_enter_observed")),
                "commit_exit_observed": bool(item.get("commit_exit_observed")),
                "coherent": coherent,
            }
            commit_rows.append(row)
            if not coherent:
                commit_failures.append(row)
    result["safety_evidence"] = safety_rows
    result["safety_checked"] = len(safety_rows)
    result["safety_failures"] = safety_failures
    result["commit_race"] = commit_rows
    result["commit_race_checked"] = len(commit_rows)
    result["commit_race_failures"] = commit_failures
    result["passed"] = (result["passed"] if args.crash_matrix else True) \
        and not safety_failures and not commit_failures \
        and (not args.r1_evidence or bool(safety_rows)) \
        and (not args.commit_race or bool(commit_rows))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
