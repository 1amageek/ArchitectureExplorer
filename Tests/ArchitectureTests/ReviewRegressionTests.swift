import ArchitectureCore
import ArchitectureFrontend
import ArchitectureGraph
import ArchitectureIR
import ArchitectureIndexer
import ArchitectureService
import ArchitectureStore
import Foundation
import Testing

struct ReviewRegressionTests {
  private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func remove(_ root: URL) {
    do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) }
  }
  private func graph() -> Snapshot {
    let entities =
      ["A", "B", "C"].map {
        Entity(
          id: $0, kind: "type", language: "swift", name: $0, identityKey: $0, entityRevision: "1")
      }
      + ["a", "b"].map {
        Entity(
          id: $0, kind: "method", language: "swift", name: $0, identityKey: $0, entityRevision: "1")
      }
    let facts = [
      Fact(
        id: "Aa", producer: "fixture", scope: "fixture", kind: "contains", source: "A", target: "a",
        revision: "1"),
      Fact(
        id: "Bb", producer: "fixture", scope: "fixture", kind: "contains", source: "B", target: "b",
        revision: "1"),
      Fact(
        id: "AB", producer: "fixture", scope: "fixture", kind: "calls", source: "A", target: "B",
        revision: "1"),
      Fact(
        id: "BC", producer: "fixture", scope: "fixture", kind: "calls", source: "B", target: "C",
        revision: "1"),
      Fact(
        id: "ab", producer: "fixture", scope: "fixture", kind: "calls", source: "a", target: "b",
        revision: "1"),
    ]
    return Snapshot(
      id: "fixture", workspaceID: "review", generation: 1, contextDigest: "context", inputs: [:],
      entities: entities, facts: facts, evidence: [], coverage: [])
  }
  @Test(.timeLimit(.minutes(1))) func pathRespectsDirectionDepthAndIdentity() throws {
    let snapshot = graph()
    for (from, to, direction, depth, expected) in [
      ("A", "C", "outgoing", 2, Set(["A", "B", "C"])),
      ("C", "A", "incoming", 2, Set(["A", "B", "C"])),
      ("B", "A", "incoming", 1, Set(["A", "B"])),
      ("B", "A", "both", 1, Set(["A", "B"])),
      ("B", "A", "outgoing", 1, Set<String>()),
      ("C", "A", "incoming", 1, Set<String>()),
      ("A", "A", "incoming", 0, Set(["A"])),
    ] {
      let result = try GraphEngine().view(
        GraphQuery(
          method: "graph.path", focus: from, kinds: ["calls"], direction: direction, depth: depth,
          target: to), snapshot: snapshot)
      #expect(Set(result.nodes.map(\.id)) == expected)
    }
  }
  @Test(.timeLimit(.minutes(1))) func overviewCountsEachSourceFactExactlyOnce() throws {
    let snapshot = graph()
    let view = try GraphEngine().view(
      GraphQuery(method: "graph.overview", level: "component"), snapshot: snapshot)
    let relations = view.edges.filter { $0.source == "A" && $0.target == "B" }
    #expect(relations.count == 1)
    let relation = try #require(relations.first)
    #expect(relation.attributes["aggregate.count"]?.int == 2)
    #expect(
      Set(relation.attributes["aggregate.sourceEdgeIDs"]?.array.compactMap(\.string) ?? []) == [
        "AB", "ab",
      ])
    let functions = try GraphEngine().view(
      GraphQuery(method: "graph.overview", level: "function"), snapshot: snapshot)
    #expect(functions.edges.count == 1)
    #expect(functions.edges.first?.attributes["aggregate.count"]?.int == 1)
    let original = try GraphEngine().view(
      GraphQuery(method: "graph.neighbors", focus: "A", direction: "both", depth: 2),
      snapshot: snapshot)
    #expect(!original.edges.contains { $0.producer == "graph.aggregate" })
    #expect(original.edges.contains { $0.id == "AB" })
  }
  @Test(.timeLimit(.minutes(1))) func whileConditionsHaveOrderedTrueAndFalsePaths() throws {
    let source = "func loop(_ a: Bool, _ b: Bool) { while a, b { continue }; return }"
    let input = SourceInput(
      workspaceID: "review", path: "Flow.swift", language: "swift", bytes: Data(source.utf8),
      contextDigest: "context", generation: 1)
    let syntax = try SkeletonFrontend().analyze(input)
    let function = try #require(syntax.entities.first { $0.kind == "function" })
    let cfg = try ControlFlowProvider().analyze(input, function: function)
    func node(_ name: String) throws -> String {
      try #require(cfg.entities.first { $0.name == name }?.id)
    }
    let a = try node("a")
    let b = try node("b")
    let continued = try node("continue")
    let returned = try node("return")
    for (from, to, branch) in [
      (a, b, "true"), (b, continued, "true"), (continued, a, "continue"), (a, returned, "false"),
      (b, returned, "false"),
    ] {
      #expect(
        cfg.facts.contains {
          $0.source == from && $0.target == to && $0.attributes["cfg.branch"]?.string == branch
        })
    }
    #expect(cfg.coverage.completeness == "completeWithinScope")
  }
  @Test(.timeLimit(.minutes(1))) func failedAndDeletedSourcesInvalidateSupplementOwners()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let source = root.appendingPathComponent("A.swift")
    let other = root.appendingPathComponent("B.swift")
    try Data("func a() -> Int { return 1 }".utf8).write(to: source)
    try Data("func b() -> Int { return 2 }".utf8).write(to: other)
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let initial = try await indexer.reconcile()
    let a = try #require(initial.entities.first { $0.name == "a" })
    let b = try #require(initial.entities.first { $0.name == "b" })
    let evidence = Evidence(
      id: "supplement", producer: "semantic.fixture", inputDigest: "fixture",
      contextDigest: initial.contextDigest, basis: "semantic", freshness: "unknown",
      anchor: b.anchor)
    let supplement = FrontendResult(
      entities: [],
      facts: [
        Fact(
          id: "reference", producer: "semantic.fixture", scope: b.id, kind: "references",
          source: b.id, target: a.id, revision: "1", evidenceIDs: [evidence.id])
      ], evidence: [evidence],
      coverage: Coverage(
        producer: "semantic.fixture", scope: b.id, language: "swift", freshness: "unknown"))
    _ = try await indexer.publishSupplement(supplement, base: initial)
    _ = try await indexer.cfg(a.id)
    try Data("func a( {".utf8).write(to: source)
    let failed = try await indexer.reconcile()
    #expect(
      failed.coverage.contains {
        $0.producer == "cfg.tree-sitter" && $0.scope == a.id && $0.freshness == "stale"
      })
    try FileManager.default.removeItem(at: source)
    let deleted = try await indexer.reconcile()
    #expect(!deleted.entities.contains { $0.anchor?.path == "A.swift" })
    #expect(!deleted.facts.contains { $0.source == a.id || $0.target == a.id || $0.scope == a.id })
    #expect(deleted.entities.contains { $0.id == b.id })
    try GraphValidation.validate(deleted)
  }
  @Test(.timeLimit(.minutes(1))) func historicalCFGNeverReconcilesOrSubstitutesLiveInputs()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let source = root.appendingPathComponent("Flow.swift")
    try Data("func value() -> Int { return 1 }".utf8).write(to: source)
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let service = ArchitectureService(paths: paths, store: store)
    await service.refresh()
    let initial = try #require(try await store.latest())
    let function = try #require(initial.entities.first { $0.kind == "function" })
    let original = try await service.handle(
      "graph.cfg", params: .object(["focus": .string(function.id)]))
    let pinnedID = try #require(original["snapshotID"].string)
    try Data("func value() -> Int { return 2 }".utf8).write(to: source)
    await service.refresh()
    let before = try #require(try await store.latest())
    let pinned = try await service.handle(
      "graph.cfg",
      params: .object(["focus": .string(function.id), "snapshotID": .string(pinnedID)]))
    #expect(pinned["snapshotID"].string == pinnedID)
    #expect(pinned["nodes"].array.contains { $0["name"].string == "return 1" })
    #expect(!pinned["nodes"].array.contains { $0["name"].string == "return 2" })
    do {
      _ = try await service.handle(
        "graph.cfg",
        params: .object(["focus": .string(function.id), "snapshotID": .string(initial.id)]))
      Issue.record("A pinned snapshot without a recorded CFG must fail explicitly.")
    } catch let error as ArchitectureError { #expect(error.code == "CFG_UNAVAILABLE") }
    #expect(try await store.latest()?.id == before.id)
  }
  @Test(.timeLimit(.minutes(1))) func importedGenerationsDoNotChangeLivePublicationOrRetention()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let source = root.appendingPathComponent("Flow.swift")
    try Data("func value() -> Int { return 1 }".utf8).write(to: source)
    let paths = try WorkspacePaths(root.path)
    let database = root.appendingPathComponent("store.sqlite").path
    let store = try SQLiteGraphStore(path: database, workspaceID: paths.workspaceID, retention: 2)
    let service = ArchitectureService(paths: paths, store: store)
    await service.refresh()
    let initial = try #require(try await store.latest())
    for number in 1...3 {
      let imported = Snapshot(
        id: "imported-\(number)", workspaceID: initial.workspaceID, generation: 1_000_000 + number,
        contextDigest: initial.contextDigest, inputs: initial.inputs, entities: initial.entities,
        facts: initial.facts, evidence: initial.evidence, coverage: initial.coverage)
      _ = try await service.handle(
        "workspace.import", params: .object(["snapshot": try JSONValue.encode(imported)]))
      #expect(try await store.latest()?.id == initial.id)
    }
    await #expect(throws: ArchitectureError.self) { try await store.load("imported-1") }
    #expect(try await store.load("imported-3").generation == 1_000_003)
    let existing = try #require(initial.entities.first)
    let conflicting = Entity(
      id: "conflicting-id", kind: existing.kind, language: existing.language, name: existing.name,
      identityKey: existing.identityKey, entityRevision: "bad")
    let rejected = Snapshot(
      id: "rejected-import", workspaceID: initial.workspaceID, generation: 2_000_000,
      contextDigest: initial.contextDigest, inputs: [:], entities: [conflicting], facts: [],
      evidence: [], coverage: [])
    await #expect(throws: ArchitectureError.self) {
      _ = try await service.handle(
        "workspace.import", params: .object(["snapshot": try JSONValue.encode(rejected)]))
    }
    await #expect(throws: ArchitectureError.self) { try await store.load(rejected.id) }
    #expect(try await store.latest()?.id == initial.id)
    #expect(try await store.load("imported-3").generation == 1_000_003)
    try Data("func value() -> Int { return 2 }".utf8).write(to: source)
    await service.refresh()
    let updated = try #require(try await store.latest())
    #expect(updated.id != initial.id)
    #expect(updated.generation == initial.generation + 1)
    #expect(try await store.history() == [updated.id, initial.id])
    let reopened = try SQLiteGraphStore(
      path: database, workspaceID: paths.workspaceID, retention: 2)
    #expect(try await reopened.latest()?.id == updated.id)
    #expect(try await reopened.load("imported-3").generation == 1_000_003)
  }
  @Test(.timeLimit(.minutes(1))) func importIntoEmptyStoreDoesNotBecomeLiveHead() async throws {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: "review")
    let imported = graph()
    try await store.importSnapshot(imported)
    #expect(try await store.latest() == nil)
    #expect(try await store.history().isEmpty)
    #expect(try await store.load(imported.id) == imported)
    let live = Snapshot(
      id: "live", workspaceID: "review", generation: 1, contextDigest: imported.contextDigest,
      inputs: imported.inputs, entities: imported.entities, facts: imported.facts,
      evidence: imported.evidence, coverage: imported.coverage)
    try await store.publish(live)
    #expect(try await store.latest()?.id == live.id)
  }
  @Test(.timeLimit(.minutes(1))) func obsoleteCacheFormatIsRejectedWithoutMigration()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let database = root.appendingPathComponent("legacy.sqlite").path
    let legacy = graph()
    let payload = String(decoding: try CanonicalJSON.encode(legacy), as: UTF8.self)
      .replacingOccurrences(of: "'", with: "''")
    _ = try await BoundedProcess.run(
      executable: "/usr/bin/sqlite3",
      arguments: [
        database,
        "CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); INSERT INTO metadata VALUES('schema','1.0'); CREATE TABLE snapshots(id TEXT PRIMARY KEY,generation INTEGER NOT NULL,payload TEXT NOT NULL); INSERT INTO snapshots VALUES('fixture',1,'\(payload)');",
      ], directory: root, timeout: .seconds(5))
    #expect(throws: ArchitectureError.self) { try SQLiteGraphStore(path: database, workspaceID: "review") }
    let version = try await BoundedProcess.run(executable: "/usr/bin/sqlite3", arguments: [database, "SELECT value FROM metadata WHERE key='schema';"], directory: root, timeout: .seconds(5))
    #expect(String(decoding: version, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1.0")
  }
  @Test(.timeLimit(.minutes(1))) func upgradeReconcilesUnchangedInputsWithLegacyGhostCFG()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    let removed = root.appendingPathComponent("A.swift")
    try Data("func a() {}".utf8).write(to: removed)
    try Data("func b() {}".utf8).write(to: root.appendingPathComponent("B.swift"))
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let originalIndexer = WorkspaceIndexer(paths: paths, store: store)
    let initial = try await originalIndexer.reconcile()
    let id = try #require(initial.entities.first { $0.name == "a" }?.id)
    let cfg = try await originalIndexer.cfg(id)
    try FileManager.default.removeItem(at: removed)
    var inputs = cfg.inputs
    inputs.removeValue(forKey: "A.swift")
    inputs.removeValue(forKey: "@indexer")
    inputs.removeValue(forKey: "@cfg")
    let legacy = Snapshot(
      id: "legacy-ghost", workspaceID: cfg.workspaceID, generation: cfg.generation + 1,
      contextDigest: cfg.contextDigest, inputs: inputs, entities: cfg.entities, facts: cfg.facts,
      evidence: cfg.evidence, coverage: cfg.coverage)
    try await store.publish(legacy)
    let upgraded = WorkspaceIndexer(paths: paths, store: store)
    let corrected = try await upgraded.reconcile()
    #expect(corrected.id != legacy.id)
    #expect(!corrected.entities.contains { $0.anchor?.path == "A.swift" })
    #expect(corrected.entities.contains { $0.name == "b" })
    #expect(try await store.load(legacy.id).entities.contains { $0.id == id })
  }
  @Test(.timeLimit(.minutes(1))) func obsoleteRecordedCFGIsRejectedWithoutReplacingPinnedData()
    async throws
  {
    let root = try temporaryDirectory()
    defer { remove(root) }
    try Data("func value() -> Int { return 1 }".utf8).write(
      to: root.appendingPathComponent("Flow.swift"))
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let initial = try await indexer.reconcile()
    let id = try #require(initial.entities.first { $0.kind == "function" }?.id)
    let cfg = try await indexer.cfg(id)
    let oldEvidence = cfg.evidence.map { item in
      Evidence(
        id: item.id, producer: item.producer,
        version: item.producer == "cfg.tree-sitter" ? "1.0" : item.version,
        inputDigest: item.inputDigest, contextDigest: item.contextDigest, basis: item.basis,
        freshness: item.freshness, anchor: item.anchor, diagnostics: item.diagnostics)
    }
    let obsolete = Snapshot(
      id: "obsolete-cfg", workspaceID: cfg.workspaceID, generation: cfg.generation,
      contextDigest: cfg.contextDigest, inputs: cfg.inputs, entities: cfg.entities,
      facts: cfg.facts, evidence: oldEvidence, coverage: cfg.coverage)
    try await store.importSnapshot(obsolete)
    let service = ArchitectureService(paths: paths, store: store)
    for method in ["graph.cfg", "graph.export"] {
      let query: JSONValue = .object([
        "method": .string("graph.cfg"), "focus": .string(id), "snapshotID": .string(obsolete.id),
      ])
      let parameters =
        method == "graph.cfg" ? query : .object(["query": query, "format": .string("json")])
      do {
        _ = try await service.handle(method, params: parameters)
        Issue.record("Obsolete CFG must not be accepted as supported.")
      } catch let error as ArchitectureError { #expect(error.code == "CFG_UNAVAILABLE") }
    }
    #expect(try await store.load(obsolete.id).evidence == oldEvidence)
  }

}
