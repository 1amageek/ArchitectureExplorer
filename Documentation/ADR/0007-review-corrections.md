# Correct the eight reproduced review failures

The review at 8215b4b reproduced eight behavioral failures through actual source analysis, SQLite, IPC and native Web hosting. Corrections preserve the existing role metadata and UI behavior. Owning component DESIGN.md files define the contracts; this record maps failures to verification rather than duplicating those contracts.

| Review failure | Contract owner | Regression owner |
|---|---|---|
| Dropped while condition | Frontend/ControlFlow | ReviewRegressionTests: real multi-condition Swift CFG |
| Deleted callable retained by CFG | Indexer/Indexing | ReviewRegressionTests: CFG, parse failure, deletion and cross-file supplement |
| Blocking LSP input/shutdown | Frontend/Semantic | LSPProcessTests and real-provider process integration |
| Import generation poisoning | Store/Persistence and Service/Requests | ReviewRegressionTests plus compiled CLI regression |
| Pinned CFG reads live source | Service/Requests | ReviewRegressionTests and CLI/MCP regression |
| Loopback cookie collision | Server/Session | Native HTTP/WS integration with one cookie jar and two helpers |
| Incoming path follows outgoing | Graph/Query | ReviewRegressionTests: direction/depth matrix |
| Direct edge and aggregate duplicated | Graph/Query | ReviewRegressionTests: direct/contracted aggregates and original-fact queries |

Imported IR remains available through its returned pinned ID. It does not replace live disk analysis. The live and imported retention namespaces are separately bounded; existing cache rows retain their original live meaning.

The internal cache schema advances to 1.1 with an explicit additive 1.0 migration. Public IR and IPC versions stay 1.0. An older cache reader refuses 1.1 rather than treating imported generations as live. Live-history preservation and the version marker are exercised against an actual legacy SQLite fixture.

Upgrade tests also reproduce legacy ghost nodes with unchanged captured disk inputs. Indexer/CFG revision markers force reconciliation after upgrading. CFG algorithm 2.0 evidence is required by the Frontend's compatibility predicate, so obsolete historical CFGs fail explicitly rather than inheriting a false completeness claim. Historical raw snapshots are preserved.

These corrections do not imply that unrelated open SPEC acceptance gates have passed. Completion evidence is recorded in VERIFICATION.md after execution.

## Ownership review

| Logical state | Native storage and isolation | Access owner | Release |
|---|---|---|---|
| Live generation and snapshot | WorkspaceIndexer actor | reconcile/cfg/supplement | Indexer lifetime |
| SQLite/import markers/head cache | SQLiteGraphStore actor | publish/importSnapshot/load/latest | Actor-confined connection |
| LSP frames, operation gate, shutdown task | LSPProcess actor | Serialized public operations | Awaited cleanup closes handles once and reaps child |
| Web sessions | SessionAuthority actor; immutable per-port cookieName | authorize/exchange | Helper lifetime; bounded one-use bootstrap |

The package is macOS-native with explicit Darwin adapters. WASM/Embedded are unsupported targets; no conditional branch substitutes raw shared state or weakens the actor contracts.

## Development refactor update
The current cache format is 2.0 with explicit rejection of earlier formats. The former additive migration decision is superseded by the user's development policy: remove compatibility code and rebuild derived caches explicitly. Snapshot generation/import isolation remains required and tested.
