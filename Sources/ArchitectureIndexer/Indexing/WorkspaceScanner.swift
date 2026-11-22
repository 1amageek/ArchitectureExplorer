import ArchitectureCore
import ArchitectureFrontend
import Foundation
import Darwin

public struct WorkspaceScanner: Sendable {
  public init() {}
  static func sourceLanguage(_ path: String) -> String? {
    switch (path as NSString).pathExtension {
    case "swift": "swift"
    case "rs": "rust"
    case "ts", "tsx": "typescript"
    default: nil
    }
  }
  public func capture(paths: WorkspacePaths, configuration: IndexConfiguration, generation: Int)
    throws -> (sources: [SourceInput], catalogs: [SourceInput], sequenceFiles: [String: SourceInput], inputs: [String: String], diagnostics: [Diagnostic])
  {
    // Cooperating generators replace fragments and the root under an exclusive directory lock.
    let directory = open(paths.root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard directory >= 0 else { throw ArchitectureError("INPUT_UNREADABLE", "Cannot open workspace.") }
    defer { close(directory) }
    guard flock(directory, LOCK_SH | LOCK_NB) == 0 else {
      throw ArchitectureError("INPUT_CHANGED_DURING_ANALYSIS", "Map files are being updated.", exitCode: 7)
    }
    var sources: [SourceInput] = []
    var catalogs: [SourceInput] = []
    var sequenceFiles: [String: SourceInput] = [:]
    var inputs: [String: String] = [:]
    var diagnostics: [Diagnostic] = []
    let rootPrefix = paths.root.path + "/"
    guard
      let iterator = FileManager.default.enumerator(
        at: paths.root,
        includingPropertiesForKeys: [
          .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        ], options: [.skipsHiddenFiles])
    else { throw ArchitectureError("INPUT_UNREADABLE", "Cannot enumerate workspace.") }
    var localDSL = Set<String>()
    var capturedBytes = 0
    while let url = iterator.nextObject() as? URL {
      try Task.checkCancellation()
      let canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
      guard canonicalPath.hasPrefix(rootPrefix) else {
        iterator.skipDescendants()
        continue
      }
      let relative = String(canonicalPath.dropFirst(rootPrefix.count))
      let values = try url.resourceValues(forKeys: [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
      ])
      if values.isSymbolicLink == true {
        iterator.skipDescendants()
        diagnostics.append(
          Diagnostic("EXCLUDED_SYMLINK", "Symlink not traversed.", scope: relative))
        continue
      }
      if values.isDirectory == true {
        if [".git", ".build", ".swiftpm", "target", "node_modules", ".architecture", "Dist"]
          .contains(url.lastPathComponent)
          || configuration.exclude.contains(where: {
            configuration.matches(relative + "/", glob: $0)
          })
        {
          iterator.skipDescendants()
        }
        continue
      }
      guard values.isRegularFile == true else { continue }
      let sequence = relative == WorkspacePaths.sequenceModelFilename && configuration.accepts(relative)
      if url.pathExtension == "dsl", relative != WorkspacePaths.architectureModelFilename, !sequence {
        if configuration.accepts(relative) { localDSL.insert(relative) }
        continue
      }
      let sourceLanguage = Self.sourceLanguage(relative)
      let contextFile = [
        "Package.swift", "Package.resolved", "Cargo.toml", "Cargo.lock", "architecture.json",
        "rust-toolchain.toml", ".swift-version",
      ].contains(url.lastPathComponent)
      let catalog = (relative == WorkspacePaths.architectureModelFilename || CatalogContext.filenames.contains(url.lastPathComponent)) && configuration.accepts(relative)
      let design = SnapshotDesignDocument.matches(relative) && configuration.accepts(relative)
      let verificationSpec = relative.hasPrefix("Verification/")
        && ["properties.json", "invar.json"].contains(url.lastPathComponent) && configuration.accepts(relative)
      guard sequence || verificationSpec || design || catalog || contextFile || (sourceLanguage != nil && configuration.accepts(relative)) else {
        continue
      }
      if let language = sourceLanguage, !configuration.languages.contains(language), !contextFile {
        continue
      }
      let byteLimit = sequence ? min(configuration.maxBytes, StructurizrSequence.fileLimit) : configuration.maxBytes
      guard (values.fileSize ?? Int.max) <= byteLimit else {
        diagnostics.append(
          Diagnostic(
            "RESOURCE_LIMIT", "File exceeds configured source byte budget.", scope: relative))
        inputs[relative] = "oversize"
        continue
      }
      let safeURL = URL(fileURLWithPath: canonicalPath)
      let data = try Data(contentsOf: safeURL)
      guard data.count <= byteLimit else {
        diagnostics.append(
          Diagnostic("RESOURCE_LIMIT", "File grew beyond configured byte budget.", scope: relative))
        inputs[relative] = "oversize"
        continue
      }
      capturedBytes += data.count
      guard capturedBytes <= 256 * 1024 * 1024 else {
        throw ArchitectureError(
          "RESOURCE_LIMIT", "Immutable source capture exceeds 256 MiB.", exitCode: 6)
      }
      inputs[relative] = CanonicalJSON.digest(data)
      if sequence {
        sequenceFiles[relative] = SourceInput(workspaceID: paths.workspaceID, path: relative, language: "structurizr",
          bytes: data, contextDigest: configuration.digest, generation: generation)
      }
      if catalog {
        catalogs.append(SourceInput(workspaceID: paths.workspaceID, path: relative, language: "catalog", bytes: data, contextDigest: configuration.digest, generation: generation))
      }
      if url.lastPathComponent == "Package.swift" {
        catalogs.append(SourceInput(workspaceID: paths.workspaceID, path: relative, language: "swift", bytes: data, contextDigest: configuration.digest, generation: generation))
      }
      if let language = sourceLanguage, url.lastPathComponent != "Package.swift" {
        sources.append(
          SourceInput(
            workspaceID: paths.workspaceID, path: relative, language: language, bytes: data,
            contextDigest: configuration.digest, generation: generation))
      }
      guard inputs.count <= 100000 else {
        throw ArchitectureError(
          "RESOURCE_LIMIT", "Workspace exceeds 100000 input files.", exitCode: 6)
      }
    }
    if let root = catalogs.first(where: { $0.path == WorkspacePaths.architectureModelFilename }) {
      do {
        try StructurizrIncludes.walk(root) { path, remaining in
          guard localDSL.contains(path) else {
            throw ArchitectureError("C4_DSL_INVALID", "Included DSL is missing or excluded: " + path)
          }
          let url = try paths.resolve(path)
          guard url.path == rootPrefix + path else {
            throw ArchitectureError("C4_DSL_INVALID", "Invalid included path: " + path)
          }
          let limit = min(remaining, configuration.maxBytes, 256 * 1024 * 1024 - capturedBytes)
          let handle = try FileHandle(forReadingFrom: url)
          defer { handle.closeFile() }
          let data = try handle.read(upToCount: limit + 1) ?? Data()
          guard data.count <= limit else { throw ArchitectureError("C4_DSL_INVALID", "Map byte budget exceeded: " + path) }
          let part = SourceInput(workspaceID: paths.workspaceID, path: path, language: "structurizr",
            bytes: data, contextDigest: configuration.digest, generation: generation)
          capturedBytes += data.count
          inputs[path] = part.digest
          catalogs.append(part)
          return part
        } visit: { _, _, _, _ in }
      } catch is CancellationError { throw CancellationError() }
      catch {
        let message = String(describing: error)
        diagnostics.append(Diagnostic("C4_DSL_INVALID", message, scope: root.path))
        inputs["@mapCaptureFailure"] = CanonicalJSON.digest(message)
      }
    }
    if let sequence = sequenceFiles[WorkspacePaths.sequenceModelFilename],
      let source = String(data: sequence.bytes, encoding: .utf8) {
      var remaining = min(StructurizrSequence.citationBudget, 256 * 1024 * 1024 - capturedBytes)
      let references = Set(StructurizrSequence.lines(source).compactMap {
        StructurizrSequence.Reference($0.trimmingCharacters(in: .whitespacesAndNewlines))?.path
      }).sorted()
      for path in references.prefix(StructurizrSequence.citationLimit) where path != sequence.path {
        try Task.checkCancellation()
        guard configuration.accepts(path), remaining > 0 else { continue }
        do {
          let url = try paths.resolve(path)
          guard url.path == rootPrefix + path else { continue }
          let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
          let limit = min(remaining, configuration.maxBytes)
          guard properties.isRegularFile == true, (properties.fileSize ?? Int.max) <= limit else { continue }
          let handle = try FileHandle(forReadingFrom: url)
          defer { handle.closeFile() }
          let data = try handle.read(upToCount: limit + 1) ?? Data()
          guard data.count <= limit else { continue }
          let input = SourceInput(workspaceID: paths.workspaceID, path: path, language: "none", bytes: data,
            contextDigest: configuration.digest, generation: generation)
          if let digest = inputs[path], digest != input.digest {
            throw ArchitectureError("INPUT_CHANGED_DURING_ANALYSIS", "Sequence evidence changed during capture: " + path)
          }
          inputs[path] = input.digest
          sequenceFiles[path] = input
          remaining -= data.count
        } catch let failure as ArchitectureError where failure.code == "INPUT_CHANGED_DURING_ANALYSIS" {
          throw failure
        } catch {
          diagnostics.append(Diagnostic("SEQUENCE_EVIDENCE_UNAVAILABLE", "Could not capture sequence evidence.", scope: path))
        }
      }
    }
    if inputs[WorkspacePaths.sequenceModelFilename] != nil { inputs["@sequences"] = "structurizr-dynamic-v1" }
    inputs["@configuration"] = configuration.digest
    inputs["@provider"] = "skeleton-1215a3b+tree-sitter-0.25.0+syntax-v9"
    inputs["@designDocuments"] = "markdown-v1"
    inputs["@indexer"] = "snapshot-lifecycle-v2"
    inputs["@c4"] = "backstage-v3+structurizr-v8"
    inputs["@swiftpm"] = "literal-manifest-v1"
    inputs["@cfg"] = ControlFlowProvider.version
    inputs["@toolchain"] = "swift-6.4.1"
    return (sources.sorted { $0.path < $1.path }, catalogs.sorted { $0.path < $1.path }, sequenceFiles, inputs, diagnostics)
  }
}
