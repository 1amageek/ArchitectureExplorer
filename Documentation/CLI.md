# CLI

Run `architecture --help` for accepted options. The default workspace is the current directory. JSON stdout contains only requested data; errors/logs go to stderr. `init` refuses an existing architecture.json. Exports refuse existing output unless `--force` is explicit.

| Command | Behavior |
|---|---|
| index | Reconcile disk and publish; `--trusted-workspace` also acquires offline official metadata |
| index --input FILE | Validate/import schema 1.0 IR into isolated retained snapshots; use the returned ID for pinned queries; live disk indexing is unchanged |
| graph / search / cfg / explain / diff | Query the shared graph, bounded by nodes/edges/depth/bytes |
| status / coverage / capabilities | Inspect input, producer coverage, current progress and unavailable providers |
| export | JSON, Mermaid, true vector SVG or offline read-only HTML for a bounded view |
| explore --watch | Foreground authenticated helper; `--no-open` prints a one-use launch URL |
| semantic | Explicit provider path, entity and operation; requires invocation-level trust |
| mcp | MCP 2025-11-25 JSON-RPC stdio; no progress text on stdout |
| daemon start/status/stop | Same-user workspace daemon identity and explicit lifecycle |
| doctor | Platform/toolchain baseline, helper location and trust state |

Exit codes: 0 handled; 2 invalid arguments/config/schema; 3 unsupported or incomplete requested information; 4 input/analysis failure; 5 policy/trust denial; 6 resource/timeout/connectivity; 7 snapshot/protocol/consistency; 130 cancellation. `--require-complete` rejects partial/stale/unsupported information; it is not a code-quality verdict.

Graph defaults: 500 nodes, 1500 edges, depth 2; maximum depth 8. Search defaults 50, maximum 200. Preserve `snapshotID` and `nextCursor` across pages. Unknown options and invalid enum values are rejected. The current explicit configuration source is workspace architecture.json; alternate `--config` contexts are not implemented.

File outlines (`--level file`) include recorded declarations to the requested depth. Child queries in this mode retain the focused file/declaration as context; other levels keep direct children. Pagination repeats required ancestor context within the declared budget. See the [query contract](../Sources/ArchitectureGraph/Query/DESIGN.md).

Pinned CFG queries/exports return only a supported CFG already recorded in that snapshot. `CFG_UNAVAILABLE` (exit 3) means the selected historical snapshot has no supported CFG, including an obsolete generator version; an unpinned request may generate a new live CFG. The requested historical ID is never replaced with a newer snapshot.

Use `graph --level context` for the captured C4 systems and their catalog relationships. The Web workspace starts in System Context.
