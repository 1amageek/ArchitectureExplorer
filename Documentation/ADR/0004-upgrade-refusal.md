# Close refused WebSocket upgrades

A raw RFC 6455 client with no session received no 101 response but the pinned upstream host left the socket waiting after the pre-upgrade callback returned nil. The same condition occurred when the callback threw. This violates bounded refusal behavior.

ArchitectureHTTPHost vendors only the native hosting adapter from swift-web commit 6edadb6cfa92e3a4b26a1e669329be38f45212f4 under its MIT license. The manifests still consume the pinned, unmodified SwiftWebCore/SwiftHTML dependency; no upstream checkout or separate project is modified. The adapter closes the channel on nil/throw before the upgrader can fall back. Original hashes, the license and local deltas are recorded in Apps/ArchitectureExplorerWeb/native-host-upstream.json. NIO futures and immutable binary storage remain confined to the established upstream platform adapter contract.

The actual HTTP/WebSocket tests must pass before this correction is considered complete. No refusal success is inferred from the callback's return value alone.
