# C4 System Context from typed project inputs — Explorer display specification

## Purpose and authority

Explorer derives L1 from authorized, machine-readable inputs. A root ARCHITECTURE.dsl, when present, is the authoritative Map model for that snapshot. Without it, the native catalog adapter applies. Explorer owns extraction, reference resolution, navigation and rendering. Invar owns applicability and verification results. Formal owns model claims and source correspondence. This document owns the Explorer projection and navigation contract.

## Source facts and resolution

1. Pin the workspace snapshot, environment and authorized inputs, including a separately captured revision for external configuration when available. Record incomplete capture. Historical queries read only these pinned inputs.
2. Parse each supported source independently using its native schema, version and precedence rules. An extractor emits typed facts with their source authority, object identity, referenced identity, locator, content digest and extraction rule. Parse failure invalidates facts requiring that input and is visible as a diagnostic.
3. Join exact typed references in their valid scope. An existing catalog membership or equivalent explicit system identity can establish a boundary. A build target, repository, Terraform module, resource name or free-text description alone cannot establish one. A client and server with matching labels alone do not establish a connection. Unknown, inaccessible or ambiguous references stay unresolved.
4. Project resolved interactions crossing system boundaries onto L1. Preserve internal links for drill-down. Merge equivalent directed relationships while retaining every supporting fact. Keep configured, planned, recorded and observed facts distinguishable. Actual execution requires attributable runtime evidence.
5. Open the sole resolved subject, or let the user select among resolved systems in a monorepo. Selection is view state. With insufficient input, show the resolved portion and diagnostics, or an undetermined Context if there is no resolved subject. Re-index the authoritative input when it changes. Catalog workspaces need no generated artifact. For generated DSL, the producer refreshes the artifact when its implementation inputs change.

| Existing source | Typed fact | Required join or limit |
|---|---|---|
| Service catalog | System membership, API consumer/provider | Resolve authority-qualified entity and API references |
| Client MCP configuration | Configured launch target or endpoint | Resolve effective host configuration, command/arguments and executable or endpoint identity in the same environment |
| API, event or extension contract | Supplied operation, data type or publication capability | Match its identified provider and contract; a capability alone cannot identify a consumer |
| Infrastructure or routing configuration | Resource attachment, routing or message delivery | Apply resource-specific semantics and resolve endpoint ownership. Provisioning order alone is insufficient |
| Trace or retained operation record | Observed execution | Require attributable endpoints and execution correlation; absence of observation does not disprove a configured relationship |

For example, if a captured Codex MCP entry targets an executable resolved to Invar in MCP mode and both system identities are established, project a configured Codex → Invar relationship. The tools exposed by that entry supply operation detail. A Claude entry resolved to the same executable yields a separate relationship. Shared transport or executable names cannot establish client attribution for a verification run.

## Identity and revisions

An ElementID keys (identity authority, native system or person reference, kind). A RelationshipID keys (source ElementID, target ElementID, namespaced operation, namespaced artifact when established). Use typed tuples with explicit optional fields. A relationship may express generic configured connectivity until richer semantics are established. Names and file enumeration order are display and processing details. An identity change produces a different subject unless the source authority provides explicit continuity.

Scope each derived graph by workspace, snapshot and environment. Identify its derivation revision by hashing an unambiguously encoded, canonically sorted inventory of authority-qualified input identities, content digests, availability states and extractor versions. This digest is independent of the existing Explorer and Invar contextDigest fields. A source shared across environments participates only where its own applicability permits. Maintain provenance and identity joins as derived index data with the snapshot; they can be rebuilt.

## Resolution against implementation

Resolve a derived subject to implementation only through a typed source link or a versioned extractor rule connecting the identified implementation entry point to the subject. Check the exact declaration kind, source anchor, file digest and UTF-8 byte range against the pinned index. Retain the subject, derivation revision, workspaceID, snapshotID, entityID, entityRevision, SourceAnchor and rule or original source link. Reverse lookup can return multiple subjects. A missing link, ambiguous overload or incomplete lookup leaves the binding unresolved. Re-resolve on change and preserve the original binding in history.

Illustrative implementation targets for the Invar system and its evidence-publication relationship. The row labels are descriptive. Actual anchors returned by the Explorer CLI for Invar snapshot `9006510A-2AC1-4621-A7AE-40AFC3D98281`:

| Context subject | Explorer declaration | Captured UTF-8 range |
|---|---|---|
| element/invar | actor WorkspaceDaemon, `ae-533bbe2bc611c2236a02c98a942c5ce9d2faf49692f7aad010f48895c8740cda` | WorkspaceDaemon.swift [185, 15684) |
| relationship/publish-evidence | method ExplorerPublisher.deliver, `ae-64c4b397a6ec5dee8b6f115e63100ac39f94ed0ca642dcbfefad7c2aa0fa0b6c` | ExplorerPublisher.swift [14268, 16513) |

The latter method checks the original run identity and reserved generation before preparing, staging and committing delivery. The anchor identifies code relevant to the relationship; it does not prove delivery order.

## Verification binding and reverse navigation

A binding requires an explicit typed join from an existing verification configuration or retained producer record to the derived subject or its identified operation. A method name, test name or matching job label cannot establish this join. If the producer supplies no such reference, the check remains unbound. Resolve the captured configuration digest, backend and job ID to the exact target JobDescriptor in the plan. Pin the derivation revision and input provenance on the binding. Reading references does not schedule work or grant execution authority.

For a selected operation the proposed derived binding record has these fields:

```text
context       = (workspaceID, snapshotID, environment, derivationRevision, typed subject ref)
obligation    = (configuration path, configuration SHA-256, backend, jobID)
target        = (target inputID, planID, target descriptorID)
assessment    = (view reference, runID, associationID, evidenceID)
formal detail = optional (bundle ID and SHA-256, claimID, optional graphID/traceID)
```

Explorer binds the subject to evidence supplied by an authorized Provider. Invar supplies retained input, run, descriptor, association and evidence references. Check view/run membership, plan and target descriptor ownership, target input and job identity, association membership and association.evidenceID. Check the original evidence's execution, descriptor and original input. For reuse across inputs require Invar's valid reassociation to the exact target descriptor and input; retain both original and target references. Without an association naming the exact target, expose only historical evidence or an unresolved assessment. Never infer equivalence from a shared job ID. For Formal details verify the artifact membership and digest, claim membership and obligation mapping inside that bundle. Attach a trace only when its graph and obligation identify the relevant trace unambiguously. Never infer a match from proposition text. Values and source ranges remain subject to their owner's read permissions.

For the example, publication-order would express the obligation “an older reserved generation cannot replace a newer published head.” The existing Swift regression test exercises reverse completion with a delayed publication. Its source is implementation/test context. A test name or passing Swift suite does not produce a Formal claim. Only an actual retained check attempt can populate assessment. A counterexample navigates back through bundle → evidence → association → subject → pinned implementation anchor. A model failure with unvalidated source correspondence remains a model failure; show an origin only at its recorded precision. No source origin means no direct counterexample-to-line link.

Default evidence comes from the acknowledged complete published Explorer head, for the matching derived subject revision and target input. A resolved Context can render before any head exists. On a newer source snapshot keep an older head explicitly historical until an applicable assessment is published. Failed, partial and in-flight operations remain reachable by their individual references. A counterexample can be part of a complete publication. Keep execution, outcome, applicability and model-to-source correspondence independent. No automatic green badge on a relationship or its endpoint.

## Presentation and acceptance

Fresh workspace entry and Home open L1 for the selected system. Browser Back restores the original snapshot and selection. Each relationship opens its supporting native records, implementation links and applicable verification results. Present conflicting or missing references alongside available facts. The code view remains accessible.

| Behavioral acceptance case | Required result |
|---|---|
| Missing endpoint, unsupported source version or conflicting ownership | Explain the affected fact; keep independent resolved facts visible |
| Same native inputs discovered in a different order | Same graph, provenance set and derivation revision |
| Two environments reference different deployments | No cross-environment join |
| Rename a display label; reorder records | Same logical subjects and topology; new raw-byte revision when bytes change |
| Same method name at a call site or in another file | Only the declared method at the specified path can resolve |
| Two matching overloads, partial lookup or stale file digest | Ambiguous, incomplete or mismatch diagnostic; no speculative link |
| Same job ID from another configuration or changed subject semantics | No evidence attachment |
| Valid model counterexample with unknown source correspondence | Show scoped counterexample and correspondence status; no code-level verdict |
| Empty evidence history, later partial publication, concurrent runs finishing out of order | Context remains navigable; only the applicable confirmed head supplies default evidence |
| Click a counterexample, return to its relationship, then open its method | Resolve the complete retained chain on the original snapshot, or report the unavailable/unauthorized step |

Implementation profile: the first native input adapter indexes Backstage catalog-info JSON/YAML records for System, Component, Resource, Domain and API with explicit system membership, dependsOn component/system references, and consumesApis/providesApis sharing one unambiguous API and provider in the captured workspace catalog. It shows directed configured dependencies in the catalog scope. Other sources above are extension points. Missing membership remains unresolved. No additional project file is required.

Evidence delivery: [Invar provider contract](https://github.com/1amageek/Invar/blob/main/Documentation/EXPLORER-EVIDENCE.md).

### Structurizr DSL input

The indexer captures a root `ARCHITECTURE.dsl` as UTF-8 data. Invar can generate
this root and package fragments from implementation and configuration. A local
`!include` expands a relative DSL file in place, resolving from its including
file. Capture only the reachable inputs within the workspace selection. Each
file is included once, with a limit of 256 files, 32 levels and 512 KiB total.
A cycle, missing input, excluded path, or escape invalidates the Map. Follow latest switches a pinned Map to its live subject, while browser Back restores the pinned query. Preserve
the original file, digest and UTF-8 range on declarations and relation evidence. Its source
comments identify the derivation inputs. Explorer owns parsing, snapshot-local
identities, source anchors, C1/C2 projection and rendering.

The Map profile adds the following constraints to standard Structurizr DSL:

- Declare each top-level person or software system inside one named model-level
  `group`. The group declares a domain area. Multiple elements may share it.
  Each container belongs to its enclosing software system and inherits its domain.
  Within a software system, a named `group` can contain container declarations.
  These groups form sibling areas within the expanded system in C2. Group names
  must be nonblank and unique within their owning system. Ungrouped containers
  remain directly in the system area. C1 displays the model-level groups.
- Give each element a unique flat identifier independent of its screen
  position. Use a nonblank domain name unique within the model.
- Declare directed interactions between existing element identifiers, with a
  nonblank operation and optional technology. Cross-domain interactions retain
  both endpoint memberships. Groups have no runtime identity and cannot serve
  as relation endpoints. Use `!impliedRelationships false` and explicitly
  declare the desired system-level and container-level interactions.
- Keep unknown ownership explicit. A generated logical boundary describes
  only the scope supported by its inputs. A shared technology or name alone
  cannot establish common ownership. Unconnected declarations are valid.
- Supply either the model alone or one wildcard systemContext/container pair
  for each selected software system. Keys are unique across the workspace.
  With multiple declared subjects, Home opens the shared context overview.
  Each system's options open its own context or containers. Switching between
  those two levels retains the subject and the selected snapshot.
  The Map profile accepts semantic input only. Coordinates, port
  choices, scripts, remote includes and rendering directives are outside the profile.
  An invalid input produces a diagnostic for the snapshot.

### Map

Map is the graphical presentation for System Context (C1) and Containers (C2).
The live Context view opens an identified system at the same snapshot with
`graph.overview(level: container, focus: systemID)`. The selected system
becomes an area. An explicitly owned Backstage service or website contributes
an application, and an owned database resource contributes a data store. The object vocabulary below defines additional supported runtime types.
Libraries and components without a known runtime type remain at the system
boundary. The nearest external endpoint is its identified system. Each
projected connection retains the source records supporting both endpoints.
An empty interior is explicitly unresolved. Catalog domains, including parent
domains, supply optional nested areas; they confer no execution boundaries.
The renderer takes domain membership from the active input adapter. It draws
only declared areas. Sibling areas and objects are placed on the grid using
their directed connections; stable identifiers break ties. Route cost accounts
for bends, shared lanes and the final approach to the raised target. Layout
never reverses a relationship or changes membership.
On expansion the subject becomes the area for its containers. Paths reach the
object ports on the floor grid. Objects on a shared clear grid line can use
ports along their facing sides to connect directly. An obstacle can require
an elbow or a detour. Connectors approach the target along the last straight
segment and draw their arrow at that segment's endpoint outside the footprint.
The stroke, hit area and directional animation use the same path.

The shared renderer uses an orthographic Three.js camera and five primitives:
grid, object, area, path, label. Geometry and placement are presentation state.
Objects use a shared scale within their grid cells. Captions clear the projected
silhouette, and connector endpoints meet the perimeter reserved for the object.
Object titles stay horizontally centered above the silhouette, with a bounded
horizontal shift or abbreviation when space is tight. Horizontal area names
interrupt their own front-left border, with the front-right border as the
alternate. The active area takes precedence over a conflicting ancestor.
The subject breadcrumb retains its domain ancestry. Operation names attach
to clear straight route segments. A generic dependency is named on hover,
keyboard focus or selection, together with its endpoints. Hover reveals the
full name above other captions without moving the underlying layout.
Objects show selection on their projected grid footprint. Keyboard focus traces the
same footprint, area boundary or route with a dashed line. The contact shadow
remains below each object. Selection preserves other visible containers and their positions. An oriented
path terminates in an arrow; only the selected path animates and reduced motion
stops the animation. Offline HTML uses the same renderer and pinned view.

Selecting an object opens its snapshot-local inspector from the map, its
caption, or the navigator. It shows its purpose, domain, owner, runtime type,
technology and visible directed interactions. A peer can be selected in place.
A system can open its container view. The inspector distinguishes the model
declaration from implementation locations cited by the generator. A contiguous
block of Invar source comments immediately before an element supplies display-only
references. These references do not authorize reads or establish verified evidence.

### From a container to its implementation

Only C1 and C2 use Map. A local container may declare one typed link in a
contiguous annotation preceding its declaration: `// Entry: <kind> <startByte>..<endByte> sha256=<digest> <relative path>`.
Offsets are half-open UTF-8 bytes. Use an indexed declaration kind or `file`
with the full byte range for an entry file that has no single named declaration.
Explorer resolves the link only to a unique indexed entity matching the kind,
path, digest and range in the pinned snapshot. Ordinary citation comments do
not establish a link.

Open components switches to the source graph at the indexed entry declaration.
The initial page prioritizes the entry and the types it directly references,
including candidates outside the entry file. The graph identifies the entry's
recorded module when available, with the entry file as the fallback scope.
Cross-module Swift candidates require a direct recorded module dependency and
an explicit import in the source file. Their edges remain lexical candidates
with source evidence. Open code follows recorded source containment in the same
snapshot. Missing or stale entry bindings leave the container inspectable.

A file entry opens its own top-level declarations and recorded direct local
imports. Imported files stay outside the entry file and open their own code.
The import edge exposes the source statement. TypeScript indexing is opt-in
with `typescript` in `architecture.json`. Static relative imports and
re-exports can link to one matching current indexed file. Resolution checks
explicit paths and, for extensionless imports, `.ts`, `.tsx` and directory index
files. Aliases, package resolution and dynamic imports are outside the
projection. Single-click selects for inspection. Double-click or Open
components opens the pinned source graph.

### Map objects

The map selects a component from the pinned entity kind and its recorded
`context.catalogType` (the normalized Backstage `spec.type`). A component
defines geometry in local coordinates, centered at its floor port. The map
owns projection, scale, title placement, interaction and evidence. Repeated
instances share one rendered symbol per component per map and theme. Rounded
molded parts form the toy silhouettes. Pigment stays consistent across themes,
with lighter shaded faces on the dark canvas.

| Component | Input | Silhouette |
|---|---|---|
| Person | Person | Round head, tunic and shoes |
| Software system | Software system | Studded blocks on a common base |
| Application | Application without a recognized subtype | Single enclosure |
| Web application | Component / website | Browser window on a stand |
| Mobile application | Component / mobile-app | Portrait handset |
| Service | Component / service | Rack with two server units |
| Worker | Component / worker | Horizontal motor with a spindle |
| Gateway | Component / api-gateway | Two posts supporting a span |
| Database | Resource / database | Three stacking rings and a central peg |
| Cache | Resource / cache | Low chip with external pins |
| Message queue | Resource / queue | Ordered upright slots in a channel |
| Object storage | Resource / object-storage | Open bucket with a curved handle |
| Data artifact | Explicit data artifact in a diagram | Offset sheets |
| Data store | Data store without a recognized subtype | Single storage cylinder |
| Unknown | Unrecognized entity kind | Neutral tile |

The component and resource rows require existing, resolved system ownership.
Components retain the application kind and resources retain the data store kind.
Data artifacts are diagram objects. Catalog files, API contracts and payloads do
not automatically become C4 containers. A title or a product name never selects
a subtype. Previously saved views retain the detail recorded in their snapshot.

## Workspace sequences

A root `SEQUENCES.dsl` extends the root `ARCHITECTURE.dsl` using Structurizr's local workspace extension syntax. It contains a `views` block with named `dynamic` views. A view uses an explicit stable key, a title or description, and ordered interactions between existing architecture elements. The supported profile uses one view per alternative outcome, implicit order or consecutive explicit integer order, and a unique matching architecture relationship. A response can reuse the reverse of an earlier matching request in the same scenario. Unsupported input produces a path and line diagnostic, and leaves the C4 Map available.

Each view can declare an `invar.requirements` property with space-separated requirement IDs. Preceding `// Source: path:line sha256=<digest>` comments cite one or more requirements, source statements, or tests for a step. Capture only bounded regular workspace files for these references. A citation whose digest or line cannot be confirmed remains unresolved or stale with no substitute excerpt.

The Indexer resolves the input against the architecture and evidence of the same capture, and persists the result with the immutable snapshot. The service serves snapshot-bound lists and Canvas documents; invalid replacement removes the live sequences while historical snapshots retain their own definitions. Diagram steps are declared interactions. Evidence excerpts and architecture links support review, and carry no execution or verification verdict.
