# ArchitectureGraph.Export

## Purpose and Scope
Own export within [ArchitectureGraph](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Bounded immutable projections, graph traversal, diff and export. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Export -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

The HTML export embeds the shared compact desktop renderer. Its UI density and gestures follow the [Web page contract](../../../Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Page/DESIGN.md); saved views retain explicit snapshot status and need no network. It embeds the shared layout model and pinned ELK engine as well as Cytoscape, so containment frames and dependency ranks use the same algorithm as live views. The pinned syntax asset is embedded before the renderer for recorded declaration signatures under the same Page contract; source bodies are still not bundled.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

Service exports attach the atomic external publication envelope under `extensions.aex-1.3`. Offline rendering uses literal data, disables every Provider action and makes no source/artifact fetches.
