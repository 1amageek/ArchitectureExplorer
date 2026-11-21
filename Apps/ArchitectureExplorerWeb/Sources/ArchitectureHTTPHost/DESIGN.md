# ArchitectureHTTPHost

## Purpose and Scope
Native HTTP/WebSocket platform adapter owned by the [Web package](../../DESIGN.md). Child: [Runtime](Runtime/DESIGN.md).

## Responsibilities and Boundaries
Adapt the pinned SwiftWebCore rendered routes to NIO. Preserve upstream actor, immutable Sendable, COW buffer and event-loop ownership contracts. Application authentication is evaluated before upgrade; a rejected channel must close.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Web package](../../DESIGN.md) | parent | Route hosting and shutdown | Hosting adapter | Revalidate upstream changes with real HTTP/WS tests |
| [Runtime](Runtime/DESIGN.md) | child | Listener and channel lifecycle | Pinned upstream host | NIO futures remain inside this platform boundary |

## Architecture
```text
SwiftWebCore rendered routes -> Native listener -> bounded HTTP or authorized WebSocket -> ArchitectureClient
```

## Contracts and Invariants
Same request, session, middleware and binary buffer behavior as the pinned upstream. New refusal invariant: session/Origin/Host rejection closes the owned channel before fallback. HTTP bodies and WS frames are bounded to 4 MiB. Descriptor and channel owners close once.

## Verification and Change Impact
Tools/web-integration.py tests real authenticated/unauthenticated HTTP/WS and helper shutdown. native-host-upstream.json pins originals and lists all local changes. Recheck ArchitectureServer on changes.
