import ArchitectureCore
import ArchitectureFrontend
import ArchitectureIR
import ArchitectureStore
import Foundation

public actor WorkspaceIndexer {
  public let paths: WorkspacePaths
  public let store: any GraphStore
  private let provider: any FrontendProvider
  private var generation = 0
  private var current: Snapshot?
  private var reconciling = false
  private var diskChecked = false
  private var pending = false
  private var completedSources = 0, totalSources = 0, runningWorkers = 0
  public init(
    paths: WorkspacePaths, store: any GraphStore,
    provider: any FrontendProvider = SkeletonFrontend()
  ) {
    self.paths = paths
    self.store = store
    self.provider = provider
  }
  public func status() -> JSONValue {
    .object([
      "workspaceID": .string(paths.workspaceID),
      "snapshotID": current.map { .string($0.id) } ?? .null,
      "desiredRevision": .number(Double(generation)),
      "publishedRevision": .number(Double(current?.generation ?? 0)),
      "pending": .bool(pending), "reconciling": .bool(reconciling),
      "freshness": .string(diskChecked && !pending ? "current" : "stale"),
      "diskReconciled": .bool(diskChecked), "completedSources": .number(Double(completedSources)),
      "totalSources": .number(Double(totalSources)),
      "runningWorkers": .number(Double(runningWorkers)),
    ])
  }
  public func reconcile() async throws -> Snapshot {
    if reconciling {
      while reconciling { try await Task.sleep(for: .milliseconds(10)) }
      guard let current else {
        throw ArchitectureError(
          "INDEX_UNAVAILABLE", "Concurrent reconciliation did not publish a snapshot.")
      }
      return current
    }
    reconciling = true
    defer { reconciling = false }
    if current == nil {
      current = try await store.latest()
      generation = current?.generation ?? 0
    }
    let configuration = try IndexConfiguration(paths: paths)
    let captured = try await capture(configuration: configuration, generation: generation + 1)
    if let current, current.inputs == captured.inputs {
      diskChecked = true
      pending = false
      return current
    }
    pending = true
    generation += 1
    let jobGeneration = generation
    let old = current
    let oldInputs = old?.inputs ?? [:]
    let oldContext = old?.contextDigest
    let contextDigest = CanonicalJSON.digest(
      try CanonicalJSON.encode(
        captured.inputs.filter {
          $0.key.hasPrefix("@")
            || [
              "Package.swift", "Package.resolved", "Cargo.toml", "Cargo.lock", "architecture.json",
            ].contains(URL(fileURLWithPath: $0.key).lastPathComponent)
        }))
    let changed = captured.sources.filter {
      oldInputs[$0.path] != $0.digest || oldContext != contextDigest
    }
    completedSources = 0
    totalSources = changed.count
    runningWorkers = 0
    var results: [String: FrontendResult] = [:]
    var failures: [String: Diagnostic] = [:]
    let provider = provider
    for start in stride(from: 0, to: changed.count, by: configuration.workers) {
      let batch = changed[start..<min(start + configuration.workers, changed.count)]
      runningWorkers = batch.count
      let outcomes = await withTaskGroup(
        of: (String, Result<FrontendResult, ArchitectureError>).self
      ) { group in
        for source in batch {
          group.addTask {
            let input = SourceInput(
              workspaceID: source.workspaceID, path: source.path, language: source.language,
              bytes: source.bytes, contextDigest: contextDigest, generation: jobGeneration)
            do {
              try Task.checkCancellation()
              return (source.path, .success(try provider.analyze(input)))
            } catch let error as ArchitectureError { return (source.path, .failure(error)) } catch {
              return (
                source.path,
                .failure(ArchitectureError("SOURCE_PARSE_FAILED", String(describing: error)))
              )
            }
          }
        }
        var values: [(String, Result<FrontendResult, ArchitectureError>)] = []
        for await value in group {
          values.append(value)
          completedSources += 1
          runningWorkers -= 1
        }
        return values
      }
      for (path, outcome) in outcomes {
        switch outcome {
        case .success(let result): results[path] = result
        case .failure(let error):
          failures[path] = Diagnostic(error.code, error.message, scope: path)
        }
      }
    }
    try Task.checkCancellation()
    let confirmed = try await capture(
      configuration: try IndexConfiguration(paths: paths), generation: jobGeneration)
    guard captured.inputs == confirmed.inputs, generation == jobGeneration else {
      throw ArchitectureError(
        "INPUT_CHANGED_DURING_ANALYSIS",
        "Disk changed during parsing; the completed job was discarded.", exitCode: 7)
    }
    for diagnostic in captured.diagnostics where diagnostic.code == "RESOURCE_LIMIT" {
      failures[diagnostic.scope] = diagnostic
    }
    let sourcePaths = Set(captured.sources.map(\.path)).union(failures.keys)
    let updated = Set(results.keys)
    let retainedPaths = sourcePaths.subtracting(updated)
    var nodeMap: [String: Entity] = [:]
    var factMap: [String: Fact] = [:]
    var evidenceMap: [String: Evidence] = [:]
    var coverage: [Coverage] = []
    if let old {
      let oldEntities = Dictionary(uniqueKeysWithValues: old.entities.map { ($0.id, $0) })
      let oldEvidence = Dictionary(uniqueKeysWithValues: old.evidence.map { ($0.id, $0) })
      let deletedPaths = Set(old.entities.compactMap { $0.anchor?.path }).subtracting(sourcePaths)
      let invalidatedPaths = updated.union(deletedPaths)
      func deletedEndpoint(_ id: String) -> Bool {
        oldEntities[id]?.anchor.map { deletedPaths.contains($0.path) } == true
      }
      let retainedFacts = old.facts.filter { fact in
        if deletedEndpoint(fact.source) || deletedEndpoint(fact.target) { return false }
        if [CatalogContext.producer, StructurizrContext.producer, SwiftPMManifest.producer].contains(fact.producer) { return false }
        if fact.producer == "project.metadata", old.contextDigest != contextDigest { return false }
        if fact.producer == provider.identity { return retainedPaths.contains(fact.scope) }
        if ["project.filesystem", "design.configuration", LocalSourceImports.producer].contains(fact.producer) {
          return false
        }
        return !invalidatedPaths.contains(fact.scope)
          && !fact.evidenceIDs.contains { id in
            oldEvidence[id].map {
              invalidatedPaths.contains($0.anchor?.path ?? "")
            } ?? false
          }
      }
      let retainedIDs = Set(retainedFacts.flatMap { [$0.source, $0.target] })
      for node in old.entities
      where retainedIDs.contains(node.id)
        || node.anchor.map({ retainedPaths.contains($0.path) }) == true
      { nodeMap[node.id] = node }
      for fact in retainedFacts { factMap[fact.id] = fact }
      let evidenceIDs = Set(retainedFacts.flatMap(\.evidenceIDs))
      for item in old.evidence
      where evidenceIDs.contains(item.id)
        || item.anchor.map({ retainedPaths.contains($0.path) }) == true
      {
        let stale =
          item.anchor.map { failures[$0.path] != nil || old.contextDigest != contextDigest }
          ?? (old.contextDigest != contextDigest)
        evidenceMap[item.id] = Evidence(
          id: item.id, producer: item.producer, version: item.version,
          inputDigest: item.inputDigest, contextDigest: item.contextDigest, basis: item.basis,
          freshness: stale ? "stale" : item.freshness, anchor: item.anchor,
          diagnostics: item.diagnostics)
      }
      for item in old.coverage
      where retainedPaths.contains(item.scope)
        || retainedFacts.contains(where: { $0.producer == item.producer && $0.scope == item.scope })
      {
        let failed =
          failures[item.scope] != nil
          || oldEntities[item.scope]?.anchor.map { failures[$0.path] != nil } == true
        coverage.append(
          Coverage(
            producer: item.producer, scope: item.scope, language: item.language,
            freshness: failed || old.contextDigest != contextDigest
              ? "stale" : item.freshness,
            completeness: failed ? "failed" : item.completeness,
            exclusions: item.exclusions,
            diagnostics: failures[item.scope].map { [$0] } ?? item.diagnostics))
      }
    }
    for path in results.keys.sorted() {
      guard let result = results[path] else { continue }
      for node in result.entities { nodeMap[node.id] = node }
      for fact in result.facts { factMap[fact.id] = fact }
      for evidence in result.evidence { evidenceMap[evidence.id] = evidence }
      coverage.append(result.coverage)
    }
    for (path, diagnostic) in failures where !coverage.contains(where: { $0.scope == path }) {
      coverage.append(
        Coverage(
          producer: provider.identity, scope: path,
          language: WorkspaceScanner.sourceLanguage(path) ?? "none", freshness: "unknown",
          completeness: "failed", diagnostics: [diagnostic]))
    }
    let root = Entity(
      id: paths.workspaceID, kind: "workspace", language: "none",
      name: paths.root.lastPathComponent, identityKey: paths.workspaceID + ":workspace",
      entityRevision: contextDigest)
    nodeMap[root.id] = root
    let projectEvidenceID = CanonicalJSON.identity("project:" + contextDigest)
    evidenceMap[projectEvidenceID] = Evidence(
      id: projectEvidenceID, producer: "project.filesystem", inputDigest: contextDigest,
      contextDigest: contextDigest, basis: "syntax")
    func containment(_ from: String, _ to: String, producer: String = "project.filesystem") {
      let id = CanonicalJSON.identity(producer + ":" + from + ":" + to)
      factMap[id] = Fact(
        id: id, producer: producer, scope: "workspace",
        kind: producer == "design.configuration" ? "memberOf" : "contains", source: from,
        target: to, revision: contextDigest, evidenceIDs: [projectEvidenceID])
    }
    var packages: [(String, Entity)] = []
    for path in captured.inputs.keys.sorted()
    where ["Package.swift", "Cargo.toml"].contains(URL(fileURLWithPath: path).lastPathComponent) {
      let directory = (path as NSString).deletingLastPathComponent
      let key = paths.workspaceID + ":package-manifest:" + path
      let package = Entity(
        id: CanonicalJSON.identity(key), kind: "package",
        language: path.hasSuffix("swift") ? "swift" : "rust",
        name: directory.isEmpty ? paths.root.lastPathComponent : directory, identityKey: key,
        entityRevision: captured.inputs[path]!,
        attributes: [
          "project.context": .string(
            "unresolved: manifest evaluation requires explicit workspace trust"),
          "project.manifest": .string(path),
        ])
      nodeMap[package.id] = package
      packages.append((directory, package))
      containment(root.id, package.id)
    }
    var filesByPackage: [String: [Entity]] = [:]
    for node in Array(nodeMap.values) where node.kind == "file" {
      let package = packages.filter { $0.0.isEmpty || node.name.hasPrefix($0.0 + "/") }.max {
        $0.0.count < $1.0.count
      }?.1
      containment(package?.id ?? root.id, node.id)
      if let package { filesByPackage[package.id, default: []].append(node) }
    }
    let evaluatedManifests = Set(factMap.values.filter { $0.producer == "project.metadata" }.map(\.scope))
    let manifestInputs = Dictionary(uniqueKeysWithValues: captured.catalogs.filter { $0.language == "swift" }.map { ($0.path, $0) })
    for (_, package) in packages {
      guard let manifest = package.attributes["project.manifest"]?.string, !evaluatedManifests.contains(manifest),
        let input = manifestInputs[manifest] else { continue }
      do {
        let result = try SwiftPMManifest.analyze(input, package: package, files: filesByPackage[package.id, default: []], contextDigest: contextDigest)
        for entity in result.entities { nodeMap[entity.id] = entity }
        for fact in result.facts { factMap[fact.id] = fact }
        for item in result.evidence { evidenceMap[item.id] = item }
        coverage.append(result.coverage)
      } catch let error as ArchitectureError {
        coverage.append(Coverage(producer: SwiftPMManifest.producer, scope: manifest, language: "swift", completeness: "failed",
          diagnostics: [Diagnostic(error.code, error.message, scope: manifest)]))
      }
    }
    for group in configuration.value["designGroups"].array {
      guard let id = group["id"].string, let label = group["label"].string else {
        throw ArchitectureError(
          "INVALID_CONFIGURATION", "Design group requires id and label.", exitCode: 2)
      }
      let key = paths.workspaceID + ":design:" + id
      let groupID = CanonicalJSON.identity(key)
      nodeMap[groupID] = Entity(
        id: groupID, kind: "designGroup", language: "none", name: label, identityKey: key,
        entityRevision: configuration.digest, attributes: ["basis": .string("designDeclared")])
      for node in Array(nodeMap.values) {
        guard let path = node.anchor?.path else { continue }
        if group["selectors"].array.contains(where: {
          $0["pathGlob"].string.map { configuration.matches(path, glob: $0) } ?? false
        }) {
          containment(node.id, groupID, producer: "design.configuration")
        }
      }
    }
    for fact in try LocalSourceImports.facts(nodes: nodeMap, inputs: captured.inputs, evidence: evidenceMap) {
      factMap[fact.id] = fact
    }
    var mapDiagnostics: [Diagnostic] = []
    coverage.removeAll { [CatalogContext.producer, StructurizrContext.producer].contains($0.producer) }
    if captured.inputs["@mapCaptureFailure"] == nil, let dsl = captured.catalogs.first(where: { $0.path == WorkspacePaths.architectureModelFilename }) {
      do {
        let map = try StructurizrContext(workspaceID: paths.workspaceID, input: dsl, catalogs: captured.catalogs, contextDigest: contextDigest,
          indexed: nodeMap, inputs: captured.inputs, failedSources: Set(failures.keys))
        for node in map.nodes { nodeMap[node.id] = node }
        for fact in map.facts { factMap[fact.id] = fact }
        for item in map.evidence { evidenceMap[item.id] = item }
      } catch let error as ArchitectureError {
        mapDiagnostics.append(Diagnostic(error.code, error.message, scope: dsl.path))
      }
      coverage.append(Coverage(producer: StructurizrContext.producer, scope: "workspace", language: "structurizr",
        freshness: "current", completeness: "partial", exclusions: ["Declared model; runtime traffic is unobserved."], diagnostics: mapDiagnostics))
    } else if captured.inputs[WorkspacePaths.architectureModelFilename] == nil {
      let catalog = try CatalogContext(workspaceID: paths.workspaceID, inputs: captured.catalogs, contextDigest: contextDigest)
      mapDiagnostics = catalog.diagnostics
      coverage.append(Coverage(producer: CatalogContext.producer, scope: "workspace", language: "catalog",
        freshness: "current", completeness: "partial",
        exclusions: ["Workspace catalog declarations only; external clients and observed traffic are outside this scope."],
        diagnostics: catalog.diagnostics))
      for node in catalog.nodes { nodeMap[node.id] = node }
      for fact in catalog.facts { factMap[fact.id] = fact }
      for item in catalog.evidence { evidenceMap[item.id] = item }
    }
    let nodes = nodeMap.values.sorted { $0.id < $1.id }
    let facts = factMap.values.filter { nodeMap[$0.source] != nil && nodeMap[$0.target] != nil }
      .sorted { $0.id < $1.id }
    coverage.append(
      Coverage(
        producer: "project.filesystem", scope: "workspace", language: "none",
        completeness: "partial",
        exclusions: [
          "excluded/hidden/generated directories", "manifest execution without trust",
          "semantic providers not configured",
        ]))
    let snapshot = Snapshot(
      id: UUID().uuidString, workspaceID: paths.workspaceID, generation: jobGeneration,
      contextDigest: contextDigest, inputs: captured.inputs, entities: nodes, facts: facts,
      evidence: evidenceMap.values.sorted { $0.id < $1.id },
      coverage: coverage.sorted { ($0.scope, $0.producer) < ($1.scope, $1.producer) },
      diagnostics: mapDiagnostics + captured.diagnostics + failures.values.sorted { $0.scope < $1.scope })
    try await store.publish(snapshot)
    current = snapshot
    diskChecked = true
    pending = false
    return snapshot
  }
  public func snapshot(_ id: String? = nil) async throws -> Snapshot {
    if let id { return try await store.load(id) }
    if let current { return current }
    throw ArchitectureError(
      "INDEX_PENDING",
      "The initial workspace snapshot is still being prepared; inspect workspace.status and retry after publication.",
      exitCode: 6)
  }
  public func cfg(_ id: String) async throws -> Snapshot {
    let snapshot = try await reconcile()
    reconciling = true
    defer { reconciling = false }
    guard let function = snapshot.entities.first(where: { $0.id == id }),
      let anchor = function.anchor, ["function", "method"].contains(function.kind)
    else {
      throw ArchitectureError("INVALID_ARGUMENT", "CFG requires a callable entity.", exitCode: 2)
    }
    if ControlFlowProvider().hasSupportedGraph(for: id, in: snapshot),
      snapshot.coverage.contains(where: {
        $0.producer == "cfg.tree-sitter" && $0.scope == id && $0.freshness == "current"
      })
    {
      return snapshot
    }
    let bytes = try Data(contentsOf: paths.resolve(anchor.path))
    let input = SourceInput(
      workspaceID: paths.workspaceID, path: anchor.path, language: function.language, bytes: bytes,
      contextDigest: snapshot.contextDigest, generation: generation)
    let result = try ControlFlowProvider().analyze(input, function: function)
    let confirmed = try Data(contentsOf: paths.resolve(anchor.path))
    guard CanonicalJSON.digest(confirmed) == input.digest else {
      throw ArchitectureError(
        "INPUT_CHANGED_DURING_ANALYSIS", "CFG input changed; result discarded.", exitCode: 7)
    }
    let oldFacts = snapshot.facts.filter { !($0.producer == "cfg.tree-sitter" && $0.scope == id) }
    let oldBlockIDs = Set(
      snapshot.entities.filter { $0.attributes["cfg.functionID"]?.string == id }.map(\.id))
    generation += 1
    let published = Snapshot(
      id: UUID().uuidString, workspaceID: paths.workspaceID, generation: generation,
      contextDigest: snapshot.contextDigest, inputs: snapshot.inputs,
      entities: snapshot.entities.filter { !oldBlockIDs.contains($0.id) } + result.entities,
      facts: oldFacts + result.facts,
      evidence: snapshot.evidence.filter { !result.evidence.map(\.id).contains($0.id) }
        + result.evidence,
      coverage: snapshot.coverage.filter { !($0.producer == "cfg.tree-sitter" && $0.scope == id) }
        + [result.coverage], diagnostics: snapshot.diagnostics)
    try await store.publish(published)
    current = published
    return published
  }
  public func publishSupplement(_ result: FrontendResult, base: Snapshot) async throws -> Snapshot {
    let checked = try await reconcile()
    guard checked.id == base.id else {
      throw ArchitectureError(
        "INPUT_CHANGED_DURING_ANALYSIS", "Inputs changed during supplementary analysis.",
        exitCode: 7)
    }
    reconciling = true
    defer { reconciling = false }
    let producer = result.coverage.producer
    let scope = result.coverage.scope
    let evaluated = Set(result.facts.map(\.scope))
    func replaces(_ fact: Fact) -> Bool {
      if producer == "project.metadata" {
        return fact.producer == producer || (fact.producer == SwiftPMManifest.producer && evaluated.contains(fact.scope))
      }
      return fact.producer == producer && fact.scope == scope
    }
    let replaced = checked.facts.filter(replaces)
    let oldOwned = Set(replaced.map(\.target)).subtracting(
      Set(
        checked.facts.filter { !replaces($0) }.flatMap {
          [$0.source, $0.target]
        }))
    var entities = Dictionary(
      uniqueKeysWithValues: checked.entities.filter { !oldOwned.contains($0.id) }.map {
        ($0.id, $0)
      })
    for entity in result.entities { entities[entity.id] = entity }
    generation += 1
    let next = Snapshot(
      id: UUID().uuidString, workspaceID: checked.workspaceID, generation: generation,
      contextDigest: checked.contextDigest, inputs: checked.inputs,
      entities: entities.values.sorted { $0.id < $1.id },
      facts: checked.facts.filter { !replaces($0) }
        + result.facts,
      evidence: checked.evidence.filter { !Set(replaced.flatMap(\.evidenceIDs)).contains($0.id) }
        + result.evidence,
      coverage: checked.coverage.filter { item in
        !(item.producer == producer && item.scope == scope)
          && !(producer == "project.metadata" && item.producer == SwiftPMManifest.producer && evaluated.contains(item.scope))
      } + [
        result.coverage
      ], diagnostics: checked.diagnostics)
    try await store.publish(next)
    current = next
    return next
  }

  public func publishedSnapshot() -> Snapshot? { current }
  private func capture(configuration: IndexConfiguration, generation: Int) async throws -> (
    sources: [SourceInput], catalogs: [SourceInput], inputs: [String: String], diagnostics: [Diagnostic]
  ) {
    let paths = paths
    return try await withThrowingTaskGroup(
      of: (sources: [SourceInput], catalogs: [SourceInput], inputs: [String: String], diagnostics: [Diagnostic]).self
    ) { group in
      group.addTask(priority: .utility) {
        try WorkspaceScanner().capture(
          paths: paths, configuration: configuration, generation: generation)
      }
      guard let result = try await group.next() else { throw CancellationError() }
      return result
    }
  }

}
