# ArchitectureExplorerWeb

## Purpose and Scope
Independent native macOS 27+ Web package. Parent: [system/headless package](../../DESIGN.md). Children: [Web pages](Sources/ArchitectureWeb/DESIGN.md), [Server composition](Sources/ArchitectureServer/DESIGN.md), [Native host](Sources/ArchitectureHTTPHost/DESIGN.md), [entry point](Sources/architecture-web/DESIGN.md).

## Responsibilities and Boundaries
SwiftHTML creates the page shell, bundled Cytoscape renders bounded views, ELK runs in workers, and SwiftWebCore/native host serve authenticated HTTP/WS. Only ArchitectureClient accesses graph data. Repository-map mode reads one working-tree scope through the Core filesystem reader and requests a selected-file outline from Frontend. It starts no index or daemon and writes no database. No runtime Node/npm/WASM/CDN build.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client](../../Sources/ArchitectureClient/DESIGN.md) | depends on | Versioned same-user RPC | Shared daemon | Never duplicate analysis |
| [Core](../../Sources/ArchitectureCore/DESIGN.md) | depends on | Values, signals | Session process cleanup | Scope signal ownership to helper |
| [Native host](Sources/ArchitectureHTTPHost/DESIGN.md) | child | Upgraded channel lifecycle | Pinned SwiftWeb adapter | Close rejected upgrades |

## Architecture
```text
Browser -> Session authority -> SwiftWeb routes -> ArchitectureClient -> daemon
    |             |
    |         HTTP/WS authorization
    +-> Cytoscape + ELK worker -> bounded view with provenance
```

## Contracts and Invariants
Exact loopback Host/Origin, one-use short-lived fragment token and HttpOnly session. Every source request is by entity/digest through Client. Text is escaped. A query/snapshot/request generation gates layout responses. Ordinary trackpad wheel input pans without zoom; pinch zooms at the pointer. Updates preserve user pan/zoom/selection. List navigation provides the graph's textual alternative.

## State, Ownership, and Lifecycle
SessionAuthority actor owns token consumption and sessions. Helper owns its listener, worker tasks and signal-driven shutdown; daemon remains shared. WebSocket streams retain at most their latest invalidation state and await socket writes. JS requests/layouts carry generation identity; snapshots are immutable.

## Failure, Concurrency, and Constraints
Only 127.0.0.1 is supported. Unauthenticated upgrades close before data. Native HTTP/WS bodies have a 4 MiB bound. Queries and layout use root limits. Worker failures are visible diagnostics; source and provider text never becomes executable HTML.

## Verification and Change Impact
Tools/web-integration.py runs actual HTTP, cookie, origin/Host and WS handshake tests plus owned helper shutdown. Browser tests run actual workers, graph interactions, source updates and gesture math. Upstream/asset hash changes require these paths again. No evidence is generalized to HTTPS or unsupported platforms.

The layout wrapper keeps one running request and one latest pending request. Rapid view changes replace the pending request instead of queuing every old layout. Response generation checks still reject stale active results. The nested ELK worker therefore receives at most one active calculation at a time. The [Page layout contract](Sources/ArchitectureWeb/Page/DESIGN.md#graph-layout) owns stable compound placement and the calculation deadline; saved exports embed the same model and engine.
