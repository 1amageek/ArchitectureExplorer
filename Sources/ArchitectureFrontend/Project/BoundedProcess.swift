import ArchitectureCore
import Darwin
import Foundation

public enum BoundedProcess {
  public static func run(
    executable: String, arguments: [String], directory: URL, timeout: Duration = .seconds(30)
  ) async throws -> Data {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.environment = [
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "TOOLCHAINS": ProcessInfo.processInfo.environment["TOOLCHAINS"] ?? "org.swift.641202610071a",
      "LANG": "en_US.UTF-8",
    ]
    try process.run()
    let handle = pipe.fileHandleForReading
    guard fcntl(handle.fileDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
      process.terminate()
      throw ArchitectureError("PROCESS_FAILED", "Cannot configure metadata output.")
    }
    defer {
      do { try handle.close() } catch {
        FileHandle.standardError.write(Data("Process pipe close failed: \(error)\n".utf8))
      }
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    let deadline = ContinuousClock.now.advanced(by: timeout)
    do {
      while true {
        try Task.checkCancellation()
        let count = buffer.withUnsafeMutableBytes {
          Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count)
        }
        if count > 0 {
          data.append(contentsOf: buffer.prefix(count))
          guard data.count <= 4 * 1024 * 1024 else {
            throw ArchitectureError("RESOURCE_LIMIT", "Metadata output exceeds 4 MiB.", exitCode: 6)
          }
          continue
        }
        if !process.isRunning { break }
        guard ContinuousClock.now < deadline else {
          throw ArchitectureError(
            "ANALYSIS_TIMEOUT", "Project metadata process timed out.", exitCode: 6)
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      guard process.terminationStatus == 0 else {
        throw ArchitectureError(
          "PROJECT_CONTEXT_UNAVAILABLE",
          "Project metadata exited with \(process.terminationStatus); no dependency resolution or network retry was attempted.",
          exitCode: 4)
      }
      return data
    } catch {
      if process.isRunning { process.terminate() }
      let deadline = ContinuousClock.now.advanced(by: .seconds(2))
      while process.isRunning, ContinuousClock.now < deadline {
        do { try await Task.sleep(for: .milliseconds(10)) } catch { break }
      }
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      throw error
    }
  }
}
