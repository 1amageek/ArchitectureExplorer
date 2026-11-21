// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "ExtensionMock", platforms: [.macOS("27.0")], dependencies: [.package(path: "../..")], targets: [.executableTarget(name: "ExtensionMock", dependencies: [.product(name: "ArchitectureClient", package: "ArchitectureExplorer"), .product(name: "ArchitectureExtensions", package: "ArchitectureExplorer")], exclude: ["DESIGN.md"])])
