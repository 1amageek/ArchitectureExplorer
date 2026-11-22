// swift-tools-version: 6.4
import PackageDescription
// Optional consumer-side integration probe. The Explorer package never depends on Invar.
let package = Package(name: "InvarReaderProbe", platforms: [.macOS("27.0")], dependencies: [.package(url: "https://github.com/1amageek/ArchitectureExplorer.git", exact: "0.1.4"), .package(url: "https://github.com/1amageek/Invar.git", exact: "0.1.5")], targets: [.executableTarget(name: "InvarReaderProbe", dependencies: [.product(name: "ArchitectureClient", package: "ArchitectureExplorer"), .product(name: "ArchitectureExtensions", package: "ArchitectureExplorer"), .product(name: "VerificationExplorer", package: "Invar")], exclude: ["DESIGN.md"])])
