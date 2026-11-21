import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionContribution: Codable, Sendable, Equatable {
  public let id: String
  public let kind: String
  public let binding: ExtensionBinding
  public let data: JSONValue
  public init(id: String, kind: String, binding: ExtensionBinding, data: JSONValue) { self.id = id; self.kind = kind; self.binding = binding; self.data = data }
  public var digest: String { get throws { CanonicalJSON.digest(try CanonicalJSON.encode(self)) } }
}
