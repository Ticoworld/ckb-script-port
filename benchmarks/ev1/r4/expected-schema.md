# Expected result schema

Each repetition creates `run.json` and an `evidence/` directory.

`run.json` contains:

- `scenario`
- `workload`
- `handoff_height`
- `transaction_count`
- `outputs_per_transaction`
- `batch_size`
- `match_gap`
- `artifact_bytes`
- `d2_storage_bytes`
- `baseline_storage_bytes`

Important evidence JSON fields include:

- `backend`
- `handoff_height`
- `script_hex`
- `request_starts`
- `matched_blocks`
- `script_progress`
- `reopen_and_continue`
- cache-validation counts
- D2 artifact row counts and digest

The timing files contain GNU `/usr/bin/time` fields:

```text
elapsed_s=<seconds> cpu=<percent> max_rss_kb=<kilobytes>
```

The runner fails if cache validation, exact Script registration, import,
reopen, post-H continuation, or the expected request topology fails.
