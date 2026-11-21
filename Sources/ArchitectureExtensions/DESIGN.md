# ArchitectureExtensions

## Purpose and Scope
Own the immutable public Extension API 1.0 / `aex-1.3` module. Parent: [system/package](../../DESIGN.md). Child: [Contracts](Contracts/DESIGN.md).

## Responsibilities and Boundaries
Provide language-neutral Codable transfer types and bounded validation. Depend only on ArchitectureCore and ArchitectureIR. This module owns no sessions, persistence, transport, process execution or UI state.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Contracts](Contracts/DESIGN.md) | child | Immutable models and validation | Public API | Keep schema and SDK consistent |
| [Service extensions](../ArchitectureService/Extensions/DESIGN.md) | used by | Validated transfer values | Runtime authority | Models never confer permission |
| [Client extensions](../ArchitectureClient/ExtensionProvider/DESIGN.md) | used by | Session, input, publication and action values | Provider SDK | Receipt differs from job state |

## Architecture
```text
ArchitectureCore + ArchitectureIR -> Contracts -> Service / Client
```

## Contracts and Invariants
Contract meaning belongs to the [extension specification](../../Documentation/EXTENSIONS-SPEC.md); wire shape and bounds belong to [Contracts](Contracts/DESIGN.md). External reported values never modify core truth.

## Verification and Change Impact
[ExtensionTests](../../Tests/ArchitectureTests/ExtensionTests.swift) and [native integration](../../Tools/extension-integration.py) exercise consumers. A wire change requires synchronized Schemas, Client, Service, Web and API reference updates.
