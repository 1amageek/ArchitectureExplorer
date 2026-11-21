# ArchitectureFrontend.Syntax

## Purpose and Scope
Own saved-source syntax extraction in the [Frontend module](../DESIGN.md). No children.

## Responsibilities and Boundaries
Parse immutable Swift/Rust bytes into lexical declarations, source anchors, containment, unresolved call sites and type spellings. Semantic binding, build execution, CFG and store publication have separate owners.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Frontend module](../DESIGN.md) | parent | Pure source provider | Public composition | Preserve read-only inputs |
| [IR Model](../../ArchitectureIR/Model/DESIGN.md) | depends on | Entities, facts, anchors and declaration refinements | Recorded syntax output | Identity and role remain separate |
| [Indexing](../../ArchitectureIndexer/Indexing/DESIGN.md) | used by | Producer-scoped result from captured input | Publishes or retains stale data | Advance provider cache revision when output changes |

## Architecture
```text
Immutable SourceInput -> original tree-sitter AST -> pinned skeleton pass
                               |                         |
                               +-> lexical extraction <--+
                                        |
                                FrontendResult or error
```

## Contracts and Invariants
The syntax provider supplies the IR declaration refinement from original grammar nodes and declaration-kind tokens. Existing coarse entity categories and identity keys remain unchanged. Rust receiver-free associated functions are distinguished from methods using the parameters AST. The provider cache revision changes when this metadata is introduced, ensuring existing workspaces are reparsed.

PropertyMetadata extracts the optional [IR property attributes](../../ArchitectureIR/Model/DESIGN.md) from direct declaration grammar nodes: modifiers, binding tokens and the type annotation associated with the recorded name. Swift setter-only visibility is distinct from read visibility; multiple-binding declarations never borrow a later binding's annotation. Rust fields have no standalone let/var mutability; their binding is recorded as field. Initializer expressions and computed-property bodies cannot supply a declared type. Unknown/default/effective information remains absent. Lexical identities remain unchanged.

CallableMetadata reads only callable header grammar nodes for parameter lists, result types and modifiers/effects. DeclarationAccess owns common explicit visibility extraction for properties and callables. Parameter closure arrows and bodies cannot supply the function result; implicit Void/unit is recorded only when the function has no result arrow. Initializers/deinitializers remain distinct. The provider cache revision advances to syntax-v7. Behavioral callable metadata tests use real Swift/Rust parses, including closure parameters, explicit/implicit returns and constructors.

CallableSignature projects original callable-header AST nodes and the legacy metadata into the structured IR contract. Swift parameter groups include default expressions without traversing bodies; passing modifiers such as inout remain distinct from receiver mutation. Rust receivers preserve borrowing, lifetime and explicit typed-self spelling; receiver-free impl functions are associated functions. Generic parameters, where clauses and attributes are syntax-backed. Bodies and closure parameter arrows never determine the callable result. The enclosing lexical owner supplies only instance/type/free classification. Extraction keeps existing identities and all call/type-reference facts.

Call expressions remain unresolved candidates; names never establish dispatch. Original source bytes own signatures, revisions and UTF-8 anchors. Parse failures are explicit ArchitectureError values, allowing the Indexer to retain stale last-known-good data.

## State, Ownership, and Lifecycle
Declaration extraction uses a bounded pending-node stack instead of recursive walk frames. It visits children in original source preorder, preserving callable/owner/conditional context and duplicate occurrence identities. Pending items cannot exceed the parser's 300,000 captured-node bound. This prevents deep valid source from exhausting the smaller cooperative-task thread stack.

Each analysis owns its parser/tree and transient source representation. Captured SyntaxNode values have no escaped parser pointers. Concurrent source jobs share only the immutable provider value; the Indexer owns scheduling and publication.

## Failure, Concurrency, and Constraints
The original AST capture rejects invalid syntax, more than 300000 nodes or nesting beyond 512. The upstream skeleton pass is synchronous and cannot be forcibly cancelled; its production call has an explicit incomplete-implementation marker. Input byte limits reduce admitted input size but do not establish an adversarial wall-clock deadline. No such termination guarantee is claimed.

## Verification and Change Impact
[Behavioral tests](../../../Tests/ArchitectureTests/BehaviorTests.swift) exercise actual Swift/Rust declarations, receiver roles, nested ownership, identity across edits, Unicode/CRLF ranges, failures and unresolved calls. Recheck Indexer cache invalidation, IR compatibility and Page consumers when output changes.

Repository map previews parse a single complete Swift, Rust or TypeScript/TSX source of up to 16 KiB on demand. The bounded original grammar produces lexical declaration cards with their parsed language and source byte ranges. This view never calls the workspace indexer, executes a manifest or infers cross-file bindings. Unavailable outlines leave an explicit reason alongside the bounded source preview.

A type records the first unqualified type spelling, direct callee, or simple member receiver for each referenced name in its lexical body and header. Nested types own their own sites. The records store names, lines and byte ranges, not source bodies. The syntax cache key advances when this contract changes.
