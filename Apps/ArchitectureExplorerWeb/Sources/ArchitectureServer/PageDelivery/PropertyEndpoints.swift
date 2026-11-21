import ArchitectureClient
import ArchitectureCore
import Foundation
import SwiftWebCore

struct PropertyEndpoints: Scene {
  let authority: SessionAuthority
  let client: ArchitectureClient

  let threadID: UUID

  var body: some Scene {
    Endpoint("/properties", method: .post, security: .external) { request in
      guard await authority.authorizeMutation(request) else { throw Abort(.forbidden, reason: "Session, Origin or CSRF denied") }
      guard let bytes = try await request.collectedBody(), bytes.count <= 2048 else { throw Abort(.badRequest, reason: "Invalid property request") }
      let message = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
      guard message["threadID"].string == threadID.uuidString.lowercased() else {
        throw Abort(.forbidden, reason: "The requesting conversation does not own this session")
      }
      var headers = HTTPFields()
      headers[.contentType] = "application/json"
      headers[.cacheControl] = "no-store"
      if message["connect"].bool == true {
        return Response(status: .ok, headers: headers, body: .init(string: "{}"))
      }
      do {
        guard let entity = message["entityID"].string, let snapshot = message["snapshotID"].string,
          message["workspaceID"].string == client.paths.workspaceID else { throw ArchitectureError("INVALID_ARGUMENT", "Select a node in this workspace.") }
        let context = try await client.call("properties.context", parameters: .object(["snapshotID": .string(snapshot), "entityID": .string(entity)]))
        return Response(status: .ok, headers: headers, body: .init(bytes: Array(try CanonicalJSON.encode(context))))
      } catch {
        let error = error as? ArchitectureError ?? ArchitectureError("ANALYSIS_FAILED", String(describing: error))
        return Response(status: .badRequest, headers: headers, body: .init(bytes: Array(try CanonicalJSON.encode(JSONValue.object(["error": .string(error.description)])))))
      }
    }
  }
}
