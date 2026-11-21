# ArchitectureService.Extensions

## Purpose and Scope
Own peer/session-bound registration, grants, authorization, durable dispatch reservation and atomic contribution heads. Do not launch Provider processes.
Parent: [../DESIGN.md](../DESIGN.md). Children: None.

## Responsibilities and Boundaries
Use the [aex-1.3 specification](../../../Documentation/EXTENSIONS-SPEC.md) as the behavioral requirement. Core facts and indexing remain separate from external records.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Service](../DESIGN.md) | parent | Request dispatch and shutdown | Runtime composition | Core queries bypass external-state failures |
| [Contracts](../../ArchitectureExtensions/Contracts/DESIGN.md) | depends on | Immutable validated DTOs | Wire authority | Values do not confer permission |
| [Store](../../ArchitectureStore/Persistence/DESIGN.md) | depends on | Atomic extensionState replacement | Durable owner | Do not mix external data into core tables |
| [Transport](../../ArchitectureCore/Transport/DESIGN.md) | depends on | Kernel peer identity | Authentication | No request-supplied identity fallback |
| [Client](../../ArchitectureClient/ExtensionProvider/DESIGN.md) | used by | Provider SDK | External consumer | Provider owns work and acceptance ledger |

## Architecture
```text
OS peer -> approved principal/session -> permission + binding checks
    -> durable dispatch / run transaction -> immutable result -> Client / Web
```

## Contracts and Invariants
Identity comes from the accepted OS peer and host-issued session, never request Provider strings. Host and Provider dispatch ledgers distinguish receipt from changing job state. Authorization consumption and dispatch reservation commit together before delivery. Unknown delivery is never replayed. Publication heads advance only on complete, newer generations; previous data and history survive failed attempts. Source and manifest digests have distinct domains.

## State, Ownership, and Lifecycle
The Service extension actor owns mutable sessions and a copy-on-write candidate state. A persistence gate rejects concurrent mutations before effects; reads observe only committed state. Store atomically persists bounded extension state separately from core graph facts. Sessions, tokens, staging and input leases have explicit owners and expiry; shutdown revokes them. Provider acceptance is persisted before work starts.

## Failure, Concurrency, and Constraints
Existing 4 MiB IPC limits remain. Extension host admission defaults to 16 registrations, 64 pending approvals/actions, 512 dispatch records and 16 MiB durable state. Contribution payloads are at most 1 MiB each, a publication 2 MiB and declarative views 64 KiB. Per-session rate admission is bounded independently of graph reads. Limits are host-owned correctness budgets; changes require boundary/fairness tests. No critical section calls external code.

## Verification and Change Impact
[Extension tests](../../../Tests/ArchitectureTests/ExtensionTests.swift) verifies permissions, fingerprints, expiry, restart, cancellation and monotonic atomic publication. Real native mock Provider/daemon/Web tests prove peer binding and user-facing state. Changes require parent, transport, Store and Web review.

### Runtime decisions
A grant supports only aex-1.3 and the whole selected workspace scope. Granular requested scopes are rejected rather than silently treated as enforced. Permission reduction invalidates sessions; expansion requires new approval. Grant replacement disables previous identities for that Provider. An approved live audit peer may collect its credential; a new process must supply the secret resume credential as well as the approved code/binary identity.

The Store owns atomic single-document replacement. The actor reserves the persistence gate before suspension and installs candidate state only after successful persistence; competing writes receive `RESOURCE_BUSY`. Nonterminal dispatches recover as `unknown` after restart. Unknown delivery is never put back in the delivery queue. Initial action receipt and monotonic job revision are independent. Cancel target identity is revalidated at confirmation, and completed/failed/cancelled states cannot be overwritten.

Runs declare contribution kinds and registered view IDs before work. Complete empty publications may advance a head; failed/partial/cancelled/unknown attempts retain the old head. Expired attempts cannot be reused. Run records are retained without eviction, up to 128; exhaustion fails explicitly. Dispatch retention is 512 records until host deadline plus 3600 seconds. Public envelopes are paginated at 3 MiB without splitting a publication, with revision-bound cursors; concurrent updates require resync.

Concurrent first readers await the same initialization gate; they do not surface a transient busy error as a permanent GUI diagnostic. Once initialized, reads use committed state while writes contend explicitly. Shutdown revokes admission and drains accepted persistence before returning.

Development policy: one canonical registration/publication contract. Removed API names and profiles are rejected; there are no adapters, per-kind write stores or legacy slots. Annotation and graph reads project only committed run contributions. Input leases use inputs.acquire/read/renew/release.

A terminal incomplete attempt may expose its manifest diagnostic to reads of the bound snapshot. Staging and complete heads remain independent of this attempt metadata.
