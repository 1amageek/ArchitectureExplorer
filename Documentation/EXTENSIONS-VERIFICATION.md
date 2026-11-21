# Extension API verification — 2026-11-17

The implemented development contract is [aex-1.3](EXTENSIONS-SPEC.md), refined by the user instruction to remove compatibility implementations. The root library supports macOS 27 and Swift 6.4.1. This record covers the actual paths below, not the uncompleted base-SPEC performance/backends matrix.

## Implemented flow

```text
Separately launched Provider -> kernel peer -> user-approved session/permissions
    -> exact input capture + run admission -> staged contribution manifest
    -> atomic Store head -> paged queries / declarative Web / saved HTML
Host confirmation -> durable dispatch -> Provider receipt ledger -> Provider-owned work
    -> monotonically revised job reports / cancellation cleanup
```

## Recorded checks

| Owner / command | Result | Actual execution scope |
|---|---|---|
| `Tools/run.py 180 swift test -Xswiftc -DARCHITECTURE_PAIRED_WEB` | 64 tests, 9 suites passed | Native success/failure, permissions, peer/session binding, atomic publication, fingerprint/receipt recovery, cancellation, paging, corrupt state, concurrent first reads, inherited-descriptor lock release, disconnect/cancel recovery, event origin, cache-format rejection, existing parser/IR/index/LSP regressions |
| `Tools/run.py 180 python3 Tools/extension-integration.py` | 12 checks passed | Real separately built SDK Provider and daemon, OS peer PID/hash, authenticated HTTP/CSRF, 50 idle non-host sockets, verified source bytes, four-kind publication, current-only storage/queries, duplicate confirmation, cancellation cleanup, input changes and actual Invar adapter |
| `Tools/run.py 150 python3 Tools/integration.py` | 12 checks passed | Actual CLI, shared daemon, source edits, historical snapshots, MCP, exports and restart |
| `Tools/run.py 150 python3 Tools/review-regressions.py` | 9 checks passed | Actual CFG/import/deletion/backpressure/shutdown paths; unregistered raw IPC denied and paired authenticated reads accepted |
| `Tools/run.py 150 python3 Tools/web-integration.py` | 19 checks passed | Real HTTP/WS sessions, one-use tokens, Host/Origin, shared asset paths, independent helpers, actual Swift/Rust callable fixtures and stream cleanup |
| `Tools/run.py 120 node --test Tools/node-cards.test.cjs Tools/layout.test.cjs` | 56 passed, 1 environment-gated E2E skipped | Pinned Cytoscape/ELK geometry, navigation, role/metadata display, gestures, theme/state preservation; the separate native Web suite owns the actual HTTP callable E2E |
| `Tools/build.py` | Passed | Independent root and Web builds; exact paired helper identity |
| `Tools/package.py --configuration release` | Passed | Local unsigned portable bundle at `Dist/ArchitectureExplorer` |
| Portable bundle smoke | Passed | Packaged CLI indexing, actual paired Web authentication/query, bundled resources, owned helper/daemon cleanup |
| Build-pair contention probe | Passed | A second build wrapper fails promptly before compiling a mismatched helper pin |
| Browser check | Passed | Real approval, literal report/graph/table/timeline, exact execution review/confirmation, offline disabled controls, current self-project module view |

## Acceptance ownership

| Requirement | Evidence |
|---|---|
| AEX-001–003 | Root package dependency direction, separate example packages, manifest/API rejection test and real Provider registration |
| AEX-004–005 | Peer/permission and namespace tests, current-route rejection, session credential binding, actual kernel peer integration |
| AEX-006–007 | Host admission under 50 external sockets, Provider disconnect/revocation with live graph reads, literal HTML-looking data in browser |
| AEX-008–010 | Immutable receipt, altered fingerprint rejection, changed-input confirmation refusal, cancel receipt vs terminal cleanup in unit/native paths |
| AEX-011 | Existing read-only MCP allowlist and actual MCP regressions; no new dispatch/approval tool |
| AEX-012–013 | SnapshotAccess original bytes/expiry/symlink/budget tests, SDK file/manifest digest checks, conservative unknown dependency status |
| AEX-014–016 | Staging/partial commit rejection, one publication head, current read projection, exact source identities, stale/unmatched applicability |
| AEX-017–018 | Input-origin regression through the actual Service path, explicit resync, bounded pages/rate/write admission, reserved host connections |
| AEX-019–020 | Actual browser saved-HTML disabled actions and four-kind live publication under the same run/publication/input binding |
| AEX-021–022 | Resource/rate/page tests, expired/old-session token/lease/staging denial, reconnect generation preservation and re-staging |
| AEX-023–024 | Separate reported status/applicability/scope/assumptions/translation rendering; external attributes never become core or temporal facts |
| AEX-025–026 | Confirmation requirement despite false manifest preference; forged/expired/session-bound token tests; removed API/profile/alias rejection and absence of old tables/adapters |
| AEX-027–028 | Per-file exact bytes and independent manifest digest, atomic complete/empty heads, later failed attempts, old-generation refusal |
| AEX-029–030 | Monotonic terminal reports, cancellation/completion race, disconnected unknown state, host restart without redelivery, durable Provider duplicate/conflict/restart/lost-ledger lookup |

The final parallel run reproduced a retained ledger lock after shutdown. A deterministic `dup` regression then failed against the original close-only implementation and passed after explicit `LOCK_UN` before close. The full 64-test run and rebuilt native Provider integration passed with the fix.

## Refactoring result

Only `aex-1.3` is registered. Compatibility profiles, legacy slots, per-record write routes, snapshot lease aliases and additive cache migration have been removed. The former IR Annotation and separate Annotation/extension graph tables were deleted. `ExtensionAnnotation` carries report data; contribution envelopes own identity, Provider, source binding and publication. Current reads project committed run data from the single `extension_state` document.

Development cache format 2.0 rejects previous formats before changing their schema. The self-project's previous derived cache was archived outside the source tree and rebuilt explicitly; no migration path was added. Original source files were not rewritten by indexing. The attached extension specification and repository copy were updated together.

## Evidence limits

Invar integration executes its real `ExplorerSnapshotReader` through an approved session. It does not claim that Invar verification backends or all their semantic results have been validated. The host forwards actions and never launches verification processes. Local peer/permission checks are not an execution sandbox; that remains the external tool's responsibility.

The self-project view contains the new ArchitectureExtensions module and 30 coarse entities/65 relations. Self-analysis remains `unknown / partial`: eight files produce explicit parser diagnostics, including the six previously recorded paths and the new ExtensionEndpoints/ProviderActionLedger files. Swift compilation and behavioral execution passed; parser coverage is not represented as complete. Full adversarial load, power-loss, base-SPEC large-workload and unavailable Rust semantic-provider gates remain as tracked in PROGRESS.md.

Browser artifacts are written to the ignored test-artifacts directory. Integration tests stop their temporary workspace processes after the run.

## Post-merge self-project refresh

The feature commit was fast-forwarded to main without source conflicts. A subsequent `architecture index --trusted-workspace` against the self-project was rejected with `INVALID_GRAPH: Duplicate identities`. The last valid coarse graph remains visible as stale. This is an observed unresolved indexing/metadata refresh failure; the current self-project view is not claimed to be freshly reconciled. It does not change the recorded extension fixture results. The cause has not been localized, so no source fix or stronger conclusion is claimed here.
