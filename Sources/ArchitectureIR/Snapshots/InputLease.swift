import Foundation

public struct InputLease: Codable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let workspaceID: String
  public let snapshotID: String
  public let contextDigest: String
  public let metadata: [String: String]
  public let fileCount: Int
  public let totalBytes: Int
  public let expiresAt: String
  public init(id: String, workspaceID: String, snapshotID: String, contextDigest: String,
    metadata: [String: String], fileCount: Int, totalBytes: Int, expiresAt: String) {
    schemaVersion = "1.0"; self.id = id; self.workspaceID = workspaceID; self.snapshotID = snapshotID
    self.contextDigest = contextDigest; self.metadata = metadata; self.fileCount = fileCount
    self.totalBytes = totalBytes; self.expiresAt = expiresAt
  }
}
