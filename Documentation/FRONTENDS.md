# Frontends

| Feature | Swift | Rust | Evidence |
|---|---|---|---|
| Types, lexical callables and source ownership | Available | Available | Skeleton plus original tree-sitter AST |
| Call-site expressions | Available | Available | Syntax; unresolved candidates |
| Type spellings/imports | Available | Available | Syntax; no inferred binding |
| Official project metadata | SwiftPM describe with resolution disabled | Cargo metadata offline/no-deps | Explicit trust, incomplete active configuration |
| Definition/references/call hierarchy | Explicit SourceKit-LSP | Explicit rust-analyzer | Advertised capability checked; freshness unknown unless whole-project inputs are fixed |
| Limited structured CFG | Available, including guard | Available | On-demand AST; unsupported effects reject generation |

The supplementary adapter never reparses skeleton text or uses regex to infer calls/CFG. Tree-sitter String offsets are UTF-16; source anchors remain exact original UTF-8 bytes. CRLF, emoji and combining characters are tested. Identity uses workspace/path/lexical owner/kind/normalized signature and a collision occurrence, independently of source revision.

CFG supports synchronous sequential expressions/declarations/assignments, if/else, while, early return and resolved loop break/continue. It rejects defer, await, throw/try/unwind syntax, short-circuit expressions, macros, match/switch/for, closures and unmodeled expression kinds. The CFG is structural and says nothing about feasible paths or safety. Calls are opaque normal-flow operations; internals and exceptional runtime failures are excluded explicitly.

Provider absence is explicit. Installing providers, resolving external dependencies and granting persistent trust are outside normal read-only analysis. The SourceKit probe and exact capabilities are recorded separately; a successful definition response is not a full call-graph guarantee.
