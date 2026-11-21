# architecture.Commands

## Purpose and Scope
Own commands within [architecture](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Consume public dependency contracts. Do not infer semantic truth from names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Argument validation and lifecycle composition; no analysis duplication. | Module composition | Recheck parent on contract changes |

## Architecture
```text
Module composition -> Commands -> immutable result or typed error
```

## Contracts and Invariants
Inputs and outputs retain workspace, snapshot and provenance. Failures remain distinguishable from absence.

## State, Ownership, and Lifecycle
Mutable database and indexing state is actor-isolated. Socket descriptors are single-owner scoped resources with exactly-once close. Trees and source bytes remain local to a parse; pointers never escape the parse scope. No state branches by target.

## Failure, Concurrency, and Constraints
Requests and sources have explicit byte limits and deadlines. Cancellation closes owned descriptors and tasks. External callbacks and I/O run outside mutex critical sections.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests) own invariant checks; module tests cover composition. Public contract changes require parent review.

## Imported Canvas Commands
`architecture canvas` forwards explicit name/text or presentation parameters through the Client. File input is checked for the import byte budget and strict UTF-8 before sending. JSON/SVG exports use the existing overwrite-protected writer. Session IDs are presentation identities, not authentication credentials. See [Canvas contracts](../../ArchitectureCanvas/DESIGN.md) and [import profiles](../../../Documentation/CANVAS-FORMATS.md).
