# Platform and source parsing

Status: accepted implementation decision, 2026-11-16.

The user's latest-OS-only request supersedes SPEC 3.2 deployment floors. Both manifests target macOS 27 and Swift tools 6.4; validation uses Swift 6.4.1 on macOS 27.2.1 arm64.

Skeleton revision 1215a3bd86d172e07151c7ccc9a213cb6ea27434 provides Swift free declarations and Swift/Rust type blocks. Its Rust parser lacks free function metadata. The supplementary adapter reads original tree-sitter nodes, never reparses skeleton text. CArchitectureSyntax declares the public tree_sitter_swift/tree_sitter_rust C ABI symbols linked by SkeletonSwiftParser/SkeletonRustParser. Grammars remain pinned in swift-skeleton; SwiftTreeSitter is pinned at 0.25.0 (the Rust grammar requires ABI 15; the initial 0.9.0 probe linked but rejected Rust at runtime). SwiftTreeSitter's String parse uses UTF-16; the adapter translates offsets to canonical UTF-8 anchors using the exact input string. Parser objects never cross concurrency boundaries.

The root manifest has no Web dependency. The Web manifest uses the released Architecture Explorer SDK at the matching release tag and pins swift-web independently. Source manifests are never executed unless an explicit local trust grant exists.
