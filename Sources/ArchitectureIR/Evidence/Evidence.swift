import ArchitectureCore
import Foundation

public struct Evidence: Codable, Sendable, Equatable {
  public let id: String
  public let producer: String
  public let version: String
  public let inputDigest: String
  public let contextDigest: String
  public let basis: String
  public let freshness: String
  public let anchor: SourceAnchor?
  public let diagnostics: [Diagnostic]
  public init(
    id: String, producer: String, version: String = "1.0", inputDigest: String,
    contextDigest: String, basis: String = "syntax", freshness: String = "current",
    anchor: SourceAnchor? = nil, diagnostics: [Diagnostic] = []
  ) {
    self.id = id
    self.producer = producer
    self.version = version
    self.inputDigest = inputDigest
    self.contextDigest = contextDigest
    self.basis = basis
    self.freshness = freshness
    self.anchor = anchor
    self.diagnostics = diagnostics
  }
}
