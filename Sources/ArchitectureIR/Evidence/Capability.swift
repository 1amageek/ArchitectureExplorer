import ArchitectureCore
import Foundation

public struct Capability: Codable, Sendable, Equatable {
  public let language: String
  public let producer: String
  public let feature: String
  public let supported: Bool
  public let scope: String
  public let reason: String
  public init(
    language: String, producer: String, feature: String, supported: Bool, scope: String,
    reason: String
  ) {
    self.language = language
    self.producer = producer
    self.feature = feature
    self.supported = supported
    self.scope = scope
    self.reason = reason
  }
}
