// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "Example", platforms: [.macOS("27.0")], products: [.library(name: "Example", targets: ["Example"])], targets: [.target(name: "Example")])
