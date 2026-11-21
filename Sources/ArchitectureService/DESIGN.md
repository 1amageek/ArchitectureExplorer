# ArchitectureService

## Purpose and Scope
Single workspace daemon composition and authenticated same-user RPC.
Parent: [system](../../DESIGN.md). Native SwiftPM module root.
- [Daemon](Daemon/DESIGN.md)
- [Requests](Requests/DESIGN.md)
- [SnapshotAccess](SnapshotAccess/DESIGN.md)

- [Extensions](Extensions/DESIGN.md)

## Responsibilities and Boundaries
Own only the responsibility above. Source code is read-only. Facts are scoped by producer and input generation.

## Related Designs
| Design | Relationship | Contract Used | Cautions |
|---|---|---|---|
| [System](../../DESIGN.md) | parent | Composition | Preserve formal independence |
| [ ArchitectureIndexer ](../ArchitectureIndexer/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |
| [ ArchitectureGraph ](../ArchitectureGraph/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |

## Architecture
```text
Caller -> ArchitectureService public contract -> Daemon, Requests
```

## Contracts and Invariants
- Transfer values are immutable and Sendable.
- Unsupported information is explicit, never an empty success.
- Identity keys own lexical path, owner, kind and normalized signature; source revisions own exact bytes.
- All facts retain evidence and immutable snapshot identity.

## Verification and Change Impact
Behavior owner: [ArchitectureTests](../../Tests/ArchitectureTests). Test successful behavior, malformed inputs, budgets and the concrete consumer path. Recheck direct dependents when a public contract changes.

## Index Job Lifecycle

A single shared index job runs per workspace; concurrent requests join its identity. Short result/status requests stay responsive while immutable capture and file workers run. The Indexer owns desired/published generations and worker progress; Service owns bounded terminal job responses. Task completion or failure is retained explicitly. Daemon shutdown cancels and awaits its watch/index tasks. A configurable FrontendProvider is injected at composition for bounded behavioral scheduling tests; production uses SkeletonFrontend.

## Immutable View Cache

The Service actor owns a cache of encoded JSON view values keyed by immutable snapshot ID and normalized GraphQuery. It holds at most 64 entries and 16 MiB of canonical response data. Snapshot identity prevents stale reuse after publication. Live pending/checking freshness is applied to a shallow response envelope after cache lookup; cached facts and evidence are never mutated. This cache does not hold source bodies or alter query budgets. Cache eviction affects latency only, never query meaning or pagination identity.

## Shared Imported Canvas
Service composes one ArchitectureCanvas session actor. Authenticated host Canvas commands do not publish source snapshots or execute Provider actions.
