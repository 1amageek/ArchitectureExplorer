# ArchitectureGraph

## Purpose and Scope
Bounded immutable projections, graph traversal, diff and export.
Parent: [system](../../DESIGN.md). Native SwiftPM module root.
- [Query](Query/DESIGN.md)
- [Export](Export/DESIGN.md)

## Responsibilities and Boundaries
Own only the responsibility above. Source code is read-only. Facts are scoped by producer and input generation.

## Related Designs
| Design | Relationship | Contract Used | Cautions |
|---|---|---|---|
| [System](../../DESIGN.md) | parent | Composition | Preserve formal independence |
| [ ArchitectureIR ](../ArchitectureIR/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |

## Architecture
```text
Caller -> ArchitectureGraph public contract -> Query, Export
```

## Contracts and Invariants
A source-only Swift model can cover individual arithmetic sites and branches inside a declaration. Canvas shows the partial scope and local check results on the selected model, independently of the whole-node verification verdict.

- Transfer values are immutable and Sendable.
- Unsupported information is explicit, never an empty success.
- Identity keys own lexical path, owner, kind and normalized signature; source revisions own exact bytes.
- All facts retain evidence and immutable snapshot identity.

## Verification and Change Impact
Behavior owner: [ArchitectureTests](../../Tests/ArchitectureTests). Test successful behavior, malformed inputs, budgets and the concrete consumer path. Recheck direct dependents when a public contract changes.

## Shared Canvas Assets
Canonical browser assets live in Resources and are mirrored into the Web package by Tools/sync-assets.py. Export embeds the same renderer. Generic imported document projections are separate from source queries; their validated model and session owner are [ArchitectureCanvas](../ArchitectureCanvas/DESIGN.md). [Web Page](../../Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Page/DESIGN.md) owns actual rendering and gesture behavior.
