import Darwin
import Foundation

/// POSIX boundary: sockaddr and buffers are stack-owned, validated and borrowed only during C calls.
/// Descriptors move once into LocalConnection or remain scoped to a listener task; each owner closes once.
public enum LocalSocket {
  public static let maximumFrameBytes = 4 * 1024 * 1024
  public static func runtimeDirectory(_ workspaceID: String) throws -> URL {
    let url = URL(fileURLWithPath: "/tmp/ae-\(getuid())-" + workspaceID.suffix(24))
    if Darwin.mkdir(url.path, 0o700) != 0, errno != EEXIST {
      throw ArchitectureError(
        "POLICY_DENIED", "Cannot create private runtime directory.", exitCode: 5)
    }
    var info = stat()
    guard lstat(url.path, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR,
      (info.st_mode & 0o077) == 0
    else {
      throw ArchitectureError("POLICY_DENIED", "Unsafe runtime directory.", exitCode: 5)
    }
    return url
  }
  private static func address<T>(
    _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
  ) throws -> T {
    var address = sockaddr_un()
    let count = MemoryLayout.size(ofValue: address.sun_path)
    let bytes = Array(path.utf8)
    guard bytes.count < count, !bytes.contains(0) else {
      throw ArchitectureError("RESOURCE_LIMIT", "Unix socket path too long.", exitCode: 6)
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      destination.initializeMemory(as: UInt8.self, repeating: 0)
      destination.copyBytes(from: bytes)
    }
    return try withUnsafePointer(to: &address) { pointer in
      try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }
  public static func create() throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ArchitectureError("CONNECTION_FAILED", "socket: \(errno)", exitCode: 6)
    }
    var value: Int32 = 1
    guard
      setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size)) == 0,
      fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0
    else {
      Darwin.close(fd)
      throw ArchitectureError("CONNECTION_FAILED", "Socket configuration failed.", exitCode: 6)
    }
    return fd
  }
  public static func listen(path: String) throws -> Int32 {
    let fd = try create()
    do {
      let result = try address(path) { Darwin.bind(fd, $0, $1) }
      guard result == 0, Darwin.listen(fd, 32) == 0, chmod(path, 0o600) == 0 else {
        throw ArchitectureError(
          "CONNECTION_FAILED", "Cannot bind private socket: \(errno)", exitCode: 6)
      }
      return fd
    } catch {
      Darwin.close(fd)
      throw error
    }
  }
  public static func connect(path: String) async throws -> LocalConnection {
    let fd = try create()
    do {
      let result = try address(path) { Darwin.connect(fd, $0, $1) }
      guard result == 0 || errno == EINPROGRESS else {
        throw ArchitectureError("CONNECTION_FAILED", "Daemon socket unavailable.", exitCode: 6)
      }
      if result != 0 {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
          var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
          let ready = Darwin.poll(&descriptor, 1, 0)
          if ready > 0 {
            var value: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &value, &size) == 0, value == 0 else {
              throw ArchitectureError(
                "CONNECTION_FAILED", "Daemon connection rejected.", exitCode: 6)
            }
            break
          }
          guard ContinuousClock.now < deadline else {
            throw ArchitectureError(
              "ANALYSIS_TIMEOUT", "Connection deadline exceeded.", exitCode: 6)
          }
          try await Task.sleep(for: .milliseconds(10))
        }
      }
      return try LocalConnection(descriptor: fd)
    } catch {
      Darwin.close(fd)
      throw error
    }
  }
  public static func accept(_ listener: Int32) throws -> LocalConnection? {
    let fd = Darwin.accept(listener, nil, nil)
    if fd < 0 {
      if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return nil }
      if errno == ECONNABORTED {
        throw ArchitectureError(
          "PEER_CONNECTION_REJECTED", "Peer aborted before accept completed.", exitCode: 5)
      }
      throw ArchitectureError("CONNECTION_FAILED", "accept: \(errno)", exitCode: 6)
    }
    do { return try LocalConnection(descriptor: fd) } catch {
      Darwin.close(fd)
      throw ArchitectureError(
        "PEER_CONNECTION_REJECTED", "Accepted peer closed or failed validation: \(error)",
        exitCode: 5)
    }
  }
}
