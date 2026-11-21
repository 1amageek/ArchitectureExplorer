# ArchitectureService.Daemon

## Purpose and Scope
Own daemon within [ArchitectureService](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Single workspace daemon composition and authenticated same-user RPC. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Daemon -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Stop Acknowledgement

The daemon.stop response is sent before the accept loop sees the stop flag. Cleanup therefore cannot cancel its own shutdown acknowledgement. After the frame is sent, the Service stop flag changes and owned tasks are cancelled and awaited. Runtime tests assert the acknowledgement and a changed daemon epoch after restart.

Extension isolation reserves 16 of the 64 connection tasks for paired host clients. OS peer identity is checked before admission; at most 48 non-host connections may wait for input. The request handler checks peer identity again before authorization, so admission classification is not execution authority. Rejected or unidentified connections close without acquiring a task slot. Native integration holds 50 non-host sockets while a host query completes.
