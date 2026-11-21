# ArchitectureClient.Connection

## Purpose and Scope
Own connection within [ArchitectureClient](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Typed versioned IPC client shared by all consumers. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Connection -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Snapshot SDK
ArchitectureSnapshotReading declares acquireInputs, scanSnapshot, readInput and releaseInputs as protocol requirements. The concrete Client maps them to inputs.acquire/read/release and graph.scan on the same daemon. It preserves typed upstream failures and immutable DTOs; it never treats source.read preview as a full original.

Provider credential clients share an actor admission queue across value copies. At most 64 pending calls are paced to 32 requests per second, below host admission; cancellation removes pending reservations and socket work still has the transport deadline. Host clients bypass this Provider pacing.
