# ArchitectureIndexer.Indexing

## Purpose and Scope
Own indexing within [ArchitectureIndexer](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Reconciliation, immutable inputs, stale retention and generation-gated publication. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Indexing -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

The provider cache revision includes the normalized declaration-role, property-metadata and callable-metadata version. A change to that version forces syntax reconciliation before newly published views can claim the new metadata; entity identity keys remain stable.

Reconciliation computes updated and deleted source paths separately. Deleted endpoint anchors invalidate facts from every producer, including CFG and semantic supplements. Evidence anchored in an updated/deleted path also invalidates its facts. A failed parse retains existing facts but marks evidence and entity-scoped coverage stale using the scope owner's source path. Facts without affected endpoints or evidence retain their producer ownership.

Saved-input captures include indexing and CFG algorithm revisions. An upgrade reconciles unchanged disk input too, removing legacy ghost entities and invalidating old CFGs rather than reusing previously incorrect cached results. Historical stored snapshots remain immutable. CFG cache reuse also requires the Frontend's hasSupportedGraph predicate and current scope coverage.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

Capture native catalog records with source digests; rederive their entities and facts on reconciliation under the [Context contract](../../../Documentation/C4-CONTEXT-SPEC.md).

Design documents are immutable inputs for property analysis. Capture README.md, DESIGN.md and Markdown in Documentation, docs and ADR directories under the configured selection; document edits change the snapshot without producing code declarations.

Accepted Verification/**/properties.json and their adjacent invar.json execution configurations contribute their byte digests to the source snapshot. Editing a property therefore invalidates the old snapshot binding.

Root Structurizr DSL takes precedence over native catalogs as specified in the [DSL input contract](../../../Documentation/C4-CONTEXT-SPEC.md#structurizr-dsl-input). A rejected replacement removes the previous DSL projection.
