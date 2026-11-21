import ArchitectureCore

public struct SnapshotPage: Codable, Sendable {
  public let schemaVersion: String
  public let workspaceID: String
  public let snapshotID: String
  public let collection: String
  public let records: [JSONValue]
  public let total: Int
  public let nextCursor: String?
  public init(workspaceID: String, snapshotID: String, collection: String, records: [JSONValue], total: Int, nextCursor: String?) {
    schemaVersion = "1.0"; self.workspaceID = workspaceID; self.snapshotID = snapshotID
    self.collection = collection; self.records = records; self.total = total; self.nextCursor = nextCursor
  }
}
