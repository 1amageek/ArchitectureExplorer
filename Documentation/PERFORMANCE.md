# Performance

The SPEC targets are acceptance goals, not advertised measurements. Tools/performance.py exercises 1000 saved Swift files, about 100k lines and over 10k entities through the compiled CLI/daemon. It records cold indexing, 20 warm bounded queries, 10 saved-file update cycles, response bytes and one final daemon RSS observation. Input hashing, periodic reconciliation and SQLite FULL publication remain enabled. CLI/IPC overhead is included; the RSS sample is not a peak.

The first Medium probe exceeded the 30-second IPC deadline. A native process sample identified redundant row-by-row Swift JSON serialization/SQL preparation during publication. ADR 0005 records the correction. The failed probe is not a successful benchmark. See performance-results.json for the subsequent run and its actual conditions.

The final release run was performed after package builds had stopped. It used 1000 files, 101 lines per file, 12002 entities and 22000 edges on the recorded host with normal hashing, progress observation and FULL SQLite publication enabled.

| Measurement | Result | Scope |
|---|---:|---|
| Daemon ready | 405 ms | Fresh local workspace |
| Cold index | 2200 ms | Includes launch and progress polling |
| Index status p50 / p95 | 5 / 241 ms | 6 observations during cold indexing |
| Maximum scheduled parsers observed | 4 | Actual overlap separately checked by instrumented provider test |
| Warm Unix API query p50 / p95 | 119 / 166 ms | 20 bounded 100-node queries; 200 ms p95 target passed |
| CLI query p50 / p95 | 157 / 174 ms | Includes launching a CLI process |
| Saved-file publication p50 / p95 | 1129 / 1426 ms | Ten full cycles; 1000 ms p95 target failed |
| Final daemon RSS | 248112 KiB | One sample; not peak memory |

Long indexing no longer holds a single fixed-deadline IPC request open: callers receive a shared job ID and poll short progress/result requests. The view cache reuses encoded immutable results by snapshot/query, within 64 entries and 16 MiB. Those changes address the observed deadline and repeated query work; they do not establish adversarial parser termination or the remaining saved-file latency target.

Large synthetic graphs (100k entities/500k edges), 10k source files, GUI frame rate and p95 commit-to-GUI latency still require dedicated controlled measurements. Do not generalize Small/Medium data to those loads or claim the full SPEC performance gate has passed.
