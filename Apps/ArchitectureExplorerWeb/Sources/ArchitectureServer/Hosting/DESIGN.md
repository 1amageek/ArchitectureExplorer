# ArchitectureServer.Hosting

## Purpose and Scope
Own hosting for [ArchitectureServer](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Follow the [Web package contract](../../../DESIGN.md). Keep mutable authority state actor-isolated and UI state scoped to its view.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Component composition | Owned lifecycle | Recheck component callers on changes |

## Architecture
```text
Public entry -> Hosting owner -> result or explicit failure
```

## Contracts and Invariants
Session state has one actor owner; rendered text is plain data; source is obtained only through Client; shutdown awaits owned tasks; invalidation never resets user transform unconditionally.

Before serving a live workspace or issuing a browser launch URL, the Web host must complete an authorized `events.poll` using its own OS peer identity. A rejected peer fails startup with guidance to restart the workspace with the paired build. If a running daemon later rejects the Web host, the subscription sends a terminal `liveUnavailable` event before closing. Transient transport failures close the stream so an authenticated browser can reconnect. Repository-map startup remains independent of the daemon.

## Verification and Change Impact
The real HTTP/WebSocket integration tests and browser gesture/update probes exercise the owning behavior. Native-only target; no conditional synchronization weakening.

## Subscription Termination

SubscriptionStreams actor owns each WebSocket delivery task. A channel close callback only requests cancellation; it never awaits the task that may itself be closing that channel. The helper cancels and awaits all retained subscriptions during shutdown. This prevents a self-await cycle when daemon failure causes a delivery task to close its own channel. The Web integration test stops the owned daemon with an authenticated channel open and verifies closure and helper termination.

Repository-map mode runs a read-only collection browser without connecting to or starting a workspace daemon. An authenticated request uses the Core filesystem reader and the Frontend repository architecture projection. Browser history retains paths and reopens them against current disk contents. Imported map metadata describes repository roles and inter-repository dependencies only.
