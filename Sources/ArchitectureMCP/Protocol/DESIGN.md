# ArchitectureMCP.Protocol

## Purpose and Scope
Own protocol within [ArchitectureMCP](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | MCP 2025-11-25 stdio lifecycle and bounded source-query and presentation-session tool adapter. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Protocol -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Shared Imported Canvas
Canvas tools operate on shared presentation sessions and advertise presentation mutations separately from read-only graph queries. External verification execution and approvals remain outside MCP.
