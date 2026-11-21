import ArchitectureCore
import Darwin
import Foundation

/// One request session owns its child, framing and nonblocking pipe descriptors.
public actor LSPProcess {
  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private var pending = Data(), nextID = 0
  private var operationBusy = false
  private var stopping = false
  private var closed = false
  private var shutdownTask: Task<Void, any Error>?

  public init(executable: String, workspace: URL) throws {
    guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
      throw ArchitectureError(
        "UNSUPPORTED_CAPABILITY", "Explicit absolute provider executable is unavailable.",
        exitCode: 3)
    }
    process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.currentDirectoryURL = workspace
    process.arguments = []
    process.environment = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LANG": "en_US.UTF-8",
      "CARGO_NET_OFFLINE": "true", "RUSTUP_OFFLINE": "1",
      "SOURCEKIT_LSP_BACKGROUND_INDEXING": "false",
    ]
    let write = Pipe()
    let read = Pipe()
    input = write.fileHandleForWriting
    output = read.fileHandleForReading
    process.standardInput = write
    process.standardOutput = read
    process.standardError = FileHandle.nullDevice
    // Configure before launch so a configuration failure cannot orphan a running child.
    guard fcntl(input.fileDescriptor, F_SETFL, O_NONBLOCK) == 0,
      fcntl(output.fileDescriptor, F_SETFL, O_NONBLOCK) == 0,
      fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) == 0
    else {
      throw ArchitectureError("PROCESS_FAILED", "Cannot configure nonblocking provider pipes.")
    }
    try process.run()
  }

  public func notify(_ method: String, params: JSONValue, timeout: Duration = .seconds(15))
    async throws
  {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    try await acquireOperation(until: deadline)
    defer { operationBusy = false }
    try await write(
      .object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]),
      until: deadline)
  }

  public func request(_ method: String, params: JSONValue, timeout: Duration = .seconds(15))
    async throws -> JSONValue
  {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    try await acquireOperation(until: deadline)
    defer { operationBusy = false }
    return try await exchange(method, params: params, until: deadline)
  }

  private func check(_ deadline: ContinuousClock.Instant, closing: Bool = false) throws {
    try Task.checkCancellation()
    guard !closed, !stopping || closing, process.isRunning else {
      throw ArchitectureError("PROCESS_FAILED", "Language provider session is stopping or exited.")
    }
    guard ContinuousClock.now < deadline else {
      throw ArchitectureError(
        "ANALYSIS_TIMEOUT", "Language provider operation timed out.", exitCode: 6)
    }
  }

  private func acquireOperation(until deadline: ContinuousClock.Instant, closing: Bool = false)
    async throws
  {
    while true {
      try check(deadline, closing: closing)
      if !operationBusy {
        operationBusy = true
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  private func write(
    _ message: JSONValue, until deadline: ContinuousClock.Instant, closing: Bool = false
  ) async throws {
    try check(deadline, closing: closing)
    let payload = try CanonicalJSON.encode(message)
    guard payload.count <= 8 * 1024 * 1024 else {
      throw ArchitectureError("RESOURCE_LIMIT", "Provider input exceeds 8 MiB.", exitCode: 6)
    }
    var frame = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
    frame.reserveCapacity(frame.count + payload.count)
    frame.append(payload)
    var offset = 0
    defer { if offset > 0, offset < frame.count { stopping = true } }
    while offset < frame.count {
      try check(deadline, closing: closing)
      // The frame owns initialized bytes. This bounded borrow never escapes the synchronous write.
      let count = frame.withUnsafeBytes { bytes in
        Darwin.write(
          input.fileDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
      }
      if count > 0 {
        offset += count
        continue
      }
      guard count < 0, errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else {
        throw ArchitectureError("PROCESS_FAILED", "Provider pipe write failed.")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  private func exchange(
    _ method: String, params: JSONValue, until deadline: ContinuousClock.Instant,
    closing: Bool = false
  ) async throws -> JSONValue {
    nextID += 1
    let id = nextID
    try await write(
      .object([
        "jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method),
        "params": params,
      ]), until: deadline, closing: closing)
    while true {
      try check(deadline, closing: closing)
      if let message = try nextMessage() {
        if message["id"].int == id {
          guard message["error"] == .null else {
            throw ArchitectureError(
              "PROVIDER_REQUEST_FAILED",
              message["error"]["message"].string ?? "Provider rejected request.", exitCode: 3)
          }
          return message["result"]
        }
        if message["method"].string != nil, message["id"] != .null {
          try await write(
            .object([
              "jsonrpc": .string("2.0"), "id": message["id"],
              "error": .object([
                "code": .number(-32601), "message": .string("Client method is not supported"),
              ]),
            ]), until: deadline, closing: closing)
        }
      } else {
        try await Task.sleep(for: .milliseconds(5))
      }
    }
  }

  private func nextMessage() throws -> JSONValue? {
    var bytes = [UInt8](repeating: 0, count: 65536)
    let count = bytes.withUnsafeMutableBytes {
      Darwin.read(output.fileDescriptor, $0.baseAddress, $0.count)
    }
    if count > 0 {
      pending.append(contentsOf: bytes.prefix(count))
    } else if count < 0, errno != EAGAIN, errno != EINTR {
      throw ArchitectureError("PROCESS_FAILED", "Provider pipe read failed.")
    } else if count == 0, pending.isEmpty {
      throw ArchitectureError("PROCESS_FAILED", "Provider output closed without a response.")
    }
    guard pending.count <= 8 * 1024 * 1024 else {
      throw ArchitectureError("RESOURCE_LIMIT", "Provider response exceeds 8 MiB.", exitCode: 6)
    }
    guard let separator = pending.range(of: Data([13, 10, 13, 10])) else { return nil }
    let header = String(decoding: pending[..<separator.lowerBound], as: UTF8.self)
    let lengths = header.components(separatedBy: "\r\n").filter {
      $0.lowercased().hasPrefix("content-length:")
    }
    guard lengths.count == 1,
      let length = Int(lengths[0].dropFirst(15).trimmingCharacters(in: .whitespaces)),
      length >= 0, length <= 8 * 1024 * 1024
    else {
      throw ArchitectureError("PROTOCOL_MISMATCH", "Invalid LSP Content-Length.", exitCode: 7)
    }
    let end = separator.upperBound + length
    guard pending.count >= end else { return nil }
    let message = try JSONDecoder().decode(
      JSONValue.self, from: pending[separator.upperBound..<end])
    pending.removeSubrange(..<end)
    return message
  }

  public func shutdown() async throws {
    if let shutdownTask {
      try await shutdownTask.value
      return
    }
    stopping = true
    // An owned unstructured cleanup task is not cancelled with the caller that is awaiting it.
    let task = Task { try await self.closeSession() }
    shutdownTask = task
    try await task.value
  }

  private func closeSession() async throws {
    if process.isRunning {
      do {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        try await acquireOperation(until: deadline, closing: true)
        defer { operationBusy = false }
        _ = try await exchange("shutdown", params: .null, until: deadline, closing: true)
        try await write(
          .object(["jsonrpc": .string("2.0"), "method": .string("exit"), "params": .null]),
          until: deadline, closing: true)
      } catch { if process.isRunning { process.terminate() } }
    }
    await waitForExit(for: .seconds(2))
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
      await waitForExit(for: .seconds(2))
    }
    closed = true
    var closeError: (any Error)?
    do { try input.close() } catch { closeError = error }
    do { try output.close() } catch { if closeError == nil { closeError = error } }
    guard !process.isRunning else {
      throw ArchitectureError(
        "PROCESS_SHUTDOWN_FAILED", "Provider did not exit after forced termination.", exitCode: 6)
    }
    if let closeError { throw closeError }
  }

  private func waitForExit(for duration: Duration) async {
    let deadline = ContinuousClock.now.advanced(by: duration)
    while process.isRunning, ContinuousClock.now < deadline {
      do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
    }
  }
}
