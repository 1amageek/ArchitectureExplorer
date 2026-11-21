# ArchitectureExplorer

## Purpose and Scope
Independent local architecture exploration for Swift and Rust. This directory is both system and headless package root. It never depends on swift-formal. User instruction supersedes the specification deployment floor: macOS 27+, Swift 6.4.1.

## Responsibilities and Boundaries
Read-only source analysis; immutable evidence-backed graph; shared local daemon; bounded CLI/MCP/Web queries. No verifier orchestration, source mutation, telemetry or implicit runtime downloads.

## Related Designs
- [ArchitectureCore](Sources/ArchitectureCore/DESIGN.md)
- [ArchitectureIR](Sources/ArchitectureIR/DESIGN.md)
- [ArchitectureExtensions](Sources/ArchitectureExtensions/DESIGN.md)
- [ArchitectureFrontend](Sources/ArchitectureFrontend/DESIGN.md)
- [ArchitectureGraph](Sources/ArchitectureGraph/DESIGN.md)
- [ArchitectureCanvas](Sources/ArchitectureCanvas/DESIGN.md)
- [ArchitectureStore](Sources/ArchitectureStore/DESIGN.md)
- [ArchitectureIndexer](Sources/ArchitectureIndexer/DESIGN.md)
- [ArchitectureService](Sources/ArchitectureService/DESIGN.md)
- [ArchitectureClient](Sources/ArchitectureClient/DESIGN.md)
- [ArchitectureMCP](Sources/ArchitectureMCP/DESIGN.md)
- [architecture](Sources/architecture/DESIGN.md)
- [Web package](Apps/ArchitectureExplorerWeb/DESIGN.md)

- [SQLite ABI](Sources/CSQLite/DESIGN.md)
- [Grammar ABI](Sources/CArchitectureSyntax/DESIGN.md)
- [Signal boundary](Sources/CArchitectureSignals/DESIGN.md)

## Architecture
```text
Filesystem -> Indexer -> Frontend -> immutable producer result
                 |                   |
                 +----> Store <-------+
                          |
                   Graph + Service (daemon)
                          |
                    Unix JSON-RPC
                          |
                       Client
                   /      |       \
                 CLI     MCP      Web helper -> Browser
```

## Contracts and Invariants
Each entity has a persistent identity key distinct from content revision. Every edge has valid endpoints and evidence. Producer replacement cannot remove another producer's facts. Failed parses retain last-known-good as stale. Only results whose immutable input still matches may publish. Containment is acyclic; dependencies may cycle. Snapshot pagination never mixes revisions. Graph operations are structural, never formal guarantees.

Only the Indexer advances the live workspace publication head. Imported snapshots are independently retained for pinned queries under the [Store contract](Sources/ArchitectureStore/Persistence/DESIGN.md). Cross-component corrections and regression ownership are recorded in [ADR 0007](Documentation/ADR/0007-review-corrections.md).

## Runtime Flows
Reconcile disk -> capture immutable bytes -> parse changed scopes -> compare disk inputs -> publish one SQLite transaction -> notify view invalidation. CFG is selected on demand. CLI, MCP and Web use one daemon, never parallel independent workspace indices. Explicit repository-map browsing uses bounded working-tree reads and selected-file lexical outlines without creating an index.

## State, Ownership, and Lifecycle
SQLite connection: Store actor. Desired generation and scanning tasks: Indexer actor. Daemon holds a same-user exclusive flock and Unix socket; clients never own daemon process lifetimes. Foreground Web helper is session-owned. Input source bodies are transient; snapshots persist anchors and digests only.

The local packaging tool builds into a fresh staging directory, including resources and licenses, before replacing the previous generated bundle. Repeated packaging must accept read-only dependency resources and preserve the previous bundle if assembly fails.

Test-only ArchitectureTests resource bundles, including non-reading provider fixtures, are excluded from the runtime bundle.

## Failure, Concurrency, and Constraints
Default 5 MiB source; 4 MiB IPC frame; 64 KiB MCP; graph 500 nodes/1500 edges; search 50/max 200; finite traversal depth and pinned cursor. File roots resolve symlinks before reads. Untrusted manifests and build scripts are not executed. Cache is user-private and historical snapshots are bounded.

## Verification and Change Impact
Behavioral tests in Tests/ArchitectureTests and Tools/integration.py exercise real Swift/Rust source edits through compiled CLI/daemon/MCP. Web tests exercise authenticated HTTP and WebSocket. No platform support is claimed beyond actual measured host. See Documentation/VERIFICATION.md for evidence and PROGRESS.md for unfinished acceptance criteria.

## External Extension Composition
Extension API [aex-1.3](Documentation/EXTENSIONS-SPEC.md) adds immutable contracts, peer-bound Service authorization, separate durable publication/dispatch state and declarative Web contributions. Explorer never launches an extension or verifier. Existing core graph identities and query budgets remain unchanged.

The local build wrapper pairs a CLI with the exact Web executable digest. A fail-fast cross-configuration lock owns generation and both builds, preventing debug/release jobs from embedding each other's helper identity. Example integration packages are separate explicit consumers: [mock](Examples/ExtensionMock/DESIGN.md) and [actual Invar reader](Examples/InvarReaderProbe/DESIGN.md).

## Imported Canvas Documents
[ArchitectureCanvas](Sources/ArchitectureCanvas/DESIGN.md) owns generic file imports and shared presentation sessions. Authenticated Canvas operations mutate presentation only; source analysis and verifier authority remain unchanged. The same session is used by Web and MCP.

[C4 System Context](Documentation/C4-CONTEXT-SPEC.md) is the Explorer-owned L1 display contract.
