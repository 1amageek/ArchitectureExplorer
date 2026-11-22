import ArchitectureClient
import ArchitectureCore
import ArchitectureServer
import ArchitectureService
import Foundation

@main
struct ExplorerHostCommand {
  static func main() async {
    do {
      try await execute(Array(CommandLine.arguments.dropFirst()))
    } catch is CancellationError {
      exit(130)
    } catch {
      let failure = error as? ArchitectureError ?? ArchitectureError("REQUEST_FAILED", String(describing: error))
      FileHandle.standardError.write(Data("\(failure)\n".utf8))
      exit(failure.exitCode)
    }
  }

  static func execute(_ arguments: [String]) async throws {
    guard arguments.count >= 3, arguments[1] == "--workspace" else {
      throw ArchitectureError("INVALID_ARGUMENT", "Expected a host mode and --workspace PATH.", exitCode: 2)
    }
    let client = try ArchitectureClient(workspace: arguments[2])
    guard let executable = Bundle.main.executableURL else {
      throw ArchitectureError("DAEMON_UNAVAILABLE", "Cannot locate the packaged Explorer host.", exitCode: 3)
    }
    let options = Array(arguments.dropFirst(3))
    switch (arguments[0], options) {
    case ("start", []):
      let companion = try InstalledInvarProvider.identify(host: executable)
      try await ArchitectureDaemonLauncher.ensure(
        client, executable: executable, arguments: ["serve", "--workspace", client.paths.root.path],
        expectedCompanionIdentity: companion?.identity)
    case ("serve", []):
      let companion = try InstalledInvarProvider.identify(host: executable)
      try await ArchitectureDaemonLauncher.serve(client.paths, bundledProvider: companion)
    case ("stop", []):
      _ = try await client.call("daemon.stop")
    case ("browser", []), ("browser", ["--no-open"]), ("browser", ["--codex-browser"]):
      let codexBrowser = options == ["--codex-browser"]
      let threadID = ProcessInfo.processInfo.environment["CODEX_THREAD_ID"].flatMap(UUID.init(uuidString:))
      guard !codexBrowser || threadID != nil else {
        throw ArchitectureError("INVALID_ARGUMENT", "Missing Codex browser session.", exitCode: 2)
      }
      try await ExplorerServer.run(
        workspace: client.paths.root.path, noOpen: !options.isEmpty, threadID: codexBrowser ? threadID : nil)
    default:
      throw ArchitectureError("INVALID_ARGUMENT", "Unsupported host invocation.", exitCode: 2)
    }
  }
}
