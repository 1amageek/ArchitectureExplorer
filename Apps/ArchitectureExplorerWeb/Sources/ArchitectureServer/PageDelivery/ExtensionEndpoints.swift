import ArchitectureClient
import ArchitectureCore
import Foundation
import SwiftWebCore

struct ExtensionEndpoints: Scene {
  let authority: SessionAuthority
  let client: ArchitectureClient
  var body: some Scene {
    Endpoint("/extensions", method: .post, security: .external) { request in
      guard await authority.authorizeMutation(request) else { throw Abort(.forbidden, reason: "Session, Origin or CSRF denied") }
      guard let bytes = try await request.collectedBody(), bytes.count <= 65536 else { throw Abort(.contentTooLarge, reason: "Extension request exceeds 64 KiB") }
      let message = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
      let allowed: Set<String> = ["extensions.approve", "extensions.permissions", "extensions.disconnect", "extensions.unregister", "actions.prepare", "actions.confirm"]
      guard let method = message["method"].string, allowed.contains(method) else { throw Abort(.forbidden, reason: "Unknown host extension operation") }
      var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
      do {
        let result = try await client.call(method, parameters: message["params"])
        let data = try CanonicalJSON.encode(result)
        return Response(status: .ok, headers: headers, body: .init(bytes: Array(data)))
      } catch {
        let typed = error as? ArchitectureError ?? ArchitectureError("REQUEST_FAILED", String(describing: error))
        let data = try CanonicalJSON.encode(JSONValue.object(["error": .object(["code": .string(typed.code), "message": .string(typed.message)])]))
        return Response(status: .badRequest, headers: headers, body: .init(bytes: Array(data)))
      }
    }
  }
}
