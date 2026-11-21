import Darwin
import Foundation

public actor LocalConnection {
  private var descriptor: Int32
  private var pending = Data()
  public init(descriptor: Int32) throws {
    var peerUser: uid_t = 0
    var peerGroup: gid_t = 0
    guard getpeereid(descriptor, &peerUser, &peerGroup) == 0, peerUser == getuid() else {
      throw ArchitectureError(
        "POLICY_DENIED", "Unix socket peer must have the same user identity.", exitCode: 5)
    }
    guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0, fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0
    else {
      throw ArchitectureError("CONNECTION_FAILED", "Cannot configure connection.", exitCode: 6)
    }
    var value: Int32 = 1
    guard
      setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
        == 0
    else {
      throw ArchitectureError(
        "CONNECTION_FAILED", "Cannot configure SIGPIPE handling.", exitCode: 6)
    }
    self.descriptor = descriptor
  }
  deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
  public func peerIdentity() throws -> ConnectionPeer {
    guard descriptor >= 0 else { throw ArchitectureError("CONNECTION_FAILED", "Connection closed.", exitCode: 6) }
    return try ConnectionPeer.read(descriptor)
  }
  public func close() {
    if descriptor >= 0 {
      Darwin.close(descriptor)
      descriptor = -1
    }
    pending.removeAll()
  }
  public func write(_ value: JSONValue, timeout: Duration = .seconds(30)) async throws {
    var data = try CanonicalJSON.encode(value)
    guard data.count <= LocalSocket.maximumFrameBytes else {
      throw ArchitectureError("RESOURCE_LIMIT", "IPC response exceeds 4 MiB.", exitCode: 6)
    }
    data.append(10)
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var offset = 0
    while offset < data.count {
      try Task.checkCancellation()
      guard descriptor >= 0 else {
        throw ArchitectureError("CONNECTION_FAILED", "Connection closed.", exitCode: 6)
      }
      let sent = data.withUnsafeBytes { bytes in
        Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
      }
      if sent > 0 {
        offset += sent
        continue
      }
      guard sent < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else {
        throw ArchitectureError("CONNECTION_FAILED", "Socket write failed.", exitCode: 6)
      }
      guard ContinuousClock.now < deadline else {
        throw ArchitectureError("ANALYSIS_TIMEOUT", "Socket write timed out.", exitCode: 6)
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
  public func read(timeout: Duration = .seconds(30)) async throws -> JSONValue? {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
      try Task.checkCancellation()
      if let end = pending.firstIndex(of: 10) {
        let line = pending[..<end]
        let value = try JSONDecoder().decode(JSONValue.self, from: line)
        pending.removeSubrange(...end)
        return value
      }
      guard pending.count <= LocalSocket.maximumFrameBytes else {
        throw ArchitectureError("RESOURCE_LIMIT", "IPC input exceeds 4 MiB.", exitCode: 6)
      }
      guard descriptor >= 0 else { return nil }
      let count = buffer.withUnsafeMutableBytes {
        Darwin.recv(descriptor, $0.baseAddress, $0.count, 0)
      }
      if count > 0 {
        pending.append(contentsOf: buffer.prefix(count))
        continue
      }
      if count == 0 {
        guard pending.isEmpty else {
          throw ArchitectureError("INVALID_REQUEST", "Truncated IPC frame.", exitCode: 2)
        }
        return nil
      }
      guard errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else {
        throw ArchitectureError("CONNECTION_FAILED", "Socket read failed.", exitCode: 6)
      }
      guard ContinuousClock.now < deadline else {
        throw ArchitectureError("ANALYSIS_TIMEOUT", "Socket read timed out.", exitCode: 6)
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}
