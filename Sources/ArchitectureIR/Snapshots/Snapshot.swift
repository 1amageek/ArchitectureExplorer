import ArchitectureCore
import Foundation

public struct Snapshot: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let id: String
  public let workspaceID: String
  public let generation: Int
  public let contextDigest: String
  public let inputs: [String: String]
  public let entities: [Entity]
  public let facts: [Fact]
  public let evidence: [Evidence]
  public let coverage: [Coverage]
  public let diagnostics: [Diagnostic]
  public let sequences: [ArchitectureSequence]?
  public let createdAt: String
  public init(
    schemaVersion: String = "1.0", id: String, workspaceID: String, generation: Int,
    contextDigest: String, inputs: [String: String], entities: [Entity], facts: [Fact],
    evidence: [Evidence], coverage: [Coverage], diagnostics: [Diagnostic] = [],
    sequences: [ArchitectureSequence]? = nil, createdAt: String = ISO8601DateFormatter().string(from: Date())
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.workspaceID = workspaceID
    self.generation = generation
    self.contextDigest = contextDigest
    self.inputs = inputs
    self.entities = entities
    self.facts = facts
    self.evidence = evidence
    self.coverage = coverage
    self.diagnostics = diagnostics
    self.sequences = sequences
    self.createdAt = createdAt
  }
}
