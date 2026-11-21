# Nonblocking index jobs and daemon readiness

The listener previously waited for initial indexing before accepting hello/status. A slow workspace could therefore consume the fixed per-frame IPC deadline even though startup and parsing were making progress.

Bind the private socket and accept clients immediately. The watch task owns reconciliation independently. `workspace.index` returns a shared job ID; `workspace.index.result` returns progress or the terminal result. The CLI waits through short polling requests, so a long initial index does not require a single request to remain open for the full analysis. Ctrl-C stops that caller's wait without terminating a shared daemon. Shutdown cancels and awaits daemon-owned watch/index tasks.

The Indexer actor owns generation, published state and progress counters. Immutable filesystem captures run as cancellable child tasks outside its isolation. Syntax file jobs run up to the configured worker budget (default 4); publication remains ordered/atomic. `workspace.status` and event polling read published state/progress without awaiting an in-progress SQLite transaction. Graph queries use the last published snapshot and report pending/stale relative to live inputs. Before first publication, INDEX_PENDING remains an explicit diagnostic and WebSocket invalidation triggers the initial view fetch.

A behavioral test instruments simultaneous provider entries and verifies at least two and at most four active parses. Medium-workspace integration checks responsiveness while indexing and confirms the same job is shared by concurrent clients. No speed claim is inferred solely from TaskGroup syntax.
