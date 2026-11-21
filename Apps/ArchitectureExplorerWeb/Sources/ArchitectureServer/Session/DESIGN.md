# ArchitectureServer.Session

## Purpose and Scope
Own session for [ArchitectureServer](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Follow the [Web package contract](../../../DESIGN.md). Keep mutable authority state actor-isolated and UI state scoped to its view.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Component composition | Owned lifecycle | Recheck component callers on changes |

## Architecture
```text
Public entry -> Session owner -> result or explicit failure
```

## Contracts and Invariants
Session state has one actor owner; rendered text is plain data; source is obtained only through Client; shutdown awaits owned tasks; invalidation never resets user transform unconditionally.

The session cookie name includes the listening port. Cookies remain host-only, HttpOnly and SameSiteStrict, while independent loopback helpers retain different cookie names in the same browser jar. Each helper accepts only its own named cookie and session value; another helper's cookie never authenticates a request. Host/Origin checks remain authoritative. Port reuse creates a new authority and requires a new launch exchange.

## Verification and Change Impact
The real HTTP/WebSocket integration tests and browser gesture/update probes exercise the owning behavior. Native-only target; no conditional synchronization weakening.
