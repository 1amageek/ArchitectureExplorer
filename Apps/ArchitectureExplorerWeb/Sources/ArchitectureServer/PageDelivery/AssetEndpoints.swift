import ArchitectureWeb
import SwiftWebCore

struct AssetEndpoints: Scene {
  let authority: SessionAuthority
  var body: some Scene {
    Endpoint("/assets/three-c4.min.js", contentType: "application/javascript") { request in try await asset("three-c4.min.js", request: request) }
    Endpoint("/assets/c4-layout.js", contentType: "application/javascript") { request in try await asset("c4-layout.js", request: request) }
    Endpoint("/assets/c4-objects.js", contentType: "application/javascript") { request in try await asset("c4-objects.js", request: request) }
    Endpoint("/assets/c4-map.js", contentType: "application/javascript") { request in try await asset("c4-map.js", request: request) }
    Endpoint("/assets/canvas-model.js", contentType: "application/javascript") { request in try await asset("canvas-model.js", request: request) }
    Endpoint("/assets/canvas-ui.js", contentType: "application/javascript") { request in try await asset("canvas-ui.js", request: request) }
    Endpoint("/assets/explorer.css", contentType: "text/css; charset=utf-8") { request in
      try await asset("explorer.css", request: request)
    }
    Endpoint("/assets/extensions.js", contentType: "application/javascript") { request in
      try await asset("extensions.js", request: request)
    }
    Endpoint("/assets/explorer.js", contentType: "application/javascript") { request in
      try await asset("explorer.js", request: request)
    }
    Endpoint("/assets/highlight.min.js", contentType: "application/javascript") { request in
      try await asset("highlight.min.js", request: request)
    }
    Endpoint("/assets/cytoscape.min.js", contentType: "application/javascript") { request in
      try await asset("cytoscape.min.js", request: request)
    }
    Endpoint("/assets/elk.bundled.js", contentType: "application/javascript") { request in
      try await asset("elk.bundled.js", request: request)
    }
    Endpoint("/assets/elk-worker.min.js", contentType: "application/javascript") { request in
      try await asset("elk-worker.min.js", request: request)
    }
    Endpoint("/assets/layout-model.js", contentType: "application/javascript") { request in
      try await asset("layout-model.js", request: request)
    }
    Endpoint("/assets/layout-worker.js", contentType: "application/javascript") { request in
      try await asset("layout-worker.js", request: request)
    }
  }
  func asset(_ name: String, request: Request) async throws -> String {
    guard await authority.validHost(request) else {
      throw Abort(.forbidden, reason: "Host/Origin denied")
    }
    return try ExplorerPage.asset(name)
  }
}
