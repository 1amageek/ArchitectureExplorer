// swift-tools-version: 6.4
import PackageDescription
// Optional consumer-side integration probe. The Explorer package never depends on Invar.
let package = Package(name: "InvarReaderProbe", platforms: [.macOS("27.0")], dependencies: [.package(path: "../.."), .package(path: "../../../Invar")], targets: [.executableTarget(name: "InvarReaderProbe", dependencies: [.product(name: "ArchitectureClient", package: "ArchitectureExplorer"), .product(name: "ArchitectureExtensions", package: "ArchitectureExplorer"), .product(name: "VerificationExplorer", package: "Invar")], exclude: ["DESIGN.md"])])
