import ArchitectureCore
import Foundation

struct CommandOptions {
  let command: String
  let subcommand: String?
  let values: [String: String]
  let flags: Set<String>
  init(_ arguments: [String]) throws {
    var arguments = arguments
    command = arguments.isEmpty ? "help" : arguments.removeFirst()
    subcommand =
      ["daemon", "canvas"].contains(command) && arguments.first?.hasPrefix("--") == false
      ? arguments.removeFirst() : nil
    let boolean: Set<String> = [
      "watch", "no-open", "codex-browser", "force", "require-complete", "trusted-workspace", "help", "version",
    ]
    let value: Set<String> = [
      "workspace", "format", "query", "view", "level", "focus", "symbol", "entity", "depth",
      "limit", "direction", "kind", "language", "snapshot", "cursor", "from", "to", "out", "config",
      "repository-map", "web-helper", "port", "input", "provider", "operation", "session", "params",
    ]
    var values: [String: String] = [:]
    var flags = Set<String>()
    while !arguments.isEmpty {
      let argument = arguments.removeFirst()
      guard argument.hasPrefix("--") else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Unexpected positional argument: \(argument)", exitCode: 2)
      }
      let key = String(argument.dropFirst(2))
      guard values[key] == nil, !flags.contains(key) else {
        throw ArchitectureError("INVALID_ARGUMENT", "Duplicate option --\(key)", exitCode: 2)
      }
      if boolean.contains(key) {
        flags.insert(key)
      } else if value.contains(key), let next = arguments.first, !next.hasPrefix("--") {
        values[key] = arguments.removeFirst()
      } else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Unknown option or missing value: \(argument)", exitCode: 2)
      }
    }
    let common: Set<String> = ["workspace", "format", "help", "version"]
    let graph: Set<String> = [
      "view", "level", "focus", "depth", "limit", "direction", "kind", "language", "snapshot",
      "cursor", "require-complete",
    ]
    let permitted: [String: Set<String>] = [
      "canvas": ["input", "session", "params", "kind", "out", "force"], "init": [], "index": ["trusted-workspace", "input"], "graph": graph,
      "search": ["query", "limit", "language", "snapshot", "cursor", "require-complete"],
      "cfg": ["symbol", "snapshot", "require-complete"],
      "explain": ["entity", "snapshot", "require-complete"], "diff": ["from", "to"], "status": [],
      "capabilities": [], "coverage": [], "doctor": ["web-helper"], "daemon": [], "mcp": [],
      "export": graph.union(["out", "force"]),
      "explore": ["repository-map", "watch", "no-open", "codex-browser", "web-helper", "port"],
      "semantic": ["entity", "provider", "operation", "trusted-workspace"],
    ]
    if let allowed = permitted[command] {
      let supplied = Set(values.keys).union(flags)
      guard supplied.isSubset(of: allowed.union(common)) else {
        throw ArchitectureError(
          "INVALID_ARGUMENT",
          "An option is not supported by \(command): \(supplied.subtracting(allowed.union(common)).sorted().joined(separator:", "))",
          exitCode: 2)
      }
    }
    if let view = values["view"],
      !["hierarchy", "calls", "dependencies", "impact", "design"].contains(view)
    {
      throw ArchitectureError("INVALID_ARGUMENT", "Unknown graph view.", exitCode: 2)
    }
    if let format = values["format"], !["graph", "search", "cfg", "export", "canvas"].contains(command),
      format != "json"
    {
      throw ArchitectureError(
        "INVALID_ARGUMENT", "This command supports JSON output only.", exitCode: 2)
    }
    if let raw = values["port"] {
      guard let port = Int(raw), (0...65535).contains(port) else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Port must be an integer in 0...65535.", exitCode: 2)
      }
    }
    self.values = values
    self.flags = flags
  }
  var workspace: String { values["workspace"] ?? FileManager.default.currentDirectoryPath }
}
