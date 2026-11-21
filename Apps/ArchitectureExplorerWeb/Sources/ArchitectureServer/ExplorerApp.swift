import ArchitectureClient
import ArchitectureCore
import ArchitectureFrontend
import ArchitectureWeb
import Foundation
import SwiftWebCore

struct ExplorerApp: App {
  let authority: SessionAuthority
  let client: ArchitectureClient
  let collection: RepositoryMap?
  let threadID: UUID?
  init() {
    threadID = nil
    collection = nil
    authority = SessionAuthority(port: 0)
    do {
      client = try ArchitectureClient(workspace: FileManager.default.currentDirectoryPath)
    } catch { preconditionFailure("An App requires a valid workspace: \(error)") }
  }
  init(authority: SessionAuthority, client: ArchitectureClient, collection: RepositoryMap? = nil, threadID: UUID? = nil) {
    self.threadID = threadID
    self.collection = collection
    self.authority = authority
    self.client = client
  }
  var body: some Scene {
    Endpoint("/", contentType: "text/html; charset=utf-8") { request in
      guard await authority.validHost(request) else {
        throw Abort(.forbidden, reason: "Host/Origin denied")
      }
      return try ExplorerPage.render(repositoryMode: collection != nil)
    }
    Endpoint("/session", method: .post, security: .external) { request in
      guard let bytes = try await request.collectedBody(), bytes.count <= 1024 else {
        throw Abort(.badRequest, reason: "Invalid session request")
      }
      let value = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
      do {
        let session = try await authority.exchange(value["token"].string ?? "", request: request)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        headers[.setCookie] =
          "\(authority.cookieName)=\(session); Path=/; HttpOnly; SameSite=Strict; Max-Age=43200"
        headers[.cacheControl] = "no-store"
        return Response(status: .ok, headers: headers, body: .init(string: "{}"))
      } catch { throw Abort(.forbidden, reason: "Launch authentication denied") }
    }
    Endpoint("/api") { request in
      guard await authority.authorize(request) else {
        throw Abort(.forbidden, reason: "Session/Host/Origin denied")
      }
      if let collection {
        guard request.queryParameters.rawValue("method") == "repository.browse" else {
          throw Abort(.badRequest, reason: "Source-index operations are unavailable in repository-map mode")
        }
        let raw = request.queryParameters.rawValue("params") ?? "{}"
        guard raw.utf8.count <= 8192 else { throw Abort(.contentTooLarge, reason: "Scope path exceeds request budget") }
        let params = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        do {
          let scope = try RepositoryArchitecture.view(map: collection, parameters: params)
          let data = try CanonicalJSON.encode(scope)
          var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
          return Response(status: .ok, headers: headers, body: .init(bytes: Array(data)))
        } catch {
          let data = try CanonicalJSON.encode(JSONValue.object(["error": .object(["message": .string(String(describing: error))])]))
          var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
          return Response(status: .badRequest, headers: headers, body: .init(bytes: Array(data)))
        }
      }
      if request.queryParameters.rawValue("method") == "host.context", let context = await authority.context(request) {
        var fields = context.object
        if threadID != nil { fields["propertyActions"] = .bool(true) }
        let bytes = try CanonicalJSON.encode(JSONValue.object(fields))
        var headers = HTTPFields(); headers[.contentType] = "application/json"; headers[.cacheControl] = "no-store"
        return Response(status: .ok, headers: headers, body: .init(bytes: Array(bytes)))
      }
      let allowed: Set<String> = [
        "canvas.list", "canvas.get", "canvas.export", "workspace.status", "graph.overview", "graph.children", "graph.node", "graph.neighbors",
        "graph.search", "graph.path", "graph.impact", "graph.cfg", "graph.diff", "graph.explain",
        "graph.evidence", "graph.annotations", "graph.capabilities", "source.read", "events.poll",
        "graph.export", "extensionGraphs.list", "extensions.list", "extensions.pending", "extensions.view", "inputs.manifest",
      ]
      guard let method = request.queryParameters.rawValue("method"), allowed.contains(method) else {
        throw Abort(.badRequest, reason: "Unknown read-only method")
      }
      let raw = request.queryParameters.rawValue("params") ?? "{}"
      guard raw.utf8.count <= 32768 else {
        throw Abort(.contentTooLarge, reason: "Query budget exceeded")
      }
      let params = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
      var headers = HTTPFields()
      headers[.contentType] = "application/json"
      headers[.cacheControl] = "no-store"
      do {
        let result = try await client.call(method, parameters: params)
        let data = try CanonicalJSON.encode(result)
        return Response(status: .ok, headers: headers, body: .init(bytes: Array(data)))
      } catch {
        let typed =
          error as? ArchitectureError
          ?? ArchitectureError("REQUEST_FAILED", String(describing: error))
        let data = try CanonicalJSON.encode(
          JSONValue.object([
            "error": .object(["code": .string(typed.code), "message": .string(typed.message)])
          ]))
        return Response(status: .badRequest, headers: headers, body: .init(bytes: Array(data)))
      }
    }
    if collection == nil {
      if let threadID { PropertyEndpoints(authority: authority, client: client, threadID: threadID) }
      CanvasEndpoints(authority: authority, client: client)
      ExtensionEndpoints(authority: authority, client: client)
    }
    Endpoint("/events") { _ in
      throw Abort(.forbidden, reason: "Authenticated WebSocket upgrade is required")
    }
    AssetEndpoints(authority: authority)
  }
}
