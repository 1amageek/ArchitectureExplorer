import ArchitectureCore
import ArchitectureIR

extension ArchitectureClient: ArchitectureSnapshotReading {
  public func acquireInputs(snapshotID: String? = nil, maximumBytes: Int = 64 * 1024 * 1024, ttl: Int = 60) async throws -> InputLease {
    var params: [String: JSONValue] = ["maximumBytes": .number(Double(maximumBytes)), "ttl": .number(Double(ttl))]
    if let snapshotID { params["snapshotID"] = .string(snapshotID) }
    let response = try await call("inputs.acquire", parameters: .object(params))
    let result = try response.decode(InputLease.self)
    guard result.schemaVersion == "1.0", result.workspaceID == paths.workspaceID else {
      throw ArchitectureError("PROTOCOL_MISMATCH", "Input lease belongs to another workspace or schema.", exitCode: 7)
    }
    return result
  }
  public func scanSnapshot(snapshotID: String, leaseID: String? = nil, collection: String, cursor: String? = nil, limit: Int = 100) async throws -> SnapshotPage {
    var params: [String: JSONValue] = ["snapshotID": .string(snapshotID), "collection": .string(collection), "limit": .number(Double(limit))]
    if let leaseID { params["leaseID"] = .string(leaseID) }; if let cursor { params["cursor"] = .string(cursor) }
    let response = try await call("graph.scan", parameters: .object(params))
    let result = try response.decode(SnapshotPage.self)
    guard result.schemaVersion == "1.0", result.workspaceID == paths.workspaceID, result.snapshotID == snapshotID, result.collection == collection else {
      throw ArchitectureError("PROTOCOL_MISMATCH", "Raw scan changed workspace/snapshot/collection.", exitCode: 7)
    }
    return result
  }
  public func readInput(leaseID: String, path: String, offset: Int = 0, count: Int = 262144) async throws -> InputChunk {
    let response = try await call("inputs.read", parameters: .object(["leaseID": .string(leaseID), "path": .string(path), "offset": .number(Double(offset)), "count": .number(Double(count))]))
    let result = try response.decode(InputChunk.self)
    guard result.path == path, result.offset == offset, result.data.count <= count,
      result.totalBytes >= offset, result.data.count <= result.totalBytes - offset,
      result.eof == (result.data.count == result.totalBytes - offset) else {
      throw ArchitectureError("PROTOCOL_MISMATCH", "Invalid captured input chunk.", exitCode: 7)
    }
    return result
  }
  public func releaseInputs(leaseID: String) async throws {
    let response = try await call("inputs.release", parameters: .object(["leaseID": .string(leaseID)]))
    guard response["released"].bool != nil else { throw ArchitectureError("PROTOCOL_MISMATCH", "Invalid lease release response.", exitCode: 7) }
  }
}
