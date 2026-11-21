# ArchitectureIR.Model

## Purpose and Scope
Own immutable Entity, Fact and SourceAnchor transfer values in the [IR module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Represent recorded structure and source identity. Providers produce values; validation, persistence and projection have separate owners. This component performs no parsing, I/O or semantic inference.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [IR module](../DESIGN.md) | parent | Immutable schema 1 transfer values | Public composition | Preserve serialized compatibility |
| [Syntax](../../ArchitectureFrontend/Syntax/DESIGN.md) | used by | Declaration-role refinement | Produces recorded roles | Role changes require provider cache invalidation |
| [Page](../../../Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Page/DESIGN.md) | used by | Coarse category and optional refinement | Displays recorded structure | Unknown refinement stays unknown |

## Architecture
```text
Provider -> Entity / Fact / SourceAnchor -> validation / store / query -> consumers
```

## Contracts and Invariants
`Entity.kind` is the stable language-neutral query category. Optional `attributes["declaration.kind"]` refines a recorded declaration using normalized syntax-backed values: class, struct, enum, actor, protocol, trait, extension, implementation, union, module, function, method, associatedFunction, initializer, deinitializer, property, field, constant, static, typeAlias or associatedType. Unknown refinement stays absent; consumers display the coarse category without guessing from a name. Refinement is metadata and does not change lexical identities or schema major version. Source signatures remain provider-owned attributes.

Optional property attributes are syntax-owned: `declaration.access` records explicit read visibility, `declaration.setterAccess` explicit setter visibility, `declaration.binding` records Swift let/var or Rust field/const/static/static mut, and `declaration.type` is the exact explicit type spelling. Absence means unrecorded; it never asserts effective access, inferred type or runtime mutability. These additive attributes do not alter schema version, identity keys or source revisions. Historical snapshots without them remain valid.

Callable metadata uses `declaration.parameters` for the exact source parameter-list spelling, `declaration.returnType` for the result spelling and `declaration.returnTypeExplicit` to distinguish explicit results from the language default (Swift Void / Rust unit). Initializers/deinitializers have no result-type attribute. `declaration.modifiers` records supported source-backed callable modifiers/effects in source order. `declaration.access` remains explicit lexical visibility. An explicit result arrow without a captured result is unknown, never a default result. These additive fields preserve identities and historical snapshots.

`declaration.callable` version 1 is additive structured syntax metadata shared by free functions, members and associated functions. Its optional parameters are ordered objects with source spelling, lexical name/label/type and passing modifiers; receiver is separate (none, instance, type, owned, sharedBorrow, mutableBorrow or explicitType). Type parameters, where constraints and annotations retain source spellings. Effects, safety and other modifiers remain distinct arrays. Results are ordered type/origin objects; resultStatus distinguishes recorded, unknown and notApplicable. Explicit access is lexical, never effective visibility. Unknown fields stay absent, and older consumers may use retained legacy attributes. No constructor result, inferred type, exception behavior or semantic binding is invented.

Fields are immutable and Sendable. Identity keys and exact-byte entity revisions remain separate. Source anchors use UTF-8 byte offsets and recorded input digests. Extension attributes retain arbitrary JSON values during Codable exchange.

## State, Ownership, and Lifecycle
Values own their strings, arrays and JSON attributes using Swift value semantics. No mutable shared owner, descriptor or shutdown action belongs to this component.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests/BehaviorTests.swift) verify actual declaration refinements, identity across edits, Unicode/CRLF anchors, graph validation and serialized round trips. Optional refinements preserve coarse query/identity compatibility; consumers fall back for older snapshots. Changes to identity or serialized fields require parent and consumer review.
