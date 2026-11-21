# ArchitectureServer.PageDelivery

## Purpose and Scope
Own pagedelivery for [ArchitectureServer](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Follow the [Web package contract](../../../DESIGN.md). Keep mutable authority state actor-isolated and UI state scoped to its view.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Component composition | Owned lifecycle | Recheck component callers on changes |

## Architecture
```text
Public entry -> PageDelivery owner -> result or explicit failure
```

## Contracts and Invariants
Session state has one actor owner; rendered text is plain data; source is obtained only through Client; shutdown awaits owned tasks; invalidation never resets user transform unconditionally.

The page and its worker consume the same bundled `layout-model.js` asset. The explicit same-origin asset route and page allowlist must include it together.

The explicit asset routes include the pinned `highlight.min.js` grammar asset requested by the [Page renderer](../../ArchitectureWeb/Page/DESIGN.md). It uses the same Host/Origin guard and JavaScript MIME type as existing renderer assets; it carries no workspace source or credentials.

## Verification and Change Impact
The real HTTP/WebSocket integration tests and browser gesture/update probes exercise the owning behavior. Native-only target; no conditional synchronization weakening.

Extension reads use authenticated GET; approval, revocation and action confirmation use authenticated POST with exact same Origin and a session-bound CSRF bearer token. No generic mutation endpoint is exposed. The renderer receives only committed public data, never Provider credentials.

## Shared Imported Canvas
Canvas reads use authenticated GET; bounded Canvas mutations use a dedicated same-origin/CSRF POST endpoint. The explicit Canvas renderer asset is mirrored in offline HTML.

In repository-map mode, authenticated repository scope requests use the bounded Core filesystem reader directly. Snapshot RPC and the daemon event stream are unavailable in that mode.

The property action builds a bounded context for the selected source snapshot. The Web host binds the destination to its launching Codex thread. The user can inspect the recipient and exact file inventory. The authenticated response contains the file bodies and graph. Only a host launched with --codex-browser inside a Codex thread registers the route. Its one-time launch URL is opened in that thread’s built-in browser. A separate Site tool call pairs the tab using the launching thread ID, which the HTTP session never discloses. Ordinary browsers cannot enable the node action by navigating to the URL. A property request must use the originating conversation; opening a different analysis session is outside this contract. Authentication, Origin and CSRF guard preparation. No verifier or agent is executed by the Web host.
