// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "ExtensionMock", platforms: [.macOS("27.0")], dependencies: [.package(url: "https://github.com/1amageek/ArchitectureExplorer.git", exact: "0.1.1")], targets: [.executableTarget(name: "ExtensionMock", dependencies: [.product(name: "ArchitectureClient", package: "ArchitectureExplorer"), .product(name: "ArchitectureExtensions", package: "ArchitectureExplorer")], exclude: ["DESIGN.md"])])
