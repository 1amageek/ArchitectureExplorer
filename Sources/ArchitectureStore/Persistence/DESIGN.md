# ArchitectureStore.Persistence

## Purpose and Scope
Own persistence within [ArchitectureStore](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Atomic SQLite snapshots, producer scopes, identity registry and atomic extension state. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Persistence -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

`publish` advances the live generation strictly monotonically. `importSnapshot` validates and atomically retains an immutable snapshot for `load(id)` without changing `latest`, live `history`, or the Indexer's generation. Imported generation numbers belong to the imported record, not the local live counter. Both operations enforce workspace identity, identity-registry consistency, graph validation and the transaction byte budget.

The `imported_snapshots` table distinguishes explicitly imported rows from live rows. Live retention orders by live generation; import retention orders by local insertion order. Each namespace retains at most the configured retention count. Deletion cascades through normalized rows and import markers. A failed import rolls back without changing the live head or cache.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Extension Transactions
A bounded opaque extension document is stored in its own SQLite row, with atomic replacement and previous-state preservation on error. The Service extension owner validates meaning and serializes candidate mutations before awaiting Store; concurrent graph operations never acquire an extension mutex. This document cannot mutate core facts.

Current development cache format is 2.0. Open only a fresh cache or exactly 2.0; reject older/unversioned formats before changing their schema. There is no migration implementation. External data lives only in the atomic extension_state document; separate annotation/extension graph tables and view_settings storage are removed.
