import ArchitectureCore
import Foundation

public struct GraphQuery: Codable, Sendable, Equatable {
  public let method: String
  public let snapshotID: String?
  public let focus: String?
  public let text: String
  public let kinds: [String]
  public let languages: [String]
  public let direction: String
  public let depth: Int
  public let limit: Int
  public let edgeLimit: Int
  public let cursor: String?
  public let level: String
  public let target: String?
  public init(
    method: String, snapshotID: String? = nil, focus: String? = nil, text: String = "",
    kinds: [String] = [], languages: [String] = [], direction: String = "outgoing", depth: Int = 2,
    limit: Int = 500, edgeLimit: Int = 1500, cursor: String? = nil, level: String = "module",
    target: String? = nil
  ) {
    self.method = method
    self.snapshotID = snapshotID
    self.focus = focus
    self.text = text
    self.kinds = kinds
    self.languages = languages
    self.direction = direction
    self.depth = depth
    self.limit = limit
    self.edgeLimit = edgeLimit
    self.cursor = cursor
    self.level = level
    self.target = target
  }
}
