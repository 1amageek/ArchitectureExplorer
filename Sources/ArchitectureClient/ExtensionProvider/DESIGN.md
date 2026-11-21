# ArchitectureClient.ExtensionProvider

## Purpose and Scope
Own the typed external Provider client and durable acceptance ledger. Parent: [Client](../DESIGN.md). No children.

## Responsibilities and Boundaries
Consume the [immutable contracts](../../ArchitectureExtensions/Contracts/DESIGN.md) over authenticated IPC. The caller launches/owns its Provider and work; this SDK never launches a verifier or automatically retries an uncertain operation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Client](../DESIGN.md) | parent | IPC composition | Request lifetime | Every call closes its socket |
| [Connection](../Connection/DESIGN.md) | depends on | ArchitectureClient and snapshot reads | Session-bound IPC | New session cannot use old leases |
| [Service extensions](../../ArchitectureService/Extensions/DESIGN.md) | depends on | Registry, run publication, actions | Remote authority | Explicit approval/permissions required |

## Architecture
```text
Provider -> register/resume -> session client -> fixed inputs / run publication
         -> received action -> durable ledger reservation -> caller-owned work
```

## Contracts and Invariants
`ArchitectureExtensionProviding` is the public typed interface; `ExtensionProviderClient` supplies the IPC implementation. Registration returns a new immutable session client. Inputs are copied from a lease and every file's SHA-256 is checked independently from the InputManifest digest. Failure releases the lease or reports both the original and cleanup failures. Partial data never returns as a complete capture.

`ProviderActionLedger.reserve` persists an accepted receipt before returning `mayStart=true`. Only that result permits the caller to start work. A duplicate returns the identical receipt with `mayStart=false`; altered fingerprints fail. A ledger created after request admission reports `ACTION_OUTCOME_UNKNOWN`; initial deadline and retention expiry are checked independently of entry lookup. Restart never implies work may be restarted. Reconciliation uses `lookup`, which requires an existing durable receipt and cannot admit a new request.

## State, Ownership, and Lifecycle
The client value owns no mutable shared state. The ledger actor owns a process-locked bounded file, in-memory candidate state and its lock descriptor. Atomic file replacement completes before state assignment. Explicit shutdown unlocks the shared open-file description before closing, so descriptors inherited across fork/dup cannot retain a stopped owner's lock; deinit is a synchronous descriptor backstop and performs no asynchronous shutdown.

## Failure, Concurrency, and Constraints
Ledger admission retains at most 512 entries/1 MiB, never evicts an entry before its host-fixed deadline plus 3600 seconds, and rejects new work when full. Concurrent processes cannot own one ledger. Resource limits and busy responses remain typed for the caller's backpressure policy. Native macOS only; no target-specific isolation branch.

## Verification and Change Impact
[ExtensionTests](../../../Tests/ArchitectureTests/ExtensionTests.swift) tests first acceptance, lost ACK, duplicate/conflicting requests, expiry, restart and lost ledger. [Mock Provider](../../../Examples/ExtensionMock) exercises the actual SDK and daemon through [native integration](../../../Tools/extension-integration.py). Recheck the Service/Contracts/Connection when changing identity, capture or ledger behavior.
