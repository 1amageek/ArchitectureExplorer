import ArchitectureCore

public struct CanvasNode: Codable, Sendable, Equatable {
  public var id: String
  public var label: String
  public var role: String
  public var language: String?
  public var parentID: String?
  public var laneID: String?
  public var order: Double?
  public var details: JSONValue
  public var source: JSONValue
  public init(id: String, label: String? = nil, role: String = "node", language: String? = nil, parentID: String? = nil, laneID: String? = nil, order: Double? = nil, details: JSONValue = .object([:]), source: JSONValue = .null) {
    self.id = id; self.label = label ?? id; self.role = role; self.language = language; self.parentID = parentID; self.laneID = laneID; self.order = order; self.details = details; self.source = source
  }
}
