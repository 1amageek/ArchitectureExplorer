// swift-tools-version: 6.4
import PackageDescription

let names = [
  "ArchitectureCore", "ArchitectureIR", "ArchitectureFrontend", "ArchitectureGraph",
  "ArchitectureStore", "ArchitectureIndexer", "ArchitectureService", "ArchitectureClient",
  "ArchitectureMCP", "ArchitectureExtensions", "ArchitectureCanvas", "ArchitectureServer",
]
let package = Package(
  name: "ArchitectureExplorer",
  platforms: [.macOS("27.0")],
  products: names.map { .library(name: $0, targets: [$0]) } + [
    .executable(name: "architecture", targets: ["architecture"]),
    .executable(name: "architecture-host", targets: ["architecture-host"])
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(
      url: "https://github.com/1amageek/swift-skeleton.git",
      exact: "0.5.0", traits: ["rust"]),
    .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", exact: "0.25.0"),
    .package(url: "https://github.com/1amageek/swift-web.git", exact: "0.14.0"),
    .package(url: "https://github.com/1amageek/swift-html.git", exact: "0.16.1"),
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.105.0"),
    .package(url: "https://github.com/apple/swift-nio-extras.git", exact: "1.35.2"),
    .package(url: "https://github.com/1amageek/swift-tls.git", exact: "2.1.0"),
    .package(url: "https://github.com/1amageek/swift-tls-nio.git", exact: "0.1.1"),
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.0"),
    .package(url: "https://github.com/apple/swift-http-types", exact: "1.8.0"),
  ],
  targets: [
    .target(name: "CArchitectureSignals", exclude: ["DESIGN.md"]),
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
    .systemLibrary(name: "CArchitectureSyntax"),
    .target(
      name: "ArchitectureCore", dependencies: ["CArchitectureSignals"],
      exclude: [
        "DESIGN.md", "Values/DESIGN.md", "Diagnostics/DESIGN.md", "Filesystem/DESIGN.md",
        "Transport/DESIGN.md",
      ]),
    .target(
      name: "ArchitectureIR", dependencies: ["ArchitectureCore"],
      exclude: [
        "DESIGN.md", "Model/DESIGN.md", "Evidence/DESIGN.md", "Snapshots/DESIGN.md",
        "Queries/DESIGN.md",
      ]),
    .target(name: "ArchitectureCanvas", dependencies: ["ArchitectureCore"], exclude: ["DESIGN.md", "Contracts/DESIGN.md", "Import/DESIGN.md", "Sessions/DESIGN.md"]),
    .target(name: "ArchitectureExtensions", dependencies: ["ArchitectureCore", "ArchitectureIR"], exclude: ["DESIGN.md", "Contracts/DESIGN.md"]),
    .target(
      name: "ArchitectureFrontend",
      dependencies: [
        "ArchitectureIR", "CArchitectureSyntax", .product(name: "Yams", package: "Yams"),
        .product(name: "SkeletonIndexCore", package: "swift-skeleton"),
        .product(name: "SkeletonSwiftParser", package: "swift-skeleton"),
        .product(name: "SkeletonTypeScriptParser", package: "swift-skeleton"),
        .product(name: "SkeletonRustParser", package: "swift-skeleton"),
        .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
      ],
      exclude: [
        "DESIGN.md", "Syntax/DESIGN.md", "ControlFlow/DESIGN.md", "Project/DESIGN.md",
        "Semantic/DESIGN.md",
      ]),
    .target(
      name: "ArchitectureGraph", dependencies: ["ArchitectureIR"],
      exclude: ["DESIGN.md", "Query/DESIGN.md", "Export/DESIGN.md"], resources: [.copy("Resources")]
    ),
    .target(
      name: "ArchitectureStore", dependencies: ["ArchitectureIR", "CSQLite"],
      exclude: ["DESIGN.md", "Persistence/DESIGN.md"]),
    .target(
      name: "ArchitectureIndexer", dependencies: ["ArchitectureFrontend", "ArchitectureStore", .product(name: "Yams", package: "Yams")],
      exclude: ["DESIGN.md", "Indexing/DESIGN.md"]),
    .target(
      name: "ArchitectureService", dependencies: ["ArchitectureIndexer", "ArchitectureGraph", "ArchitectureExtensions", "ArchitectureCanvas", "ArchitectureClient"],
      exclude: ["DESIGN.md", "Daemon/DESIGN.md", "Requests/DESIGN.md", "SnapshotAccess/DESIGN.md", "Extensions/DESIGN.md"]),
    .target(
      name: "ArchitectureClient", dependencies: ["ArchitectureIR", "ArchitectureExtensions"],
      exclude: ["DESIGN.md", "Connection/DESIGN.md", "ExtensionProvider/DESIGN.md"]),
    .target(
      name: "ArchitectureMCP", dependencies: ["ArchitectureClient"],
      exclude: ["DESIGN.md", "Protocol/DESIGN.md"]),
    .executableTarget(
      name: "architecture",
      dependencies: [
        "ArchitectureService", "ArchitectureClient", "ArchitectureMCP", "ArchitectureFrontend",
        "ArchitectureGraph", "ArchitectureStore",
      ], exclude: ["DESIGN.md", "Commands/DESIGN.md"]),
    .target(
      name: "ArchitectureHTTPHost",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOWebSocket", package: "swift-nio"),
        .product(name: "NIOHTTPTypes", package: "swift-nio-extras"),
        .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
        .product(name: "TLS", package: "swift-tls"),
        .product(name: "TLSNIO", package: "swift-tls-nio"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftWebCore", package: "swift-web"),
      ], path: "Apps/ArchitectureExplorerWeb/Sources/ArchitectureHTTPHost",
      exclude: ["DESIGN.md", "Runtime/DESIGN.md"],
      resources: [.copy("Runtime/UPSTREAM-LICENSE")],
      swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
    .target(
      name: "ArchitectureWeb", dependencies: [.product(name: "SwiftHTML", package: "swift-html")],
      path: "Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb",
      exclude: ["DESIGN.md", "Page/DESIGN.md", "Page/SPEC.md"], resources: [.copy("Assets")]),
    .target(
      name: "ArchitectureServer",
      dependencies: [
        "ArchitectureFrontend",
        "ArchitectureWeb", "ArchitectureClient",
        "ArchitectureCore",
        .product(name: "SwiftWebCore", package: "swift-web"), "ArchitectureHTTPHost",
      ], path: "Apps/ArchitectureExplorerWeb/Sources/ArchitectureServer",
      exclude: ["DESIGN.md", "Hosting/DESIGN.md", "Session/DESIGN.md", "PageDelivery/DESIGN.md"]),
    .executableTarget(
      name: "architecture-host", dependencies: ["ArchitectureClient", "ArchitectureCore", "ArchitectureService", "ArchitectureServer"],
      exclude: ["DESIGN.md"]),
    .testTarget(
      name: "ArchitectureTests",
      dependencies: [
        "ArchitectureCore", "ArchitectureIR", "ArchitectureFrontend", "ArchitectureGraph",
        "ArchitectureStore", "ArchitectureIndexer", "ArchitectureService", "ArchitectureClient",
        "ArchitectureMCP", "ArchitectureExtensions", "ArchitectureCanvas", "ArchitectureServer",
      ], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
