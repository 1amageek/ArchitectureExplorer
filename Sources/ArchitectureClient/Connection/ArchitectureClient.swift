import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ArchitectureClient: ArchitectureQueryClient {
  public let paths: WorkspacePaths
  public let extensionCredential: String?
  private let extensionAdmission: ProviderRequestAdmission?
  public init(workspace: String, extensionCredential: String? = nil) throws { paths = try WorkspacePaths(workspace); self.extensionCredential = extensionCredential; extensionAdmission = extensionCredential == nil ? nil : ProviderRequestAdmission() }
  public func call(_ method: String, parameters: JSONValue = .object([:])) async throws -> JSONValue
  {
    try await extensionAdmission?.acquire()
    let runtime = try LocalSocket.runtimeDirectory(paths.workspaceID)
    let connection = try await LocalSocket.connect(
      path: runtime.appendingPathComponent("rpc.sock").path)
    do {
      let id = UUID().uuidString
      var envelope: [String: JSONValue] = [
        "jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method),
        "params": parameters, "workspaceID": .string(paths.workspaceID),
        "protocolVersion": .string("1.0"),
      ]
      if let extensionCredential { envelope["extensionCredential"] = .string(extensionCredential) }
      try await connection.write(.object(envelope))
      guard let response = try await connection.read(), response["id"].string == id else {
        throw ArchitectureError(
          "PROTOCOL_MISMATCH", "Missing or mismatched RPC response.", exitCode: 7)
      }
      await connection.close()
      if response["error"] != .null {
        throw ArchitectureError(
          response["error"]["data"]["code"].string ?? "RPC_FAILED",
          response["error"]["message"].string ?? "Daemon request failed.",
          exitCode: Int32(response["error"]["data"]["exitCode"].int ?? 4))
      }
      return response["result"]
    } catch {
      await connection.close()
      throw error
    }
  }
  public func query(_ query: GraphQuery) async throws -> GraphView {
    let response = try await call(query.method, parameters: try JSONValue.encode(query))
    return try response.decode(GraphView.self)
  }
}
