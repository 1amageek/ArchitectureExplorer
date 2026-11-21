# ArchitectureCore.Filesystem

## Purpose and Scope
Own filesystem within [ArchitectureCore](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Values, diagnostics, bounded filesystem and socket transport. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Filesystem -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Repository collection navigation
A local repository map supplies display attributes, dependency edges and direct checkout names. The filesystem reader binds navigation to those checkouts inside the collection root. Directory requests identify the repository boundary for architectural projection. Navigation never enumerates repository directory entries. The bounded reader distinguishes a missing optional input from invalid, inaccessible or symlinked paths. A source preview reads at most 16 KiB plus one truncation byte. Descriptor-relative traversal rejects symlinks and special files. Neither operation asks the indexer to build a snapshot.
