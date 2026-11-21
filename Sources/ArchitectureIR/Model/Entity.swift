import ArchitectureCore
import Foundation

public struct Entity: Codable, Sendable, Equatable {
  public let id: String
  public let kind: String
  public let language: String
  public let name: String
  public let identityKey: String
  public let entityRevision: String
  public let anchor: SourceAnchor?
  public let attributes: [String: JSONValue]
  public init(
    id: String, kind: String, language: String, name: String, identityKey: String,
    entityRevision: String, anchor: SourceAnchor? = nil, attributes: [String: JSONValue] = [:]
  ) {
    self.id = id
    self.kind = kind
    self.language = language
    self.name = name
    self.identityKey = identityKey
    self.entityRevision = entityRevision
    self.anchor = anchor
    self.attributes = attributes
  }
}
