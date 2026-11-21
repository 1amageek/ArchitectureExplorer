import ArchitectureCore
import Foundation

public struct GraphDelta: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workspaceID: String
  public let streamEpoch: String
  public let sequence: Int
  public let queryID: String
  public let baseSnapshotID: String
  public let targetSnapshotID: String
  public let upsertNodes: [Entity]
  public let removeNodeIDs: [String]
  public let upsertEdges: [Fact]
  public let removeEdgeIDs: [String]
  public let coverageChanged: Bool
  public init(
    schemaVersion: String = "1.0", workspaceID: String, streamEpoch: String, sequence: Int,
    queryID: String, baseSnapshotID: String, targetSnapshotID: String, upsertNodes: [Entity],
    removeNodeIDs: [String], upsertEdges: [Fact], removeEdgeIDs: [String], coverageChanged: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.workspaceID = workspaceID
    self.streamEpoch = streamEpoch
    self.sequence = sequence
    self.queryID = queryID
    self.baseSnapshotID = baseSnapshotID
    self.targetSnapshotID = targetSnapshotID
    self.upsertNodes = upsertNodes
    self.removeNodeIDs = removeNodeIDs
    self.upsertEdges = upsertEdges
    self.removeEdgeIDs = removeEdgeIDs
    self.coverageChanged = coverageChanged
  }
}
