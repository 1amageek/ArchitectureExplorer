import Foundation

public struct InputChunk: Codable, Sendable {
  public let path: String
  public let digest: String
  public let totalBytes: Int
  public let offset: Int
  public let data: Data
  public let eof: Bool
  public init(path: String, digest: String, totalBytes: Int, offset: Int, data: Data, eof: Bool) {
    self.path = path; self.digest = digest; self.totalBytes = totalBytes; self.offset = offset
    self.data = data; self.eof = eof
  }
}
