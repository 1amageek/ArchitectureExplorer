import ArchitectureClient
import ArchitectureCore
import ArchitectureGraph
import ArchitectureIR
import ArchitectureMCP
import ArchitectureService
import ArchitectureStore
import Darwin
import Foundation

@main struct ArchitectureCommand {
  static let help = """
    ArchitectureExplorer 0.1.0 — local evidence-backed architecture exploration
    Usage: architecture <command> [--workspace PATH] [options]
    Commands: init, index, explore, graph, search, cfg, explain, diff, status,
              capabilities, coverage, export, mcp, daemon start|status|stop, doctor, semantic, canvas
    Graph: --view hierarchy|calls|dependencies|impact --level context|container|system|module|component|function|file
           --focus ID --depth 0...8 --direction outgoing|incoming|both --limit N
    Search: --query TEXT --limit 1...200
    Details: cfg --symbol ID; explain --entity ID; diff --from SNAPSHOT --to SNAPSHOT
    Export: --format json|mermaid|svg|html --out PATH [--force]
    Common: --snapshot ID --cursor CURSOR --format json|mermaid|svg
            --require-complete --help --version
    Explore: [--repository-map PATH] --watch [--no-open | --codex-browser] [--web-helper PATH] [--port PORT]
    Sources are read-only. Unknown semantic targets remain unresolved.
    """
  static func main() async {
    do {
      try await execute(try CommandOptions(Array(CommandLine.arguments.dropFirst())))
    } catch is CancellationError { exit(130) } catch {
      let typed =
        error as? ArchitectureError
        ?? ArchitectureError("REQUEST_FAILED", String(describing: error))
      FileHandle.standardError.write(Data((typed.description + "\n").utf8))
      exit(typed.exitCode)
    }
  }
  static func output(_ value: JSONValue) throws {
    var data = try CanonicalJSON.encode(value)
    data.append(10)
    FileHandle.standardOutput.write(data)
  }
  static func execute(_ options: CommandOptions) async throws {
    if options.command == "--version" || options.flags.contains("version") {
      print("ArchitectureExplorer 0.1.0 / schema 1.0 / MCP 2025-11-25")
      return
    }
    if ["help", "--help"].contains(options.command) || options.flags.contains("help") {
      print(help)
      return
    }
    let client = try ArchitectureClient(workspace: options.workspace)
    if options.command == "init" {
      let path = client.paths.root.appendingPathComponent("architecture.json")
      let data = try CanonicalJSON.encode(
        JSONValue.object([
          "schemaVersion": .string("1.0"),
          "languages": .array([.string("swift"), .string("rust")]),
          "include": .array([.string("**")]), "exclude": .array([]),
        ]))
      guard !FileManager.default.fileExists(atPath: path.path) else {
        throw ArchitectureError("OUTPUT_EXISTS", "architecture.json already exists.", exitCode: 2)
      }
      try data.write(to: path, options: .withoutOverwriting)
      try output(.object(["created": .string("architecture.json")]))
      return
    }
    if options.command == "daemon", options.subcommand == "run" {
      try client.paths.prepareState()
      let store = try SQLiteGraphStore(
        path: client.paths.state.appendingPathComponent("graph.sqlite").path,
        workspaceID: client.paths.workspaceID)
      #if ARCHITECTURE_PAIRED_WEB
      let digests: Set<String> = [HostBuildIdentity.webDigest]
      #else
      let digests: Set<String> = []
      #endif
      let daemon = try ArchitectureDaemon(paths: client.paths, store: store, trustedHostDigests: digests)
      try await daemon.run()
      return
    }
    let commands: Set<String> = [
      "index", "graph", "search", "cfg", "explain", "diff", "status", "capabilities", "coverage",
      "export", "mcp", "daemon", "doctor", "explore", "semantic", "canvas",
    ]
    guard commands.contains(options.command) else {
      throw ArchitectureError(
        "INVALID_ARGUMENT", "Unknown command: \(options.command)", exitCode: 2)
    }
    if options.command == "daemon" {
      switch options.subcommand {
      case "start":
        try await DaemonLauncher.ensure(client)
        try output(await client.call("daemon.hello"))
      case "status": try output(await client.call("daemon.hello"))
      case "stop": try output(await client.call("daemon.stop"))
      default:
        throw ArchitectureError(
          "INVALID_ARGUMENT", "daemon requires start, status or stop.", exitCode: 2)
      }
      return
    }
    if options.command == "doctor" {
      try output(
        .object([
          "schemaVersion": .string("1.0"), "workspaceID": .string(client.paths.workspaceID),
          "platform": .string(ProcessInfo.processInfo.operatingSystemVersionString),
          "toolchainBaseline": .string("Swift 6.4.1"),
          "webHelper": .string(helperPath(options) ?? "unavailable"),
          "semanticProviders": .string("not configured"),
          "trust": .string("filesystem and syntax only"),
        ]))
      return
    }
    if options.command == "explore", options.values["repository-map"] != nil {
      try await explore(options, client: client)
      return
    }
    try await DaemonLauncher.ensure(client)
    if options.command == "canvas" {
      let operation = options.subcommand ?? "list"
      var parameters: [String: JSONValue] = [:]
      if let raw = options.values["params"] { parameters = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)).object }
      if let id = options.values["session"] { parameters["viewSessionID"] = .string(id) }
      if let kind = options.values["kind"] { parameters["kind"] = .string(kind) }
      if let format = options.values["format"] { parameters["format"] = .string(format) }
      if let path = options.values["input"] {
        let url = URL(fileURLWithPath: path), values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? Int.max) <= 1024 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Canvas file exceeds 1 MiB.", exitCode: 6) }
        parameters["name"] = .string(url.lastPathComponent)
        parameters["text"] = .string(try String(contentsOf: url, encoding: .utf8))
      }
      let result = try await client.call("canvas." + operation, parameters: .object(parameters))
      if let out = options.values["out"], let text = result["text"].string { try GraphExporter.write(text, to: out, force: options.flags.contains("force")) }
      try output(result); return
    }
    if options.command == "semantic" {
      guard let entity = options.values["entity"], let provider = options.values["provider"] else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "semantic requires --entity and --provider.", exitCode: 2)
      }
      try output(
        await client.call(
          "graph.semantic",
          parameters: .object([
            "focus": .string(entity), "provider": .string(provider),
            "operation": .string(options.values["operation"] ?? "definition"),
            "trusted": .bool(options.flags.contains("trusted-workspace")),
          ])))
      return
    }
    if options.command == "index", let input = options.values["input"] {
      let bytes = try Data(contentsOf: URL(fileURLWithPath: input))
      guard bytes.count <= 4 * 1024 * 1024 else {
        throw ArchitectureError("RESOURCE_LIMIT", "Import frame exceeds 4 MiB.", exitCode: 6)
      }
      let snapshot = try JSONDecoder().decode(Snapshot.self, from: bytes)
      try GraphValidation.validate(snapshot)
      try output(
        await client.call(
          "workspace.import", parameters: .object(["snapshot": try JSONValue.encode(snapshot)])))
      return
    }
    if options.command == "mcp" {
      try await MCPServer(client: client).run()
      return
    }
    if options.command == "explore" {
      try await explore(options, client: client)
      return
    }
    let method: String
    switch options.command {
    case "index": method = "workspace.index"
    case "status", "coverage": method = "workspace.status"
    case "capabilities": method = "graph.capabilities"
    case "search": method = "graph.search"
    case "cfg": method = "graph.cfg"
    case "explain": method = "graph.explain"
    case "diff": method = "graph.diff"
    default:
      method =
        (options.values["focus"] == nil || ["context", "container"].contains(options.values["level"] ?? ""))
        ? "graph.overview"
        : (options.values["view"] == "impact" ? "graph.impact" : "graph.neighbors")
    }
    var parameters: [String: JSONValue] = [:]
    let mapping = [
      "focus": "focus", "symbol": "focus", "entity": "focus", "query": "text", "level": "level",
      "snapshot": "snapshotID", "cursor": "cursor", "direction": "direction", "from": "from",
      "to": "to",
    ]
    for (key, target) in mapping {
      if let value = options.values[key] { parameters[target] = .string(value) }
    }
    for key in ["depth", "limit"] {
      if let text = options.values[key] {
        guard let value = Int(text) else {
          throw ArchitectureError("INVALID_ARGUMENT", "--\(key) requires an integer.", exitCode: 2)
        }
        parameters[key] = .number(Double(value))
      }
    }
    if let kind = options.values["kind"] {
      parameters["kinds"] = .array(kind.split(separator: ",").map { .string(String($0)) })
    } else if options.values["view"] == "calls" {
      parameters["kinds"] = .array([
        .string("calls"), .string("candidateCalls"), .string("contains"),
      ])
    }
    if let language = options.values["language"] {
      parameters["languages"] = .array(language.split(separator: ",").map { .string(String($0)) })
    }
    if options.command == "diff", parameters["from"] == nil || parameters["to"] == nil {
      throw ArchitectureError("INVALID_ARGUMENT", "diff requires --from and --to.", exitCode: 2)
    }
    var result = try await client.call(method, parameters: .object(parameters))
    if options.command == "index" {
      ProcessSignals.install()
      guard let jobID = result["jobID"].string else {
        throw ArchitectureError("PROTOCOL_MISMATCH", "Missing index job identity.", exitCode: 7)
      }
      while true {
        if ProcessSignals.interrupted { throw CancellationError() }
        let job = try await client.call(
          "workspace.index.result", parameters: .object(["jobID": .string(jobID)]))
        if job["state"].string == "completed" {
          result = job["result"]
          break
        }
        if job["state"].string == "failed" {
          let error = job["error"]
          throw ArchitectureError(
            error["code"].string ?? "INDEX_FAILED", error["message"].string ?? "Index failed.",
            exitCode: Int32(error["exitCode"].int ?? 4))
        }
        try await Task.sleep(for: .milliseconds(100))
      }
      if options.flags.contains("trusted-workspace") {
        _ = try await client.call(
          "workspace.project", parameters: .object(["trusted": .bool(true)]))
        result = try await client.call("workspace.status")
      }
    }
    if options.flags.contains("require-complete"),
      result["completeness"].string != "completeWithinScope"
        || result["freshness"].string != "current"
    {
      throw ArchitectureError(
        "INCOMPLETE_INFORMATION", "Requested scope is partial, stale or unsupported.", exitCode: 3)
    }
    let format = options.values["format"] ?? "json"
    guard ["json", "mermaid", "svg", "html"].contains(format) else {
      throw ArchitectureError("INVALID_ARGUMENT", "Unknown output format.", exitCode: 2)
    }
    if options.command == "export" || format != "json" {
      let exported = try await client.call("graph.export", parameters: .object(["query": .object(parameters.merging(["method": .string(method)]) { _, new in new }), "format": .string(format)]))
      let view = try result.decode(GraphView.self)
      guard let text = exported["text"].string else { throw ArchitectureError("PROTOCOL_MISMATCH", "Export text missing.", exitCode: 7) }
      if options.command == "export" {
        guard let path = options.values["out"] else {
          throw ArchitectureError("INVALID_ARGUMENT", "export requires --out.", exitCode: 2)
        }
        try GraphExporter.write(text, to: path, force: options.flags.contains("force"))
        try output(
          .object([
            "snapshotID": .string(view.snapshotID), "out": .string(path),
            "truncated": .bool(view.truncated),
          ]))
      } else {
        print(text)
      }
    } else {
      try output(result)
    }
  }
  static func helperPath(_ options: CommandOptions) -> String? {
    if let explicit = options.values["web-helper"] {
      return FileManager.default.isExecutableFile(atPath: explicit) ? explicit : nil
    }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let candidates: [String?] = [
      options.values["web-helper"], ProcessInfo.processInfo.environment["ARCHITECTURE_WEB_HELPER"],
      executable.deletingLastPathComponent().appendingPathComponent("architecture-web").path,
    ]
    return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
  }
  static func explore(_ options: CommandOptions, client: ArchitectureClient) async throws {
    guard let helper = helperPath(options) else {
      throw ArchitectureError(
        "WEB_HOST_UNAVAILABLE",
        "Install architecture-web beside architecture or pass --web-helper PATH.", exitCode: 3)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helper)
    process.arguments =
      ["--workspace", client.paths.root.path, "--port", options.values["port"] ?? "0"]
      + (options.values["repository-map"].map { ["--repository-map", $0] } ?? [])
      + (options.flags.contains("no-open") ? ["--no-open"] : [])
      + (options.flags.contains("codex-browser") ? ["--codex-browser"] : [])
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    ProcessSignals.install()
    try process.run()
    while process.isRunning {
      if ProcessSignals.interrupted { process.terminate() }
      try await Task.sleep(for: .milliseconds(100))
    }
    if ProcessSignals.interrupted { throw CancellationError() }
    guard process.terminationStatus == 0 else {
      throw ArchitectureError(
        "WEB_HOST_FAILED", "Web helper exited with \(process.terminationStatus).",
        exitCode: process.terminationStatus)
    }
  }
}
