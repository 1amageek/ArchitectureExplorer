# ArchitectureIR.Snapshots

## Purpose and Scope
Own snapshots within [ArchitectureIR](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Language-neutral immutable facts, provenance, query and exchange contracts. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Snapshots -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence. InputLease describes lease/snapshot/context/metadata, counts and expiry without unbounded file lists. SnapshotPage carries a separately paged raw collection and a pinned cursor; facts may reference endpoints on other raw pages. InputChunk contains an offset-bounded byte slice with original file digest/size and EOF. Their availability does not establish semantic completeness or source correctness. The [SnapshotAccess owner](../../ArchitectureService/SnapshotAccess/DESIGN.md) defines acquisition/lifetime/budget behavior.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.
