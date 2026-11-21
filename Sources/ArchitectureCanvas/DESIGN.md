# ArchitectureCanvas

## Purpose and Scope
Generic imported diagram model and shared view sessions. Parent: [system/package](../../DESIGN.md). Children: [Contracts](Contracts/DESIGN.md), [Import](Import/DESIGN.md), [Sessions](Sessions/DESIGN.md).

## Responsibilities and Boundaries
Own diagram file decoding and display state. Depend only on ArchitectureCore. Import does not publish ArchitectureIR facts, run tools or change source. The browser owns drawing and transient gesture frames; the shared Session actor owns acknowledged state consumed by browser and MCP.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [System](../../DESIGN.md) | parent | Independent Explorer composition | Source and presentation separation | No verifier dependencies |
| [Service](../ArchitectureService/DESIGN.md) | used by | CanvasFileReading and CanvasSessionManaging | Shared authenticated operations | Lifecycle and authority |
| [Page](../../Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Page/DESIGN.md) | used by | Canvas document/session JSON | Existing Canvas renderer | Preserve source card/property design |

## Architecture
```text
File / Provider graph -> Reader -> CanvasDocument -> Session actor
                                                   ↑       ↓
                                              MCP / Web -> shared Canvas
```

## Contracts and Invariants
Exactly one validated model covers hierarchy, relations, CFG, data flow, state transitions, ordered sequence/timeline and proof dependencies. Diagram kind is explicit or format-defined; semantics are never inferred from labels. Common model includes hierarchy, lanes, explicit event order, edge labels/roles, details and original data. Static SVG is isolated image content. Source snapshots and external publication identities remain distinct provenance. Source-backed cards retain their current design.

## Runtime Flows
Read file -> strict format profile -> validate endpoints/hierarchy/bounds -> open session -> shared commands -> render. Rejected imports preserve existing sessions. Browser imports multiple files as separate sessions. External committed graphs enter the same document projection and Canvas path; the old separate SVG graph renderer is removed.

## State, Ownership, and Lifecycle
One session actor per daemon, in-memory until close/shutdown. Revisioned commands serialize mutations. Browser gestures remain local during movement and coalesce into acknowledged camera updates; remote revisions restore acknowledged state. Session ID is distinct from authentication and Provider sessions. Disconnected screens may reconnect by session ID; expired daemon sessions fail visibly.

## Failure, Concurrency, and Constraints
Bounds belong to child contracts. XML external entities/DTDs and executable diagram directives are rejected. No implicit external tool acquisition. Failed import, unsupported syntax and unknown session are typed errors.

## Verification and Change Impact
Real fixtures for every format and every kind, parser failures, seven-kind engine tests, session/MCP/HTTP integration and actual browser file opening. Recheck all direct consumers when documents or commands change.
