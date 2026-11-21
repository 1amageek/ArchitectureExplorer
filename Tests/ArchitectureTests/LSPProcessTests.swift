import ArchitectureCore
import ArchitectureFrontend
import Darwin
import Foundation
import Testing

struct LSPProcessTests {
  private func fixture(_ mode: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard
      let resource = Bundle.module.url(
        forResource: "lsp-provider", withExtension: "py", subdirectory: "Fixtures")
    else {
      throw ArchitectureError("TEST_FIXTURE_MISSING", "The real stdio fixture is missing.")
    }
    try FileManager.default.copyItem(at: resource, to: root.appendingPathComponent("provider.py"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("provider.py").path)
    try Data(mode.utf8).write(to: root.appendingPathComponent("provider-mode"))
    return root
  }
  private func remove(_ root: URL) {
    do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
  }
  private func ready(_ root: URL) async throws -> Int32 {
    let file = root.appendingPathComponent("provider.pid")
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !FileManager.default.fileExists(atPath: file.path) {
      guard ContinuousClock.now < deadline else {
        throw ArchitectureError("TEST_TIMEOUT", "Provider did not start.")
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    let value = try String(contentsOf: file, encoding: .utf8)
    guard let pid = Int32(value) else {
      throw ArchitectureError("TEST_FIXTURE_FAILED", "Provider PID is invalid.")
    }
    return pid
  }
  private func gone(_ pid: Int32) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

  private func withSession(_ mode: String, body: (LSPProcess, Int32) async throws -> Void)
    async throws
  {
    let root = try fixture(mode)
    defer { remove(root) }
    let process = try LSPProcess(
      executable: root.appendingPathComponent("provider.py").path, workspace: root)
    do {
      let pid = try await ready(root)
      try await body(process, pid)
    } catch {
      try await process.shutdown()
      throw error
    }
    try await process.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func blockedWriteTimesOutAndShutdownIsIdempotent() async throws {
    try await withSession("blocked") { process, pid in
      let start = ContinuousClock.now
      do {
        try await process.notify(
          "large", params: .object(["text": .string(String(repeating: "x", count: 1024 * 1024))]),
          timeout: .milliseconds(150))
        Issue.record("A non-reading child must apply bounded backpressure.")
      } catch let error as ArchitectureError { #expect(error.code == "ANALYSIS_TIMEOUT") }
      #expect(start.duration(to: .now) < .seconds(2))
      do {
        try await process.notify("cannot-reuse-partial-frame", params: .null, timeout: .milliseconds(50))
        Issue.record("A truncated frame must invalidate the session.")
      } catch let error as ArchitectureError { #expect(error.code == "PROCESS_FAILED") }
      try await process.shutdown()
      try await process.shutdown()
      #expect(gone(pid))
    }
  }
  @Test(.timeLimit(.minutes(1))) func cancelledWriteAndCallerStillAwaitOwnedCleanup() async throws {
    try await withSession("blocked") { process, pid in
      let operation = Task {
        try await process.notify(
          "large", params: .object(["text": .string(String(repeating: "x", count: 1024 * 1024))]),
          timeout: .seconds(5))
      }
      try await Task.sleep(for: .milliseconds(100))
      let start = ContinuousClock.now
      operation.cancel()
      do {
        try await operation.value
        Issue.record("The write must observe cancellation.")
      } catch is CancellationError {}
      #expect(start.duration(to: .now) < .seconds(1))
      let cleanup = Task { try await process.shutdown() }
      cleanup.cancel()
      try await cleanup.value
      #expect(gone(pid))
    }
  }
  @Test(.timeLimit(.minutes(1))) func concurrentRequestsPreserveFramesAndResponses() async throws {
    try await withSession("echo") { process, pid in
      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          for index in 0..<8 {
            group.addTask {
              let result = try await process.request(
                "echo",
                params: .object([
                  "token": .number(Double(index)),
                  "text": .string(String(repeating: "x", count: 128000)),
                ]), timeout: .seconds(5))
              #expect(result["token"].int == index)
              #expect(result["size"].int == 128000)
            }
          }
          try await group.waitForAll()
        }
        try await process.notify(
          "large", params: .object(["text": .string(String(repeating: "x", count: 1024 * 1024))]),
          timeout: .seconds(5))
        let result = try await process.request("echo", params: .object([:]), timeout: .seconds(5))
        #expect(result["notifications"].int == 1)
        try await process.shutdown()
      } catch {
        try await process.shutdown()
        throw error
      }
      #expect(gone(pid))
    }
  }
  @Test(.timeLimit(.minutes(1))) func closedInputIsTypedFailureWithoutSIGPIPE() async throws {
    try await withSession("closed") { process, pid in
      do {
        try await process.notify(
          "large", params: .object(["text": .string(String(repeating: "x", count: 100000))]),
          timeout: .milliseconds(500))
        Issue.record("A closed pipe must not report success.")
      } catch let error as ArchitectureError { #expect(error.code == "PROCESS_FAILED") }
      try await process.shutdown()
      #expect(gone(pid))
    }
  }
  @Test(.timeLimit(.minutes(1))) func shutdownInterruptsActiveRequestAndForcesUnresponsiveChild()
    async throws
  {
    try await withSession("stubborn") { process, pid in
      let operation = Task {
        try await process.request("echo", params: .object([:]), timeout: .seconds(8))
      }
      try await Task.sleep(for: .milliseconds(100))
      let start = ContinuousClock.now
      try await process.shutdown()
      #expect(start.duration(to: .now) < .seconds(6))
      do {
        _ = try await operation.value
        Issue.record("A stopped request must fail.")
      } catch let error as ArchitectureError { #expect(error.code == "PROCESS_FAILED") }
      #expect(gone(pid))
    }
  }
}
