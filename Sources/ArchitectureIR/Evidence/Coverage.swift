import ArchitectureCore
import Foundation

public struct Coverage: Codable, Sendable, Equatable {
  public let producer: String
  public let scope: String
  public let language: String
  public let freshness: String
  public let completeness: String
  public let exclusions: [String]
  public let diagnostics: [Diagnostic]
  public init(
    producer: String, scope: String, language: String, freshness: String = "current",
    completeness: String = "partial", exclusions: [String] = [], diagnostics: [Diagnostic] = []
  ) {
    self.producer = producer
    self.scope = scope
    self.language = language
    self.freshness = freshness
    self.completeness = completeness
    self.exclusions = exclusions
    self.diagnostics = diagnostics
  }
}
