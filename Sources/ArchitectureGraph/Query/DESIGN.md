# ArchitectureGraph.Query

## Purpose and Scope
Own query within [ArchitectureGraph](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Bounded immutable projections, graph traversal, diff and export. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Query -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

Path adjacency follows the requested direction: outgoing uses source-to-target, incoming target-to-source, and both includes both orientations. Overview keeps structural contains/memberOf facts directly, and represents every other eligible fact exactly once through an aggregate with sourceEdgeIDs and count. Non-overview queries retain original facts. A direct visible semantic fact is not returned alongside its aggregate.

File outlines use the existing `level: file` selector. `graph.overview` starts from all files; `graph.children` starts at its focus and follows recorded lexical `contains` facts to `depth`. Project scopes are excluded as roots of child views; a focused file or declaration remains the containing frame. Default children queries at other levels keep their direct-child behavior. Call sites, basic blocks and unresolved/external symbols are excluded from outlines. Depth zero shows roots only (or no children for an excluded project scope).

File-mode semantic kind filters do not remove structural containment. Language filters select payloads; each page additionally includes their selected recorded ancestors, counted within the node budget. Cursor offsets advance through payloads rather than repeated context. A page that cannot fit one payload with its ancestors, or all structural edges for that page, fails with `RESOURCE_LIMIT` rather than showing orphaned declarations. Structural facts precede semantic facts under the edge budget. Traversal has the existing 20,000-node/200 ms work limit and reports explicit truncation. Facts and identities are never synthesized for lexical grouping.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

The context overview projects only recorded C4 subjects and direct context facts. It reports missing boundary evidence and never aggregates package dependencies into L1.

Type overviews and file outlines (overview and focused children) project a dashed candidate reference when a recorded syntax site has one matching type spelling in its source scope. Scope is the conventional SwiftPM Sources/<target> or Tests/<target> tree, otherwise the source file. The lookup includes declarations outside the visible page. Duplicate spellings, nested-only targets, stale evidence and self references do not create candidates. These edges retain their source and destination evidence, one representative UTF-8 site, and a separate kind from semantic dependencies. Projection reads the pinned snapshot only and respects the query edge budget.

C2 selects a pinned software system and its typed runtime children using the [C4 projection contract](../../../Documentation/C4-CONTEXT-SPEC.md). Every container page includes its owner within the declared node budget.
