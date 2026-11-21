# architecture-web.Commands

## Purpose and Scope
Own commands for [architecture-web](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Follow the [Web package contract](../../../DESIGN.md). Keep mutable authority state actor-isolated and UI state scoped to its view.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Component composition | Owned lifecycle | Recheck component callers on changes |

## Architecture
```text
Public entry -> Commands owner -> result or explicit failure
```

## Contracts and Invariants
Session state has one actor owner; rendered text is plain data; source is obtained only through Client; shutdown awaits owned tasks; invalidation never resets user transform unconditionally.

Unknown CLI options fail before server startup with a typed argument error and process exit status 4. This path does not depend on platform-specific persistence validation errors.

## Verification and Change Impact
The real HTTP/WebSocket integration tests and browser gesture/update probes exercise the owning behavior. Native-only target; no conditional synchronization weakening.
