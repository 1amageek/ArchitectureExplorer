import ArchitectureClient
import ArchitectureCore
import Foundation

struct DaemonLauncher {
  static func ensure(_ client: ArchitectureClient) async throws {
    do {
      let hello = try await client.call("daemon.hello")
      guard hello["workspaceID"].string == client.paths.workspaceID,
        hello["protocolVersion"].string == "1.0", hello["processIdentity"].string != nil
      else {
        throw ArchitectureError(
          "PROTOCOL_MISMATCH", "Connected daemon identity differs.", exitCode: 7)
      }
      return
    } catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" {}
    try client.paths.prepareState()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = ["daemon", "run", "--workspace", client.paths.root.path]
    let log = client.paths.state.appendingPathComponent("daemon.log")
    if !FileManager.default.fileExists(atPath: log.path) {
      FileManager.default.createFile(
        atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    try handle.close()
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while ContinuousClock.now < deadline {
      do {
        let hello = try await client.call("daemon.hello")
        if hello["workspaceID"].string == client.paths.workspaceID,
          hello["processIdentity"].string != nil
        {
          return
        }
        throw ArchitectureError("PROTOCOL_MISMATCH", "Daemon identity mismatch.", exitCode: 7)
      } catch let error as ArchitectureError where error.code == "CONNECTION_FAILED" {}
      try await Task.sleep(for: .milliseconds(50))
    }
    throw ArchitectureError(
      "CONNECTION_FAILED", "Daemon did not become ready; inspect the private daemon log.",
      exitCode: 6)
  }
}
