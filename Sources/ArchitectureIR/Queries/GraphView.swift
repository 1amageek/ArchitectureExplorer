import ArchitectureCore
import Foundation

public struct GraphView: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workspaceID: String
  public let snapshotID: String
  public let queryID: String
  public let freshness: String
  public let completeness: String
  public let nodes: [Entity]
  public let edges: [Fact]
  public let evidence: [Evidence]
  public let coverage: [Coverage]
  public let truncated: Bool
  public let nextCursor: String?
  public let diagnostics: [Diagnostic]
  public let extensions: [String: JSONValue]?
  public init(
    schemaVersion: String = "1.0", workspaceID: String, snapshotID: String, queryID: String,
    freshness: String, completeness: String, nodes: [Entity], edges: [Fact],
    evidence: [Evidence] = [], coverage: [Coverage] = [], truncated: Bool = false,
    nextCursor: String? = nil, diagnostics: [Diagnostic] = [], extensions: [String: JSONValue]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.workspaceID = workspaceID
    self.snapshotID = snapshotID
    self.queryID = queryID
    self.freshness = freshness
    self.completeness = completeness
    self.nodes = nodes
    self.edges = edges
    self.evidence = evidence
    self.coverage = coverage
    self.truncated = truncated
    self.nextCursor = nextCursor
    self.diagnostics = diagnostics
    self.extensions = extensions
  }
}
