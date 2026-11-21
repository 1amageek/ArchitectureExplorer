# Shared Canvas verification

Verified locally on 2026-11-18 with the fixed macOS 27 / Swift 6.4.1 host build. [Canvas design](../Sources/ArchitectureCanvas/DESIGN.md) owns responsibility boundaries; [format profiles](CANVAS-FORMATS.md) own supported syntax and limits.

## Requirement coverage

| Requirement | Implementation path | Behavioral evidence |
|---|---|---|
| Eight input formats | CanvasFileReader -> format reader -> CanvasDocument validation | 22 real fixtures through Swift readers and authenticated native HTTP; all eight formats roundtrip through normalized JSON |
| Seven diagram kinds | CanvasModel projection -> shared LayoutModel -> pinned ELK or ordered sequence layout -> existing Cytoscape | Seven-kind tests and all real parsed fixtures on the production engine; hierarchy, relations, CFG, data flow, states, sequences and proof dependencies |
| Shared imported/external sessions | Service authorization -> CanvasSessions actor -> HTTP/CLI/MCP -> browser reconciliation | MCP/HTTP selection, revision conflict, focus, filter, layout, camera, collapse/expand and paging tests; actual browser follows MCP selection/focus |
| Preserve source presentation | Original source cards and imported ArchitectureIR projection | Swift/Rust real-source renderer integration; fixed 264-wide child cards and original 640×32 property-row regressions |
| Atomic failure | Parse/validate/admit candidate before replacing actor state | Invalid replacement preserves complete old session; stale CAS has exactly one winner; invalid filters/camera/geometry do not advance revision |
| Bounded ownership | Per-read parser state and per-daemon session actor | 32 open files, explicit overflow without eviction, close/shutdown, reserved host identities, XML entities/resources and malformed/unsupported syntax |
| Static SVG and vector export | Sanitized isolated SVG image; acknowledged geometry -> SVG export | Mixed text order, safe roundtrip, static-image selection/geometry, collapsed external connections, actual sequence SVG download |
| External authority | Separate Canvas read/control permissions | Read-only and control-only grants cannot mutate; combined grant can; permission revocation invalidates access; existing extension integration remains valid |

## Executed checks

All commands run under explicit process-group deadlines.

| Check | Result |
|---|---|
| Full `swift test` | 74 test functions passed in 10 suites, including the 22-file parameterized import test |
| Focused permission checks after tightening mutation admission | Passed; both read and control are required for mutation acknowledgments |
| Node layout/card/Canvas/controller suite | 80 tests: 78 passed; two real-source/import fixture gates run separately by native integration |
| Canvas native HTTP/MCP/production-engine integration | 7 checks passed; 22 files, eight formats, seven kinds |
| Existing CLI/daemon/MCP integration | 12 checks passed |
| Existing authenticated Web/WS and actual Swift/Rust renderer integration | 19 checks passed |
| Existing external Provider/SDK/Invar integration | 12 checks passed |
| Paired CLI/Web build and vendor asset synchronization | Passed |

The actual browser opened nine files covering all eight formats in one file chooser. Checks covered static SVG, sequence lanes/messages/loop frame, state transitions including a visible self-loop, node selection/Inspector, 100% -> 120% zoom acknowledged by the daemon, MCP selection/focus reflected on screen, browser Back, filter/grid/automatic layout, failed import preserving the current view and downloaded SVG content.

Browser verification exposed and fixed host-only image/sequence identity rejection, low-contrast message labels, fragment positioning after dimension updates, stale Inspector content on session switches, disabled Back after opening sessions and self-loops hidden behind large cards. Focused regression tests cover these paths. The standalone Node tests use a DOM/font host double; screenshots and native browser operation cover the actual rendering path.

## Evidence boundaries

This verifies the documented syntax profiles, not the entirety of Mermaid, PlantUML, GraphML, SCXML or UML/XMI. Graphs are bounded; large-load performance is not established by small fixtures. SVG export reproduces acknowledged boxes and logical connections, not pixel-identical browser routes or source-card artwork. Imported/external session state is shared; existing live source navigation remains browser-owned. Sessions expire on daemon restart. TLC execution, Lean extraction and verification semantics remain external.

Existing self-analysis remains stale/partial with explicit parser diagnostics; source compilation and successful Canvas import do not prove the Explorer can fully parse its own repository. The previously recorded self-refresh limitation and unrelated base-SPEC acceptance gates remain open.

## Destination-first navigation

The Page [navigation contract](../Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Page/SPEC.md) covers source hierarchies, repository scopes, imported sessions/files, Map verification reports and published formal graphs. Each foreground destination is committed and painted before its reads begin. Source nodes expose Verify model in their header options menu, without an Inspector prerequisite. Loading and failure clear the old drawing and badges; Retry retains history, and Back/Home or a newer destination detach late replies. Index invalidation cannot replace an imported destination while its session is loading. Reading a result or retrying availability never confirms external execution.

The [bounded navigation model](../Verification/Navigation/RESULT.md) checks three invariants over 106 states, with a stale-reply negative control. Production page/controller regressions deliberately hold paint, RPC replies, source resolution and file reads. They exercise failure/retry, exact report binding, Back/Home, index invalidation, late success/failure and publication confirmation. JavaScript/browser correctness is supported by those behavioral tests and real browser checks, not inferred from the state model.

The 2026-11-21 regression run passes 123 JavaScript tests (two optional external-fixture cases skipped) and 22 real authenticated HTTP/WebSocket checks. The paired native build uses Tools/build.py. In the built-in browser, Map report and source hierarchy clicks show their destination Loading state before results. The Formal report remains incomplete at 0/41 overall, Specification 3/41, Code 0/41 and Correspondence 0/41. Selecting a source function exposes Verify model directly. A disconnected Invar produces an explicit unavailable reason and Retry rather than implying successful verification. This UI task does not create new Formal production-code proof evidence.

## Direct Canvas verification actions

The follow-up removes the Inspector prerequisite. Source nodes expose Verify model inside their existing header options menu; no separate Verify button is rendered. Bound result marks have a labeled native pointer/keyboard target over their existing artwork. Linked Map objects expose Open verification report in their context menu; multiple matches use a local chooser. These entry points reuse destination-first navigation and exact-snapshot evidence binding. They never require an Inspector interaction or implicitly confirm external execution. Map captions display labels only. Report availability leaves caption placement, object/area geometry and camera unchanged.

The final paired native build passed. The full JavaScript run passed 127 tests with two optional external-fixture skips; authenticated HTTP/WebSocket integration passed 22 checks. New behavioral cases cover direct header dispatch, result targets, Map click/keyboard access, stale report removal, chooser selection, caption geometry and clearing an imported-session URL when returning to source. The Map host-double test uses the actual controller, Three projection and layout; actual browser checks cover rendering.

In the built-in browser at the normal viewport, Inspector remained at No Selection while the swift-formal Map Report opened the existing incomplete report. A temporary copy of that same incomplete report exercised the two-report chooser and was closed afterward. The source function advance opened Verify model and Loading model immediately from its header, then displayed the explicit disconnected-Invar reason and Retry. Back returned to source; Home cleared the Canvas URL. No new Formal verification outcome is claimed.

The header placement correction retains Verify model only in the options menu and restores its former text space. The final 127-pass JavaScript run (two optional skips) verifies that source headers contain only their options control unless a bound result mark exists, and that choosing Verify model closes the menu and commits its destination. Existing extension-controller tests still cover delayed model availability and confirmation. The paired native build and actual browser menu/navigation check passed. No new verification result was produced.

The Map placement correction removes the standalone Report control, its SVG/CSS implementation and the layout space reserved for it. The object and caption context menu retains Open verification report, including Shift+F10 access and the local multi-report chooser. Browser checks confirmed no standalone report button, right-click caption and keyboard access, immediate report Loading, the existing incomplete outcome and Back. Regression tests cover actual Map menu callbacks without caption controls and the Page menu-to-report/chooser path. The paired native build and 126 JavaScript tests passed, with two optional external-fixture skips. This presentation correction does not execute verification or change the report outcome.

## Executable project verification

Verified on 2026-11-21 with the built native Web helper and Invar daemon against Formal. The Map software-system options menu exposes Verify project. The destination paints before availability reads; Run verification submits the original snapshot/subject-bound action. The controller follows that exact request/run and opens the full project-report graph after publication. Back does not resubmit work; the same Map options menu reopens published reports through Open verification report. No permanent Report/Verify controls were added to Map.

The actual report displays Project verification incomplete, 0 of 41 requirements verified; Specification 3/41, Code 0/41, Correspondence 0/41. Selecting A12 shows the independent specification evidence and explicit unsupported implementation/unvalidated correspondence limits. The report has 49 nodes and 56 displayed relations, including parent containment. Filtered views preserve the full-inventory verdict. This verifies rendering and workflow, not Formal source semantics.

Validation: 128 controller/renderer tests passed, 2 optional dependency checks skipped; native host integration passed 22 checks; the paired native products built successfully. The real Agent MCP path also completed and committed its report to the same subject. Invar's Verification/ProjectAction-RESULT.md owns execution receipts, identifiers and backend limitations.
