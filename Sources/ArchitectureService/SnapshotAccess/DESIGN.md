# ArchitectureService.SnapshotAccess

## Purpose and Scope
Own pinned raw-record paging and expiring immutable original-input leases. Parent: [Service](../DESIGN.md). No children.

## Responsibilities and Boundaries
Expose generic snapshot/input acquisition, not verification. Never execute workspace manifests, infer formal semantics or provide a second index. The Service request dispatcher obtains an existing snapshot; this component owns its raw paging and exact captured bytes.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Service](../DESIGN.md) | parent | Snapshot selection and shutdown | Composition | Current and pinned inputs remain distinct |
| [IR snapshots](../../ArchitectureIR/Snapshots/DESIGN.md) | depends on | Lease/page/chunk immutable DTOs | Public wire data | Cursor is pinned to snapshot and collection |
| [Client](../../ArchitectureClient/Connection/DESIGN.md) | used by | Typed snapshot reads | Same-user IPC | Preview is not a complete input |

## Architecture
```text
Existing immutable Snapshot -> bounded raw pages (independent entity/fact/evidence/coverage/input collections)
    -> exact source capture -> lease-held bytes -> bounded read chunks -> release/expiry
```

## Contracts and Invariants
Raw facts are never restricted to endpoints on the same page and never aggregated. Stable snapshot storage order and offset cursors retain snapshot/collection identity. Page records and bytes are bounded; an oversized record fails explicitly. Expired snapshot/lease/cursor fails rather than switching generations. A lease returns only a small descriptor; file manifests are themselves paged.

Capture validates every recorded non-metadata input's exact SHA-256 and bytes through root-relative descriptor traversal with O_NOFOLLOW. Oversize/unavailable input fails the complete capture. Metadata and context remain pinned to the snapshot. Source files are read-only, bounded to 5 MiB each/10,000 files; content reservations total at most 256 MiB across four leases/captures. This content quota is separate from preexisting graph/cache/process memory. Requests select a positive per-capture content budget, default 64 MiB/max 256 MiB. TTL is 1..300 seconds/default 60, measured monotonically. Renewal keeps the same captured bytes and is capped at 900 seconds from original admission. Service authorization binds Provider leases to the creating session. Immutable leases survive disk edits but not daemon restart. Chunk reads are at most 256 KiB; pages at most 500 records/2 MiB. No complete source bodies are included in normal display views or exports.

## State, Ownership, and Lifecycle
An actor owns leases, capture task handles, quotas and stop state. Capture I/O runs in an owned cancellable task, checking cancellation between bounded reads/files. Reservations are acquired before suspension and reconciled after capture; actor reentry cannot publish after shutdown or oversubscribe. Captured Data values stay immutable. Explicit release, expiry and shutdown release retained bytes; shutdown cancels/awaits active capture tasks. Descriptor chains and file handles close exactly once within each read scope.

## Failure, Concurrency, and Constraints
Path/byte/digest/limit/expiry/schema failures remain typed. Read chunks never read live disk. No observer shutdown stops another component's source daemon. Missing historical bytes are unavailable, not inferred from a preview. Lease expiry is enforced on every access; expired entries are pruned on requests and bounded by the same global quota when idle.

## Verification and Change Impact
SnapshotAccessTests exercise cross-page fact completeness, >16 KiB original reads, edits after lease, altered input rejection, traversal/symlink refusal, cursor mismatch, release/expiry, quota and shutdown. Real Client/daemon integration must execute these routes before consumer completion. Recheck Snapshot/Client/Requests designs when wire fields or limits change.

A host-requested property context uses one bounded input lease and a pinned graph. The selected declaration (or declarations structurally contained by a scope), file-level outgoing closure, immediate reverse references and their tests determine its source files. Confirmed snapshot facts and lexical identifier candidates retain distinct provenance. Include dependencies needed by the included callers/tests, applicable design documents and snapshot diagnostics. The payload contains complete UTF-8 files, paths and digests. Rejected limits, a stale anchor or a pre-document-index snapshot produce an error before dispatch.
