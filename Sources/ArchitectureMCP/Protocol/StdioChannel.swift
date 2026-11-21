import ArchitectureCore
import Darwin
import Foundation

actor StdioChannel {
  private var pending = Data()
  init() throws {
    guard fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK) == 0 else {
      throw ArchitectureError("STDIO_FAILED", "Cannot configure protocol stdin.")
    }
  }
  func read() async throws -> JSONValue? {
    var bytes = [UInt8](repeating: 0, count: 8192)
    while true {
      try Task.checkCancellation()
      if let end = pending.firstIndex(of: 10) {
        let line = pending[..<end]
        let value = try JSONDecoder().decode(JSONValue.self, from: line)
        pending.removeSubrange(...end)
        return value
      }
      guard pending.count < 1024 * 1024 else {
        throw ArchitectureError("RESOURCE_LIMIT", "MCP input exceeds 1 MiB.", exitCode: 6)
      }
      let count = bytes.withUnsafeMutableBytes {
        Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
      }
      if count > 0 {
        pending.append(contentsOf: bytes.prefix(count))
        continue
      }
      if count == 0 {
        guard pending.isEmpty else {
          throw ArchitectureError("INVALID_REQUEST", "Truncated MCP frame.", exitCode: 2)
        }
        return nil
      }
      guard errno == EAGAIN || errno == EINTR else {
        throw ArchitectureError("STDIO_FAILED", "Protocol stdin read failed.")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
  func write(_ value: JSONValue) throws {
    var bytes = try CanonicalJSON.encode(value)
    bytes.append(10)
    FileHandle.standardOutput.write(bytes)
  }
}
