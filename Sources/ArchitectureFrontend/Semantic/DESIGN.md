# ArchitectureFrontend.Semantic

## Purpose and Scope
Own semantic within [ArchitectureFrontend](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Pure source providers; parse immutable bytes, never write stores. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Semantic -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

LSPProcess owns nonblocking input and output descriptors. Its actor serializes complete notifications and request/response exchanges so suspension cannot interleave frames or consume another request's response. Deadlines start before encoding/transmission and cover operation-queue waiting, partial writes and response reads. Every polling loop checks cancellation and the same deadline even while making progress. A pipe-local F_SETNOSIGPIPE setting turns closed-input writes into typed errors without changing process-wide signal policy.

A failed partial frame marks the session stopping, because another frame cannot repair the truncated JSON-RPC body. Subsequent public operations reject that session; shutdown remains available and bounded.

Shutdown is an idempotent, actor-owned cleanup task that survives caller cancellation. It attempts protocol shutdown within two seconds, permits two seconds for graceful process exit, then sends SIGKILL if necessary and permits two seconds for confirmed exit. Owned handles close once; failure to observe exit is explicit. Pending operations observe closed/stopping state. Scoped Data borrows are used only during synchronous Darwin read/write calls; pointers never escape and offsets stay within initialized owned storage.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.
