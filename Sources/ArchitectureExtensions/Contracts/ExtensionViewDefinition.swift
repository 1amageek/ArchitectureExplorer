import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionViewDefinition: Codable, Sendable, Equatable {
  public let id: String
  public let kind: String
  public let title: String
  public init(id: String, kind: String, title: String) { self.id = id; self.kind = kind; self.title = title }
}
