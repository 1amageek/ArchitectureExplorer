# ArchitectureService.Requests

## Purpose and Scope
Own requests within [ArchitectureService](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Single workspace daemon composition and authenticated same-user RPC. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Requests -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

An explicit snapshotID is immutable authority for CFG queries and exports: use the Frontend's supported recorded CFG or return CFG_UNAVAILABLE. Pinned requests never reconcile disk or generate a replacement CFG. Unpinned CFG queries may generate and publish through the Indexer. Import uses the Store's isolated import contract and never directly publishes a live generation.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Snapshot SDK routes
inputs.acquire/read/release and graph.scan delegate to [SnapshotAccess](../SnapshotAccess/DESIGN.md), with an existing pinned snapshot or a lease-held snapshot. These generic routes do not launch verification or alter source/index state. Service shutdown drains owned captures.

## Shared Imported Canvas
canvas.* delegates to the shared Canvas session owner after host authorization; no file path is read from browser-supplied data.

A source.read request can supply both startByte and endByte to read a UTF-8 subrange contained in its pinned entity anchor. The full source digest and the existing preview budget still apply.
