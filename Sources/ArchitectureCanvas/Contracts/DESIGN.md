# ArchitectureCanvas.Contracts

## Purpose and Scope
Own the presentation document value types and reader/session protocols. Parent: [Canvas](../DESIGN.md). No children.

## Responsibilities and Boundaries
A CanvasDocument represents imported presentation data. Its local identities and provenance remain distinct from ArchitectureIR entities. These are validated value snapshots; mutability is owned by a session, not shared between readers.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Canvas](../DESIGN.md) | parent | Document/session composition | Module boundary | Recheck consumers after schema changes |
| [Core](../../ArchitectureCore/DESIGN.md) | depends on | JSONValue and ArchitectureError | Literal details and typed failures | No semantic source ownership |
| [Import](../Import/DESIGN.md) | used by | CanvasFileReading and document validation | Produces validated documents | Input profiles are owned by Import |
| [Sessions](../Sessions/DESIGN.md) | used by | CanvasSessionManaging | Owns acknowledged values | State does not mutate source facts |

## Architecture
```text
Reader -> CanvasDocument -> validate -> session-owned value snapshot
           Node / Edge / Lane / literal metadata
```

## Contracts and Invariants

A Canvas node can carry an optional source language independent of its diagram role; absence represents no recorded language.
Schema version is `1`. Supported kinds are hierarchy, relations, controlFlow, dataFlow, stateTransition, sequence and proofDependencies. A semantic document has at most 500 nodes, 1500 edges, 128 lanes and 128 interaction fragments. Node and edge IDs are nonempty, unique and disjoint. Host presentation prefixes (`__svg`, `__lane:`, `__fragment:`, `__lane-contains:`, `__contains:`) are reserved. Endpoints, parents and lanes resolve within the document. Containment is acyclic and at most 64 levels. Sequence events require finite order and a declared lane. Static SVG has no semantic nodes, edges or lanes. A document must contain drawable content.

Source name, format and digest identify the imported origin. Source references and arbitrary details are literal values, never implicit file reads or execution instructions. Reader and session protocols return typed errors rather than empty success on unsupported or invalid input.

## Verification and Change Impact
[CanvasTests](../../../Tests/ArchitectureTests/CanvasTests.swift) verifies identity, hierarchy, bounds, sequence structure and static-image separation through actual readers. Schema changes recheck Import, Sessions, Service, MCP and browser projections.
