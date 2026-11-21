import ArchitectureCore
import Foundation

public struct IndexConfiguration: Sendable {
  public let value: JSONValue
  public let digest: String
  public let languages: [String]
  public let include: [String]
  public let exclude: [String]
  public let workers: Int
  public let maxBytes: Int
  public let debounceMilliseconds: Int
  public init(paths: WorkspacePaths, explicitPath: String? = nil) throws {
    let url =
      explicitPath.map { URL(fileURLWithPath: $0) }
      ?? paths.root.appendingPathComponent("architecture.json")
    let value: JSONValue
    if FileManager.default.fileExists(atPath: url.path) {
      let bytes = try Data(contentsOf: url)
      guard bytes.count <= 1024 * 1024 else {
        throw ArchitectureError("RESOURCE_LIMIT", "Configuration exceeds 1 MiB.", exitCode: 6)
      }
      value = try JSONDecoder().decode(JSONValue.self, from: bytes)
    } else if explicitPath != nil {
      throw ArchitectureError(
        "INVALID_CONFIGURATION", "Explicit configuration file is missing.", exitCode: 2)
    } else {
      value = .object([
        "schemaVersion": .string("1.0"), "languages": .array([.string("swift"), .string("rust")]),
      ])
    }
    guard value["schemaVersion"].string == "1.0" else {
      throw ArchitectureError(
        "SCHEMA_MISMATCH", "Configuration requires schemaVersion 1.0.", exitCode: 2)
    }
    let keys: Set<String> = [
      "schemaVersion", "languages", "include", "exclude", "analysis", "views", "designGroups",
      "externalLinks", "extensions",
    ]
    guard Set(value.object.keys).isSubset(of: keys) else {
      throw ArchitectureError("INVALID_CONFIGURATION", "Unknown configuration key.", exitCode: 2)
    }
    let analysisKeys: Set<String> = [
      "syntax", "semantic", "cfg", "debounceMilliseconds", "maxWorkers", "maxSourceFileBytes",
    ]
    guard Set(value["analysis"].object.keys).isSubset(of: analysisKeys) else {
      throw ArchitectureError(
        "INVALID_CONFIGURATION", "Unknown analysis configuration key.", exitCode: 2)
    }
    let languages = value["languages"].array.compactMap(\.string)
    guard !languages.isEmpty, Set(languages).isSubset(of: ["swift", "rust"]) else {
      throw ArchitectureError(
        "UNSUPPORTED_LANGUAGE", "Supported languages are swift and rust.", exitCode: 3)
    }
    self.value = value
    self.languages = languages
    include = value["include"] == .null ? ["**"] : value["include"].array.compactMap(\.string)
    exclude =
      [
        ".git/**", ".build/**", ".swiftpm/**", "target/**", "node_modules/**", ".architecture/**",
        "Dist/**",
      ] + value["exclude"].array.compactMap(\.string)
    workers =
      value["analysis"]["maxWorkers"].int ?? min(4, ProcessInfo.processInfo.activeProcessorCount)
    maxBytes = value["analysis"]["maxSourceFileBytes"].int ?? 5 * 1024 * 1024
    debounceMilliseconds = value["analysis"]["debounceMilliseconds"].int ?? 250
    guard (1...16).contains(workers), (1...5 * 1024 * 1024).contains(maxBytes),
      (50...10000).contains(debounceMilliseconds)
    else {
      throw ArchitectureError(
        "INVALID_CONFIGURATION", "Worker, source size or debounce budget outside supported range.",
        exitCode: 2)
    }
    digest = CanonicalJSON.digest(try CanonicalJSON.encode(value))
  }
  public func matches(_ path: String, glob: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: glob)
      .replacingOccurrences(of: "\\*\\*", with: "§DOUBLE§")
      .replacingOccurrences(of: "\\*", with: "[^/]*")
      .replacingOccurrences(of: "§DOUBLE§/", with: "(?:.*/)?")
      .replacingOccurrences(of: "§DOUBLE§", with: ".*")
    return path.range(of: "^" + escaped + "$", options: .regularExpression) != nil
  }
  public func accepts(_ path: String) -> Bool {
    include.contains { matches(path, glob: $0) } && !exclude.contains { matches(path, glob: $0) }
  }
}
