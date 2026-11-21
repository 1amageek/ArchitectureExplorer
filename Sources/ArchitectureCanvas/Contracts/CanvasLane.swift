public struct CanvasLane: Codable, Sendable, Equatable {
  public var id: String
  public var label: String
  public init(id: String, label: String? = nil) { self.id = id; self.label = label ?? id }
}
