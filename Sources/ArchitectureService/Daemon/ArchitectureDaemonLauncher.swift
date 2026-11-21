import ArchitectureClient
import ArchitectureCore
import ArchitectureStore
import Foundation

package enum ArchitectureDaemonLauncher {
  package static func serve(
    _ paths: WorkspacePaths, trustedHostDigests: Set<String> = []
  ) async throws {
    try paths.prepareState()
    let store = try SQLiteGraphStore(
      path: paths.state.appendingPathComponent("graph.sqlite").path, workspaceID: paths.workspaceID)
    let daemon = try ArchitectureDaemon(paths: paths, store: store, trustedHostDigests: trustedHostDigests)
    try await daemon.run()
  }

  package static func ensure(
    _ client: ArchitectureClient, executable: URL, arguments: [String]
  ) async throws {
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
    process.executableURL = executable
    process.arguments = arguments
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
