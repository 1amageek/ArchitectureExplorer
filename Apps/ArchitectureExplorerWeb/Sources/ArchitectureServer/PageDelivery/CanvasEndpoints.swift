import ArchitectureClient
import ArchitectureCore
import Foundation
import SwiftWebCore

struct CanvasEndpoints: Scene {
  let authority: SessionAuthority
  let client: ArchitectureClient
  var body: some Scene {
    Endpoint("/canvas", method: .post, security: .external) { request in
      guard await authority.authorizeMutation(request) else { throw Abort(.forbidden, reason: "Session, Origin or CSRF denied") }
      guard let bytes = try await request.collectedBody(), bytes.count <= 3 * 1024 * 1024 else { throw Abort(.contentTooLarge, reason: "Canvas request exceeds 3 MiB") }
      let message = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
      let allowed: Set<String> = ["canvas.open", "canvas.close", "canvas.select", "canvas.focus", "canvas.expand", "canvas.collapse", "canvas.setFilter", "canvas.setLayout", "canvas.setCamera", "canvas.setGeometry"]
      guard let method = message["method"].string, allowed.contains(method) else { throw Abort(.forbidden, reason: "Unknown Canvas operation") }
      var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
      do {
        let result = try await client.call(method, parameters: message["params"])
        let data = try CanonicalJSON.encode(result)
        return Response(status: .ok, headers: headers, body: .init(bytes: Array(data)))
      } catch {
        let typed = error as? ArchitectureError ?? ArchitectureError("CANVAS_FAILED", String(describing: error))
        let data = try CanonicalJSON.encode(JSONValue.object(["error": .object(["code": .string(typed.code), "message": .string(typed.message)])]))
        return Response(status: .badRequest, headers: headers, body: .init(bytes: Array(data)))
      }
    }
  }
}
