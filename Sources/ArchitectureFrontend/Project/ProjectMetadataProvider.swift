import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ProjectMetadataProvider: Sendable {
  public init() {}
  public func analyze(paths: WorkspacePaths, snapshot: Snapshot, trusted: Bool) async throws
    -> FrontendResult
  {
    guard trusted else {
      throw ArchitectureError(
        "WORKSPACE_TRUST_REQUIRED",
        "Manifest evaluation may execute project code. Pass --trusted-workspace explicitly for this invocation.",
        exitCode: 5)
    }
    var nodes: [Entity] = []
    var facts: [Fact] = []
    var evidence: [Evidence] = []
    var coverage: [Coverage] = []
    for package in snapshot.entities where package.kind == "package" {
      guard let manifest = package.attributes["project.manifest"]?.string else { continue }
      let directory = (manifest as NSString).deletingLastPathComponent
      let url = directory.isEmpty ? paths.root : try paths.resolve(directory)
      let bytes: Data
      if package.language == "swift" {
        bytes = try await BoundedProcess.run(
          executable: "/usr/bin/xcrun",
          arguments: [
            "swift", "package", "--package-path", url.path, "--disable-automatic-resolution",
            "describe", "--type", "json",
          ], directory: url)
      } else {
        let cargo = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
          ".cargo/bin/cargo"
        ).path
        guard FileManager.default.isExecutableFile(atPath: cargo) else {
          throw ArchitectureError(
            "UNSUPPORTED_CAPABILITY", "Cargo is unavailable; no download was attempted.",
            exitCode: 3)
        }
        bytes = try await BoundedProcess.run(
          executable: cargo,
          arguments: [
            "metadata", "--offline", "--no-deps", "--format-version", "1", "--manifest-path",
            url.appendingPathComponent("Cargo.toml").path,
          ], directory: url)
      }
      let metadata = try JSONDecoder().decode(JSONValue.self, from: bytes)
      let evidenceID = CanonicalJSON.identity(
        "project.metadata:" + package.id + ":" + snapshot.contextDigest)
      evidence.append(
        Evidence(
          id: evidenceID, producer: "project.metadata",
          inputDigest: snapshot.inputs[manifest] ?? "unknown",
          contextDigest: snapshot.contextDigest, basis: "semantic", freshness: "unknown",
          anchor: nil,
          diagnostics: [
            Diagnostic(
              "PROJECT_CONTEXT_UNAVAILABLE",
              "Metadata is resolved; active compile flags and whole-project build inputs are not fully established.",
              scope: manifest)
          ]))
      let targets =
        package.language == "swift"
        ? metadata["targets"].array : metadata["packages"].array.flatMap { $0["targets"].array }
      var targetMap: [String: String] = [:]
      for target in targets {
        guard let name = target["name"].string else { continue }
        let key = package.identityKey + ":module:" + name
        let id = CanonicalJSON.identity(key)
        targetMap[name] = id
        nodes.append(
          Entity(
            id: id, kind: "module",
            language: package.language == "swift" && target["module_type"].string != "SwiftTarget"
              ? "none" : package.language, name: name, identityKey: key,
            entityRevision: CanonicalJSON.digest(try CanonicalJSON.encode(target)),
            attributes: [
              "project.metadata": portable(target, root: paths.root.path),
              "project.manifest": .string(manifest),
              "freshness": .string("unknown"),
            ]))
        facts.append(
          Fact(
            id: CanonicalJSON.identity("project.metadata:contains:" + id),
            producer: "project.metadata", scope: manifest, kind: "contains", source: package.id,
            target: id, revision: snapshot.contextDigest, evidenceIDs: [evidenceID]))
      }
      for target in targets {
        guard let name = target["name"].string, let from = targetMap[name] else { continue }
        let sourcePaths: [String]
        if package.language == "swift", let targetPath = target["path"].string {
          sourcePaths = target["sources"].array.compactMap(\.string).map {
            [directory, targetPath, $0].filter { !$0.isEmpty }.joined(separator: "/")
          }
        } else if let source = target["src_path"].string, source.hasPrefix(paths.root.path + "/") {
          sourcePaths = [String(source.dropFirst(paths.root.path.count + 1))]
        } else {
          sourcePaths = []
        }
        for path in sourcePaths {
          _ = try paths.resolve(path)
          guard
            let file = snapshot.entities.first(where: {
              $0.kind == "file" && $0.anchor?.path == path
            })
          else { continue }
          facts.append(
            Fact(
              id: CanonicalJSON.identity("project.metadata:source:" + from + ":" + file.id),
              producer: "project.metadata", scope: manifest, kind: "contains", source: from,
              target: file.id, revision: snapshot.contextDigest, evidenceIDs: [evidenceID],
              attributes: ["projection": .string("build-module")]))
        }
        for dependency in target["dependencies"].array + target["target_dependencies"].array {
          let dependencyName =
            dependency["target"].array.first?.string ?? dependency["byName"].array.first?.string
            ?? dependency.string
          guard let dependencyName, let to = targetMap[dependencyName] else { continue }
          facts.append(
            Fact(
              id: CanonicalJSON.identity("project.metadata:depends:" + from + ":" + to),
              producer: "project.metadata", scope: manifest, kind: "dependsOn", source: from,
              target: to, revision: snapshot.contextDigest, evidenceIDs: [evidenceID]))
        }
      }
      coverage.append(
        Coverage(
          producer: "project.metadata", scope: manifest, language: package.language,
          freshness: "unknown", completeness: "partial",
          exclusions: [
            "implicit dependency resolution", "build execution", "active compile flags",
            "generated source", "file membership not returned by metadata",
          ]))
    }
    guard !coverage.isEmpty else {
      throw ArchitectureError(
        "PROJECT_CONTEXT_UNAVAILABLE", "No supported project manifest was found.", exitCode: 3)
    }
    return FrontendResult(
      entities: nodes, facts: facts, evidence: evidence,
      coverage: Coverage(
        producer: "project.metadata", scope: "workspace", language: "multiple",
        freshness: "unknown", completeness: "partial", exclusions: coverage.flatMap(\.exclusions)))
  }
  private func portable(_ value: JSONValue, root: String) -> JSONValue {
    switch value {
    case .string(let text):
      if text.hasPrefix(root + "/") { return .string(String(text.dropFirst(root.count + 1))) }
      return value
    case .array(let values): return .array(values.map { portable($0, root: root) })
    case .object(let values): return .object(values.mapValues { portable($0, root: root) })
    default: return value
    }
  }

}
