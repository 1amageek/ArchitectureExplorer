# Architecture

[DESIGN.md](../DESIGN.md) is the system/package design authority and links all module/component contracts. This document is the reader's entry point; it does not duplicate those contracts.

| Owner | Responsibility |
|---|---|
| Core / IR | Transfer values, identity keys, exact-byte anchors and schema |
| Frontend | Pinned skeleton structures, supplemental original AST, limited CFG and explicit LSP |
| Graph | Snapshot-bound projections, traversal, pagination, diff and export |
| Store | SQLite FULL transactions, immutable history, identities and external namespaces |
| Indexer | Reconciliation, parallel file parsing, generation checks and stale retention |
| Service / Client | One same-user daemon and versioned Unix JSON-RPC |
| MCP / CLI / Web | Consumer adapters, without independent workspace indexing |

The macOS native hosting adapter is pinned SwiftWeb source under MIT with a small reviewed refusal/size-limit correction. See ADR 0004 and the original source hashes in the Web package. The root has no HTTP/GUI dependency.
