# ArchitectureCanvas.Import

## Purpose and Scope
Own offline diagram parsing and SVG sanitization. Parent: [Canvas](../DESIGN.md). No children.

## Responsibilities and Boundaries
Convert supported file syntax into validated CanvasDocument values. Parsing does not publish ArchitectureIR facts, access referenced files, run external tools or execute source content. The syntax matrix is owned by [import profiles](../../../Documentation/CANVAS-FORMATS.md).

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Canvas](../DESIGN.md) | parent | Reader composition | Module boundary | Recheck consumers on syntax changes |
| [Contracts](../Contracts/DESIGN.md) | depends on | CanvasFileReading, documents and validation | Output guarantees | Preserve local identities and provenance |
| [Sessions](../Sessions/DESIGN.md) | used by | Synchronous validated read | Admission follows parsing | Failed parse cannot replace a session |

## Architecture
```text
UTF-8 file -> extension dispatch -> format reader -> document validation
                         XML -> bounded literal tree -> profile / SVG sanitizer
```

## Contracts and Invariants
Accepted profiles are JSON, DOT, Mermaid, PlantUML, GraphML, SCXML, UML XMI and static SVG. Coordinates from external formats are retained as data, not rendering authority. The Contracts owner defines semantic budgets. Digest covers original UTF-8 text, including a BOM; a leading BOM is removed only for parsing. Unsupported syntax is explicit failure.

## State, Ownership, and Lifecycle
Every synchronous read owns its builder, tokens and XML tree. Temporary state is released with the read. No global parser or cross-target state branches exist.

## Failure, Concurrency, and Constraints
Input is at most 1 MiB UTF-8 and contains no NUL. XML is at most 20,000 elements and 64 levels. JSON is at most 100,000 values and 64 levels. Readers reject script/include directives, DTD/entity resolution, unsafe SVG elements, event handlers and external resources. Static source conditions/actions are retained literally and never executed. Parsing is bounded synchronous work; cancellation is checked by the session owner before and after a read, before publication.

## Verification and Change Impact
[CanvasTests](../../../Tests/ArchitectureTests/CanvasTests.swift) and [native integration](../../../Tools/canvas-integration.py) use real files for all formats, explicit unsupported/malformed cases and export reimports. Format changes recheck Contracts, Sessions and renderer fixture coverage.
