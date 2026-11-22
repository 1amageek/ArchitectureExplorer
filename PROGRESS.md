# Implementation progress

The full v1 acceptance contract is Documentation/SPEC.md sections 24–25. Unverified functionality remains open; build success alone is not acceptance.

| Phase | Status |
|---|---|
| P0 dependency probes and package isolation | Verified native Swift 6.4.1 builds; root has no Web/formal dependency; deployment floor macOS 27 |
| P1 IR/store/queries | Behavioral coverage for validation, atomic publication, identity, budgets, cursors and exports |
| P2 live indexing/daemon | Actual concurrent parsing, shared daemon, asynchronous jobs, responsive status, edits/deletion/stale/restart tested |
| P3 authenticated Web GUI | Native HTTP/WS authentication, real Cytoscape/ELK, canvas gestures and navigation exercised; complete UI acceptance matrix remains open |
| P4 semantic providers/CFG | Actual SourceKit-LSP probe; Swift/Rust supported CFG paths/refusals tested; actual rust-analyzer integration remains untested |
| P5 MCP/export/annotations | Real MCP stdio, four export formats and current atomic contribution UI tested; dependency applicability stays explicitly unknown when evidence is incomplete |
| P6 integration/performance/distribution | 64 behavioral tests, 12 CLI/daemon/MCP checks, 9 review regression checks, 19 native Web checks; local unsigned bundle assembled; performance gates below remain open |

## Review corrections

All eight reproduced review issues are corrected and mapped to actual regression evidence in [ADR 0007](Documentation/ADR/0007-review-corrections.md) and [verification](Documentation/VERIFICATION.md). Coverage includes explicit obsolete-cache rejection, unchanged-input upgrade reconciliation, obsolete CFG rejection, imported-generation isolation, non-reading/closed-input child processes, cancellation, forced termination and simultaneous loopback sessions. LSP lifecycle tests passed three bounded runs without stale helpers. These results do not close unrelated v1 gates below.

## Implemented timeout and interaction changes

```text
Client -> shared index job ID -> short progress/result polls
                    |
              up to 4 file parsers -> atomic publication

Trackpad scroll -> canvas pan
Pinch / modifier-wheel -> zoom around pointer
Layout requests -> one running + latest pending request
```

`workspace.status` remains available during indexing. Abandoned client sockets cannot terminate the shared daemon. The parser parallelism test instruments simultaneous real provider calls; it does not infer concurrency from declarations.

## Open v1 acceptance gates

| Gate | Remaining work / current evidence boundary |
|---|---|
| AE-018 / configuration | Default workspace configuration and context invalidation work; alternate invocation-level `--config` and every analysis/view control are not implemented |
| AE-022 | Atomic rollback is tested; process-kill/crash fault-injection matrix is not run |
| AE-035–041 | Bounded GUI, latest-generation layout, resync and accessible list exist; full large-load, keyboard, focus, reconnect/backpressure matrix is not complete |
| AE-043 | Python real MCP client passed; named external MCP client compatibility matrix is not run |
| AE-049–051 | Current atomic report/graph browsing is verified; complete dependency applicability and all external semantic-backend fixtures are not established |
| AE-057 | Source/capture/message/layout sizes are bounded; the synchronous upstream skeleton parser cannot be forcibly cancelled and has an explicit source marker; adversarial deadline coverage is not complete |
| AE-058 | Medium workload measured honestly in performance-results.json; saved-file p95 target, 10k files, Large 100k-node/500k-edge, GUI frame rate and commit-to-GUI latency gates have not all passed |
| P4 | rust-analyzer executable component is unavailable on the host; no successful Rust semantic-provider result is claimed |

This is a developing 0.1 implementation. These open gates prevent a claim that the complete SPEC v1 acceptance contract has passed. Signing and notarization are outside the verified scope.

## Extension API aex-1.3

| Phase | Status |
|---|---|
| E0 contracts/peer authorization | Implemented; current-only profile, kernel peer/session/permission and rejection tests pass |
| E1 queries/events/input leases | Implemented; exact source copying, lease ownership/expiry, origin/resync and current SDK paths verified |
| E2 atomic publications/declarative GUI | Implemented; one transaction/head, paged current reads, report/graph/table/timeline and saved HTML checked |
| E3 actions/receipts/cancellation | Implemented; confirmation, no uncertain redelivery, durable Provider lookup, monotonic job/cancel terminal behavior verified |
| E4 external integration | Real SDK Provider and actual Invar input adapter verified; verifier backend semantics remain external ownership |

The development refactor removes compatibility profiles/adapters, old mutation routes, lease aliases, separate Annotation/graph stores and additive cache migration. Current cache format is 2.0; older formats are explicitly rejected. The former IR Annotation is replaced by the current ExtensionAnnotation report contract.

[Extension verification](Documentation/EXTENSIONS-VERIFICATION.md) records 64 Swift tests, 12 native extension checks, 12 CLI checks, 9 review regressions, 19 native Web checks, 56 renderer/layout passes and the portable release smoke. The self-project was reindexed and shows ArchitectureExtensions; its eight explicit parser diagnostics keep self-analysis partial. This does not close the unrelated base-SPEC gates above.

Post-merge observation: a trusted self-project metadata refresh returns `INVALID_GRAPH: Duplicate identities`; the previous valid view remains stale. This unresolved failure is recorded in the extension verification and is not counted as a passed self-refresh check.

## Shared multi-format Canvas
- [x] Native validated Canvas model and eight offline import profiles.
- [x] Shared revisioned sessions through Service, HTTP, CLI and MCP.
- [x] Seven diagram layouts, common Canvas interactions, external graph integration and SVG display/export.
- [x] Real file fixtures, parser failure/bounds, native/MCP/browser E2E, regression build and coherent commits.

[Canvas verification](Documentation/CANVAS-VERIFICATION.md) records 22 real import fixtures, 74 Swift tests, 78 renderer/controller passes and native/browser integration. Supported syntax profiles and resource limits are explicit; this does not close unrelated base-SPEC acceptance gates.

## C4 System Context

Explorer owns the specification, snapshot projection and live Home route. The first implemented input profile is the workspace Backstage catalog (System, Component and API). Typed MCP client/endpoint, IaC and trace adapters, person attribution, and automatic association of Context relationships with provider verification records remain open acceptance items. No workspace-specific Context manifest is required.

## Workspace sequences

- [x] Capture root Structurizr dynamic views with their Map participants and cited source on the same snapshot.
- [x] Navigate from Workspace or a Map participant, open the sequence before awaiting its data, and inspect messages and replies.
- [x] Verify historical reads, stale and missing citations, invalid model replacement, and invalid imported identities in WorkspaceSequenceTests.

## Destination-first verification navigation

The Map options menu now prepares and executes the Invar verify-project action for a system/container. It enters the destination before availability/input reads and shows the new action's complete three-phase report after publication. Existing reports remain accessible through the context menu. [Project action evidence](Documentation/CANVAS-VERIFICATION.md#executable-project-verification) records the actual Formal run and regression scope.

- [x] Shared destination/loading/failure lifecycle for source, repository, Canvas, report and published-model navigation.
- [x] Node-options verification, clickable result marks and Map context-menu report/chooser without an Inspector prerequisite; pending navigation never implies verification success.
- [x] Bounded navigation model with a stale-reply control, delayed-read production regressions, authenticated host integration and built-in browser checks.

[Verification evidence](Documentation/CANVAS-VERIFICATION.md#destination-first-navigation) records the scope and limits. This does not complete unrelated base-SPEC acceptance items or certify Formal's unverified production code.
