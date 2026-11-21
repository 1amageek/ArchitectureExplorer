# Canvas import profiles

Explorer imports declarative data without starting tools. Files are UTF-8, at most 1 MiB; a document has at most 500 nodes, 1500 edges, 128 lanes and 128 interaction fragments. XML and group depth is at most 64. Unsupported syntax is a typed `UNSUPPORTED_SYNTAX`; malformed data is `INVALID_CANVAS`. Imports are atomic and never change source snapshots. The source digest, filename, format, original attributes and details remain inspectable.

| Extension | Supported profile |
|---|---|
| `.json` | Canvas document v1 with explicit `kind`; ArchitectureIR GraphView/Snapshot (`nodes/edges` or `entities/facts`); extension graph (`nodes/edges`, explicit optional kind). Nodes/edges carry details and optional source references. Sequence documents declare lanes and numeric event order. |
| `.dot` | DOT graph/digraph, optional strict, quoted/unquoted IDs, comments, chained edges, ports, graph/node/edge attributes, assignments, nested subgraphs/clusters and subgraph edge endpoints. Labels and HTML-like labels are literal text. Original attributes are retained; provider coordinates are not layout authority. |
| `.mmd` | Mermaid flowchart/graph with directions, node shape labels, edge chains/labels, subgraphs; stateDiagram/stateDiagram-v2 with aliases, composite states, start/end markers and transition labels; sequenceDiagram with participants/actors, aliases, synchronous/asynchronous messages, notes and bounded interaction fragments. Unsupported diagram families/directives are explicit failures. |
| `.puml` | `@startuml` / `@enduml` class/interface/enum/abstract class/package declarations, members and relationships; state declarations/aliases/composites and transitions; participant/actor sequence messages and fragments. No preprocessor, includes, macros or external resources. |
| `.graphml` | GraphML nodes, directed/undirected edges, nested graphs, key/data/default attributes. Common yFiles label elements are retained as text. Hyperedges and ports are explicit unsupported syntax. |
| `.scxml` | W3C SCXML state/parallel/final/history hierarchy, initial/default transitions, event/cond/target and executable content retained as literal details. Never executes actions, conditions or scripts. |
| `.xmi` | UML 2 XMI Model/Package/Class/Interface/Enumeration/DataType, properties/operations, Generalization/Dependency/Association/Realization, StateMachine/Region/State/Pseudostate/FinalState/Transition and Interaction/Lifeline/MessageOccurrenceSpecification/Message. External references and unrecognized semantic model elements fail explicitly. |
| `.svg` | Static SVG elements/attributes with local fragment references only; scripts, event handlers, foreignObject, animation, DTD/entities, external resources and stylesheet/CSS URL references are rejected. Displayed as an isolated image, not converted to graph facts. |

Diagram kinds: `hierarchy`, `relations`, `controlFlow`, `dataFlow`, `stateTransition`, `sequence`, `proofDependencies`. JSON can express every kind. DOT defaults to relations, SCXML to stateTransition; a caller can explicitly choose a graph kind where the format does not supply one. Sequence order and lanes are supplied facts, not inferred timestamps. TLA+/TLC and Lean conversion stay with external tools.

## Canvas JSON v1

A document uses `schemaVersion: "1"`, `kind`, `title`, `nodes`, `edges`, optional `lanes` and `metadata`. Each node has `id`, `label`, `role`, optional `parentID`, `laneID`, numeric `order`, `details` and `source`. An edge has `id`, `source`, `target`, `label`, `role`, `directed` and optional numeric `order` and `details`. A lane has `id` and `label`. Host presentation IDs `__svg` and prefixes `__lane:`, `__fragment:`, `__lane-contains:`, `__contains:` are reserved. Static SVG documents cannot also contain semantic graph elements. Source references are literal metadata, never instructions or implicit file reads. IDs are document-local and qualified by session/document at presentation boundaries.

### Specification verification evidence

A producer can attach `metadata.specVerification` to a Canvas document. Its `checks` array enumerates the verification obligations for the reported run. Each entry has a unique nonempty string `id`, a `nodeID` for the subject, an `evidenceID` for the checker result, and an explicit `outcome` of `passed`, `failed`, or `notVerified`. Both references must resolve in the document. The required `openQuestions` array lists distinct node IDs for unresolved specification boundaries. Expected counterexamples from negative controls are graph evidence outside the run's primary check list.

A report may supply `metadata.specVerification.mapBinding` with `workspaceID`, `snapshotID` and `entityID` identifying its C4 subject. This navigation reference opens the imported specification report from that exact Map object. The report's checks and open questions still determine its guarantee scope.

## Shared sessions

`canvas.open` accepts `name`, `text`, optional `kind` and optional existing `viewSessionID`/`expectedRevision` for atomic replacement. `canvas.list`, `canvas.get`, `canvas.close`, `canvas.select`, `canvas.focus`, `canvas.expand`, `canvas.collapse`, `canvas.setFilter`, `canvas.setLayout` (optional diagram `kind`), `canvas.setCamera`, `canvas.setGeometry` and `canvas.export` share daemon-owned state. `canvas.get` supports paged `nodes`, `edges` and `lanes` collections, or `collection: "state"` for acknowledged state without geometry. MCP defaults to paged nodes and returns a compact committed acknowledgment for mutations; large details are read separately. Session mutations optionally compare `expectedRevision`; stale updates fail with `REVISION_CONFLICT`. Closed sessions fail explicitly. At most 32 sessions / 16 MiB encoded state. Screen polling reconciles shared revisions; gestures coalesce camera commits. No command conveys verification execution authority.

Exports retain the entire normalized JSON document. SVG export of graphs requires acknowledged rendered geometry; unavailable geometry fails explicitly rather than inventing a different view. Static SVG exports preserve their validated image. Live rendered SVG export uses the current acknowledged positions and visible projected edges. It is a logical vector export; browser routing and source-card artwork are not reproduced pixel for pixel. Session state is ephemeral across daemon restarts. Shared sessions cover imported files and external graphs; live source navigation retains its existing browser history state.

## References

- [DOT grammar](https://graphviz.org/doc/info/lang.html)
- [Mermaid syntax](https://mermaid.js.org/intro/syntax-reference.html)
- [PlantUML](https://plantuml.com/)
- [GraphML](https://graphml.graphdrawing.org/primer/graphml-primer.html)
- [SCXML](https://www.w3.org/TR/scxml/)
- [UML / XMI](https://www.omg.org/spec/UML/2.5.1/)

- [Cytoscape loop styling](https://js.cytoscape.org/#style/loop-edges)
