import ArchitectureCore
import Foundation

public struct Fact: Codable, Sendable, Equatable {
  public let id: String
  public let producer: String
  public let scope: String
  public let kind: String
  public let source: String
  public let target: String
  public let revision: String
  public let evidenceIDs: [String]
  public let attributes: [String: JSONValue]
  public init(
    id: String, producer: String, scope: String, kind: String, source: String, target: String,
    revision: String, evidenceIDs: [String] = [], attributes: [String: JSONValue] = [:]
  ) {
    self.id = id
    self.producer = producer
    self.scope = scope
    self.kind = kind
    self.source = source
    self.target = target
    self.revision = revision
    self.evidenceIDs = evidenceIDs
    self.attributes = attributes
  }
}
