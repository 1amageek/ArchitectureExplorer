# architecture

## Purpose and Scope
Argument validation and lifecycle composition; no analysis duplication.
Parent: [system](../../DESIGN.md). Native SwiftPM module root.
- [Commands](Commands/DESIGN.md)

## Responsibilities and Boundaries
Own only the responsibility above. Source code is read-only. Facts are scoped by producer and input generation.

## Related Designs
| Design | Relationship | Contract Used | Cautions |
|---|---|---|---|
| [System](../../DESIGN.md) | parent | Composition | Preserve formal independence |
| [ ArchitectureService ](../ArchitectureService/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |
| [ ArchitectureClient ](../ArchitectureClient/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |
| [ ArchitectureMCP ](../ArchitectureMCP/DESIGN.md) | depends on | Public Sendable values or protocol | Dependency change requires behavioral regression |

## Architecture
```text
Caller -> architecture public contract -> Commands
```

## Contracts and Invariants
- Transfer values are immutable and Sendable.
- Unsupported information is explicit, never an empty success.
- Identity keys own lexical path, owner, kind and normalized signature; source revisions own exact bytes.
- All facts retain evidence and immutable snapshot identity.

## Verification and Change Impact
Behavior owner: [ArchitectureTests](../../Tests/ArchitectureTests). Test successful behavior, malformed inputs, budgets and the concrete consumer path. Recheck direct dependents when a public contract changes.
