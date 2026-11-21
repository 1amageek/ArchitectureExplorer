// swift-tools-version: 6.4
import PackageDescription

let names = [
  "ArchitectureCore", "ArchitectureIR", "ArchitectureFrontend", "ArchitectureGraph",
  "ArchitectureStore", "ArchitectureIndexer", "ArchitectureService", "ArchitectureClient",
  "ArchitectureMCP", "ArchitectureExtensions", "ArchitectureCanvas",
]
let package = Package(
  name: "ArchitectureExplorer",
  platforms: [.macOS("27.0")],
  products: names.map { .library(name: $0, targets: [$0]) } + [
    .executable(name: "architecture", targets: ["architecture"])
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    .package(
      url: "https://github.com/1amageek/swift-skeleton.git",
      revision: "fb10ef666a30e892b9f3a4ca0740702c6c621d80", traits: ["rust"]),
    .package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", exact: "0.25.0"),
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
      name: "ArchitectureService", dependencies: ["ArchitectureIndexer", "ArchitectureGraph", "ArchitectureExtensions", "ArchitectureCanvas"],
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
    .testTarget(
      name: "ArchitectureTests",
      dependencies: [
        "ArchitectureCore", "ArchitectureIR", "ArchitectureFrontend", "ArchitectureGraph",
        "ArchitectureStore", "ArchitectureIndexer", "ArchitectureService", "ArchitectureClient",
        "ArchitectureMCP", "ArchitectureExtensions", "ArchitectureCanvas",
      ], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
