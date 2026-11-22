// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ArchitectureExplorerWeb", platforms: [.macOS("27.0")],
  products: [.executable(name: "architecture-web", targets: ["architecture-web"])],
  dependencies: [
    .package(url: "https://github.com/1amageek/ArchitectureExplorer.git", exact: "0.1.4"),
  ],
  targets: [
    .executableTarget(
      name: "architecture-web",
      dependencies: [.product(name: "ArchitectureServer", package: "ArchitectureExplorer")],
      exclude: ["DESIGN.md", "Commands/DESIGN.md"]),
  ], swiftLanguageModes: [.v6])
