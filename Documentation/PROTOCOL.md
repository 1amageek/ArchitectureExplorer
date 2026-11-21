# Protocols

Internal IPC is JSON-RPC 2.0 with protocolVersion 1.0, workspaceID and one newline-delimited UTF-8 message. Frames are at most 4 MiB. Unix sockets live in an atomically created, owner-checked 0700 runtime directory; socket mode is 0600 and peer uid is verified. `daemon.hello` returns an epoch/process identity rather than relying on PID alone.

Graph query methods are declared in the SPEC and implemented by one Service. Snapshot IDs remain fixed across pagination and exports. Expired or mismatched cursors fail explicitly. `events.poll` returns stream epoch/sequence and view invalidation; WebSocket clients refetch their bounded view on invalidation/reconnect. This implementation uses invalidation/resync, not unverified live incremental patch application. GraphDelta is used for immutable history diffs.

Pinned `graph.cfg` never generates live data. `workspace.import` retains a validated pinned snapshot separately from the live publication head, so foreign generation numbers cannot change the Indexer's counter. Overview semantic relations are aggregated once; non-overview queries retain original facts. The owning contracts and regression mapping are linked from ADR 0007.

MCP is a separate 2025-11-25 stdio profile, with initialize/initialized, ping, tools/list, tools/call, cancellation and EOF shutdown. Ten read-only tools call the same Client. A conservative 24 KiB data allowance leaves framing/structured-content space within the 64 KiB response budget. Logs go to stderr. See integration-results.json for the actual client used; universal MCP-client compatibility is not claimed.

Annotations and external graphs occupy separate tables/namespaces. The provider's reportedStatus is preserved. Applicability is computed independently as matchesInputs/stale/unmatched/unknown. Graph construction and source facts are never promoted by an external status.

`workspace.index` begins or joins a shared analysis job and returns its job ID immediately. `workspace.index.result` returns progress or a terminal result. The CLI polls this API, so the per-frame connection deadline is independent of the duration of a full workspace analysis. `workspace.status` remains available before the initial snapshot and reports pending progress rather than waiting for publication. Completed job responses are retained up to the declared small job-history budget.
