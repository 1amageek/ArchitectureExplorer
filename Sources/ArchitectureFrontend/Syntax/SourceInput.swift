import ArchitectureCore
import ArchitectureIR
import Foundation

public struct SourceInput: Sendable {
  public let workspaceID: String
  public let path: String
  public let language: String
  public let bytes: Data
  public let digest: String
  public let contextDigest: String
  public let generation: Int
  public init(
    workspaceID: String, path: String, language: String, bytes: Data, contextDigest: String,
    generation: Int
  ) {
    self.workspaceID = workspaceID
    self.path = path
    self.language = language
    self.bytes = bytes
    digest = CanonicalJSON.digest(bytes)
    self.contextDigest = contextDigest
    self.generation = generation
  }
  public func anchor(_ start: Int, _ end: Int) -> SourceAnchor {
    SourceAnchor(path: path, digest: digest, startByte: start, endByte: end)
  }
  public func text(_ node: SyntaxNode) -> String {
    String(decoding: bytes[node.start..<node.end], as: UTF8.self)
  }
}
