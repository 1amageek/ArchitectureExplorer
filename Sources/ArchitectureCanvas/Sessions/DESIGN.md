# ArchitectureCanvas.Sessions

## Purpose and Scope
Own shared imported/external view sessions and SVG export from acknowledged geometry. Parent: [Canvas](../DESIGN.md). No children. Existing live source navigation remains browser-owned.

## Responsibilities and Boundaries
Own session admission, revisions, selection, filters, collapse, focus, layout intent, camera and acknowledged geometry. Browser rendering and transient gestures remain outside this owner. Source facts and verification execution remain outside Canvas.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Canvas](../DESIGN.md) | parent | Session composition | Module boundary | State is presentation only |
| [Contracts](../Contracts/DESIGN.md) | depends on | Document and session protocols | Validation and value guarantees | Host presentation IDs are distinct from facts |
| [Import](../Import/DESIGN.md) | depends on | CanvasFileReading | Atomic validated read | Reject before replacing old state |
| [Requests](../../ArchitectureService/Requests/DESIGN.md) | used by | CanvasSessionManaging | Authenticated command routing | Permission checked at admission |

## Architecture
```text
Authenticated command -> session actor -> compare revision -> candidate
                                                     -> budget -> atomic publish
Web / MCP / CLI <- same acknowledged revision and presentation state
```

## Contracts and Invariants
Operations are listed in [session API](../../../Documentation/CANVAS-FORMATS.md#shared-sessions). Unknown/closed sessions fail explicitly. Paged element reads and a state-only read keep MCP inspection separate from bounded mutation acknowledgments. An expected revision rejects stale mutations. Failed parsing, validation or admission preserves the previous complete value. Collapse projects connections at display/export time without rewriting endpoints. Focus expands ancestors and clears filters so the requested element can be shown.

SVG sessions expose the host-owned `__svg` image identity; sequences expose `__lane:<id>` and `__fragment:<index>` for selection/focus/geometry without adding semantic facts. JSON export retains the complete normalized document and acknowledged view state. Graph SVG export requires acknowledged geometry and uses current visible boxes and projected connections; it is a logical vector export, not a pixel-identical copy of browser edge routes. Static SVG exports retain the validated image.

## State, Ownership, and Lifecycle
One actor per daemon isolates all session storage and mutation. Sessions are in memory until close or shutdown. Shutdown removes all sessions and prevents further admission. A command has no suspension inside its actor-isolated state transition; callers may run concurrently, while compare-and-publish remains atomic.

## Failure, Concurrency, and Constraints
At most 32 sessions, 16 MiB total encoded state, and 3 MiB per session. Geometry accepts at most 756 bounded boxes (500 semantic nodes, 128 lanes, 128 fragments), with finite coordinates within ±1,000,000 and positive dimensions. Camera zoom is 0.12–3 with finite pan within ±10,000,000. Invalid filters, IDs, layout kinds and geometry fail without state changes. Cancellation is checked before publication; a committed mutation returns its acknowledgment even if transport cancellation arrives afterward.

## Verification and Change Impact
[CanvasTests](../../../Tests/ArchitectureTests/CanvasTests.swift) owns atomic replacement, CAS concurrency, bounds, invalid presentation updates, static/sequence identities, shutdown and SVG projection/reimport. [Native integration](../../../Tools/canvas-integration.py) owns shared HTTP/MCP behavior and production renderer composition. Changes recheck Service, CLI, MCP, browser reconciliation and export.
