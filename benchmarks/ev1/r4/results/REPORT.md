# R4 public benchmark report

These are controlled-fixture measurements using the pinned CKB light-client
protocol path and SQLite. They are not mainnet, Internet, mobile, or production
performance measurements.

| Workload | Baseline median | D2 destination median | Total D2 median |
|---|---:|---:|---:|
| H=10,000 sparse | 45.17 s | 12.79 s | 12.79 s |
| H=5,000 moderate | 28.62 s | 6.29 s | 6.42 s |

In both workloads baseline performed historical filtering from the historical
start. D2 performed zero historical Script requests after import and began at
H+1, while reaching equivalent final state.

Post-H processing was measured separately and was not shown to be faster. Whole
database copying remains a separate comparator and may be simpler for
same-backend whole-install migration. No universal speed claim follows.
