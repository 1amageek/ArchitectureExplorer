import ArchitectureCore

public struct CanvasEdge: Codable, Sendable, Equatable {
  public var id: String
  public var source: String
  public var target: String
  public var label: String
  public var role: String
  public var directed: Bool
  public var order: Double?
  public var details: JSONValue
  public init(id: String, source: String, target: String, label: String = "", role: String = "relation", directed: Bool = true, order: Double? = nil, details: JSONValue = .object([:])) {
    self.id = id; self.source = source; self.target = target; self.label = label; self.role = role; self.directed = directed; self.order = order; self.details = details
  }
}
