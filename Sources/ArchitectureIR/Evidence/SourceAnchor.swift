import ArchitectureCore
import Foundation

public struct SourceAnchor: Codable, Sendable, Equatable {
  public let path: String
  public let digest: String
  public let startByte: Int
  public let endByte: Int
  public init(path: String, digest: String, startByte: Int, endByte: Int) {
    self.path = path
    self.digest = digest
    self.startByte = startByte
    self.endByte = endByte
  }
}
