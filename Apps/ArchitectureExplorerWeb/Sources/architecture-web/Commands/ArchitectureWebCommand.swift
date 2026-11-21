import ArchitectureServer
import Foundation

@main struct ArchitectureWebCommand {
  private enum ArgumentError: Error { case unknownOption(String), invalidBrowserSession }

  static func main() async {
    do {
      var args = Array(CommandLine.arguments.dropFirst())
      var workspace = FileManager.default.currentDirectoryPath
      var repositoryMap: URL?
      var port = 0
      var noOpen = false
      var codexBrowser = false
      while !args.isEmpty {
        let argument = args.removeFirst()
        switch argument {
        case "--workspace":
          guard !args.isEmpty else { throw CocoaError(.coderValueNotFound) }
          workspace = args.removeFirst()
        case "--repository-map":
          guard !args.isEmpty else { throw CocoaError(.coderValueNotFound) }
          repositoryMap = URL(fileURLWithPath: args.removeFirst())
        case "--port":
          guard !args.isEmpty, let value = Int(args.removeFirst()) else {
            throw CocoaError(.coderValueNotFound)
          }
          port = value
        case "--codex-browser": codexBrowser = true
        case "--no-open": noOpen = true
        default: throw ArgumentError.unknownOption(argument)
        }
      }
      let threadID = codexBrowser ? ProcessInfo.processInfo.environment["CODEX_THREAD_ID"].flatMap(UUID.init(uuidString:)) : nil
      if codexBrowser && (threadID == nil || repositoryMap != nil) {
        throw ArgumentError.invalidBrowserSession
      }
      try await ExplorerServer.run(workspace: workspace, port: port, noOpen: noOpen || codexBrowser, repositoryMap: repositoryMap, threadID: threadID)
    } catch {
      FileHandle.standardError.write(Data("Web host failed: \(error)\n".utf8))
      exit(4)
    }
  }
}
