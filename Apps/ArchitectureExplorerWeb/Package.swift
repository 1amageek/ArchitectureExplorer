// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ArchitectureExplorerWeb", platforms: [.macOS("27.0")],
  products: [
    .library(name: "ArchitectureWeb", targets: ["ArchitectureWeb"]),
    .library(name: "ArchitectureServer", targets: ["ArchitectureServer"]),
    .executable(name: "architecture-web", targets: ["architecture-web"]),
  ],
  dependencies: [
    .package(path: "../.."),
    .package(
      url: "https://github.com/1amageek/swift-web.git",
      revision: "6edadb6cfa92e3a4b26a1e669329be38f45212f4"),
    .package(url: "https://github.com/1amageek/swift-html.git", from: "0.16.1"),
    .package(url: "https://github.com/apple/swift-collections.git", exact: "1.7.1"),
    .package(url: "https://github.com/apple/swift-http-api-proposal.git", exact: "0.3.0"),
    .package(url: "https://github.com/swift-server/swift-http-server", exact: "0.1.0"),
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.105.0"),
    .package(url: "https://github.com/apple/swift-nio-extras.git", exact: "1.35.2"),
    .package(url: "https://github.com/1amageek/swift-tls.git", exact: "2.1.0"),
    .package(url: "https://github.com/1amageek/swift-tls-nio.git", exact: "0.1.1"),
    .package(url: "https://github.com/apple/swift-log.git", exact: "1.17.0"),
    .package(url: "https://github.com/apple/swift-http-types", exact: "1.8.0"),
  ],
  targets: [
    .target(
      name: "ArchitectureHTTPHost",
      dependencies: [
        .product(name: "BasicContainers", package: "swift-collections"),
        .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
        .product(name: "NIOHTTPServer", package: "swift-http-server"),
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
      ], exclude: ["DESIGN.md", "Runtime/DESIGN.md", "Runtime/UPSTREAM-LICENSE"],
      swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
    .target(
      name: "ArchitectureWeb", dependencies: [.product(name: "SwiftHTML", package: "swift-html")],
      exclude: ["DESIGN.md", "Page/DESIGN.md"], resources: [.copy("Assets")]),
    .target(
      name: "ArchitectureServer",
      dependencies: [
        .product(name: "ArchitectureFrontend", package: "ArchitectureExplorer"),
        "ArchitectureWeb", .product(name: "ArchitectureClient", package: "ArchitectureExplorer"),
        .product(name: "ArchitectureCore", package: "ArchitectureExplorer"),
        .product(name: "SwiftWebCore", package: "swift-web"), "ArchitectureHTTPHost",
      ], exclude: ["DESIGN.md", "Hosting/DESIGN.md", "Session/DESIGN.md", "PageDelivery/DESIGN.md"]),
    .executableTarget(
      name: "architecture-web", dependencies: ["ArchitectureServer"],
      exclude: ["DESIGN.md", "Commands/DESIGN.md"]),
  ], swiftLanguageModes: [.v6])
