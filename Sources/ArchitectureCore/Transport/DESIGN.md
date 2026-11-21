# ArchitectureCore.Transport

## Purpose and Scope
Own transport within [ArchitectureCore](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Values, diagnostics, bounded filesystem and socket transport. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Transport -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Native Capability Review

| Logical state | Native storage / isolation | Read / mutation | WASM | Embedded | Release |
|---|---|---|---|---|---|
| Socket descriptor/pending frame | LocalConnection actor | actor methods only | unsupported target | unsupported target | close()/deinit exactly once |
| Process termination signal | C volatile sig_atomic_t | async-signal-safe handler / scalar query | unsupported target | unsupported target | process lifetime |
| Daemon peer identity | immutable uid / workspace values | construction / validation | unsupported target | unsupported target | scoped connection |

No target branch removes Sendable or changes actor/Mutex storage to raw mutable state. POSIX buffers are closure-scoped borrows with checked lengths and no escaping pointer. NIO event-loop state stays inside the separately documented native Web platform adapter.

## Abandoned Peer Isolation

A peer can close between accept() and credential/socket configuration. LocalSocket closes that accepted descriptor and returns PEER_CONNECTION_REJECTED; the daemon rejects only that connection and continues accepting other clients. Listener failures retain their fatal distinction. The IPC integration test opens/closes fifty peers and verifies the same live daemon epoch afterward.

## Peer Authentication
Accepted sockets obtain the kernel peer PID/audit identity and Security.framework dynamic code identity. Peer data never comes from JSON. Executable identity is verified against the running code before exposing its path/hash. Missing identity fails protected requests explicitly. Host binaries are pinned at daemon composition; the paired Web digest is produced by Tools/build.py, not workspace configuration. Same-user transport admission alone supplies no extension permission.
