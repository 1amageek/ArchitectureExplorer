# ArchitectureFrontend.Project

## Purpose and Scope
Own project within [ArchitectureFrontend](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Pure source providers; parse immutable bytes, never write stores. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Project -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

Read-only SwiftPM analysis recognizes literal target declarations and local dependencies directly in a top-level `Package` initializer. Default file ownership requires a Swift file in that manifest's conventional `Sources/<target>` or `Tests/<target>` tree. Custom source selection and dynamic declarations leave the affected structure unresolved. Results carry syntax evidence and partial coverage. Explicit trusted metadata supersedes this producer for the manifests it resolves.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## On-demand repository architecture

Repository selection projects declared deployment services and their startup, network and storage relationships from Compose. Package exports and production dependencies describe the package surface when deployment evidence is unavailable. The repository overview does not establish system context or runtime calls. A service can be linked to one working-tree TypeScript entry point when its local Docker build stage, literal Node entrypoint, and compiler source/output roots agree. Selecting that service parses only the selected source. Entry and imported binding nodes identify the language of the selected source site. Lexical construction and static member-call sites referencing imported bindings retain the source expression. Unsupported or ambiguous inputs yield explicit limitations. The projection never runs project code or recursively scans sources.
