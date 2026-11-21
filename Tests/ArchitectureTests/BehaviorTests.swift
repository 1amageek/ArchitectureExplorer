import ArchitectureExtensions
import ArchitectureCore
import ArchitectureFrontend
import ArchitectureGraph
import ArchitectureIR
import ArchitectureIndexer
import ArchitectureService
import ArchitectureStore
import Darwin
import Foundation
import Synchronization
import Testing

struct BehaviorTests {
  func input(_ source: String, language: String = "swift") -> SourceInput {
    SourceInput(
      workspaceID: "test", path: language == "swift" ? "Flow.swift" : "flow.rs", language: language,
      bytes: Data(source.utf8), contextDigest: "context", generation: 1)
  }
  func temp() throws -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return path
  }
  func snapshot(_ result: FrontendResult) -> Snapshot {
    Snapshot(
      id: "snapshot", workspaceID: "test", generation: 1, contextDigest: "context", inputs: [:],
      entities: result.entities, facts: result.facts, evidence: result.evidence,
      coverage: [result.coverage])
  }

  @Test(.timeLimit(.minutes(1))) func componentOverviewProjectsOnlyUnambiguousSourceReferences() async throws {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("Sources/Calendar")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    func write(_ name: String, _ body: String) throws {
      try Data(body.utf8).write(to: target.appendingPathComponent(name))
    }
    try write("Month.swift", """
      struct Month {
        var body: Int { Dates.start() }
        func create() { _ = Pager() }
        var axis: Axis?
        let note = "Decoy"
      }
      """)
    try write("Types.swift", "struct Dates {}\nstruct Pager {}\nstruct Axis {}\nstruct Decoy {}")
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("db.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let query = GraphQuery(method: "graph.overview", kinds: ["candidateTypeReference"], level: "component")
    func view() async throws -> GraphView {
      let snapshot = try await indexer.reconcile()
      return try GraphEngine().view(query, snapshot: snapshot)
    }
    let initial = try await view()
    let month = try #require(initial.nodes.first { $0.name == "Month" })
    let names = Dictionary(uniqueKeysWithValues: initial.nodes.map { ($0.id, $0.name) })
    #expect(Set(initial.edges.filter { $0.source == month.id }.compactMap { names[$0.target] }) == ["Dates", "Pager", "Axis"])
    let dates = try #require(initial.edges.first { names[$0.target] == "Dates" })
    #expect(dates.attributes["reference.site"]?["name"].string == "Dates")
    #expect(dates.attributes["reference.site"]?["line"].int == 2)
    #expect(!dates.evidenceIDs.isEmpty && dates.evidenceIDs.allSatisfy { id in initial.evidence.contains { $0.id == id } })
    let indexed = try await indexer.reconcile()
    let sourceFile = try #require(indexed.entities.first {
      $0.kind == "file" && $0.name.hasSuffix("Month.swift")
    })
    let ownerID = try #require(indexed.facts.first { $0.kind == "contains" && $0.target == sourceFile.id }?.source)
    for method in ["graph.overview", "graph.children"] {
      let outline = try GraphEngine().view(GraphQuery(method: method, focus: method == "graph.children" ? ownerID : nil,
        kinds: ["candidateTypeReference"], depth: 4, level: "file"), snapshot: indexed)
      #expect(outline.edges.contains { $0.id == dates.id && $0.evidenceIDs == dates.evidenceIDs })
      #expect(outline.edges.contains { $0.source == sourceFile.id && $0.target == month.id && $0.kind == "contains" })
    }
    try write("Duplicate.swift", "struct Dates {}")
    let ambiguous = try await view()
    #expect(!ambiguous.edges.contains { names[$0.target] == "Dates" })
    try write("Month.swift", "struct Month {}")
    let edited = try await view()
    #expect(edited.edges.isEmpty)
  }

  @Test(.timeLimit(.minutes(1))) func syntaxExtractsBothLanguagesAndCallSites() throws {
    for language in ["swift", "rust"] {
      let source =
        language == "swift"
        ? "struct Box { func value() -> Int { return helper(1) } }\nfunc helper(_ x: Int) -> Int { return x }"
        : "struct Box {}\nimpl Box { fn value(&self) -> i32 { return helper(1); } }\nfn helper(x: i32) -> i32 { return x; }"
      let result = try SkeletonFrontend().analyze(input(source, language: language))
      #expect(result.entities.contains { $0.kind == "type" && $0.name == "Box" })
      #expect(result.entities.contains { $0.kind == "function" && $0.name == "helper" })
      #expect(result.entities.contains { $0.kind == "callSite" })
      #expect(result.facts.contains { $0.kind == "candidateCalls" })
      #expect(!result.facts.contains { $0.kind == "calls" })
      try GraphValidation.validate(snapshot(result))
    }
  }

  @Test(.timeLimit(.minutes(1))) func entryGraphShowsDirectReferencesAcrossDeclaredSwiftTargets() async throws {
    let root = try temp()
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    func write(_ path: String, _ contents: String) throws {
      let file = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: file, options: .atomic)
    }
    func manifest(dependencies: String) throws {
      try write("Package.swift", """
        // swift-tools-version: 6.4
        import PackageDescription
        let package = Package(name: "Example", targets: [
          .executableTarget(name: "App", dependencies: \(dependencies)),
          .target(name: "Core"),
          .target(name: "Unimported"),
          .target(name: "Undeclared")
        ])
        """)
    }
    try manifest(dependencies: #"["Core", .target(name: "Unimported")]"#)
    try write("Sources/App/Entry.swift", """
      import Core
      import Undeclared
      struct Entry {
        var store = Store(repository: TaskRepository())
        var view = Workspace()
        var unrelated = ImportedWithoutDependency()
        var hidden = DeclaredWithoutImport()
      }
      """)
    try write("Sources/App/Workspace.swift", "struct Workspace {}\nstruct Aardvark {}\nstruct Another {}")
    try write("Sources/Core/Store.swift", "struct Store {}\nstruct TaskRepository {}")
    try write("Sources/Unimported/Hidden.swift", "struct DeclaredWithoutImport {}\nstruct Store {}")
    try write("Sources/Undeclared/Hidden.swift", "struct ImportedWithoutDependency {}\nstruct Store {}")
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let snapshot = try await indexer.reconcile()
    let entry = try #require(snapshot.entities.first { $0.name == "Entry" })
    let query = GraphQuery(method: "graph.overview", focus: entry.id, limit: 4, level: "component")
    let engine = GraphEngine()
    let view = try engine.view(query, snapshot: snapshot)
    let expected: Set<String> = ["Store", "TaskRepository", "Workspace"]
    #expect(Set(view.nodes.map(\.name)) == expected.union(["Entry"]))
    #expect(view.extensions?["implementation.scope"]?.string == "Module · App")
    #expect(view.truncated && view.nextCursor != nil)
    let names = Dictionary(uniqueKeysWithValues: view.nodes.map { ($0.id, $0.name) })
    let references = view.edges.filter { $0.source == entry.id && $0.kind == "candidateTypeReference" }
    #expect(Set(references.compactMap { names[$0.target] }) == expected)
    let crossModule = try #require(references.first { names[$0.target] == "Store" })
    #expect(crossModule.attributes["reference.site"]?["line"].int == 4)
    #expect(crossModule.attributes["reference.scope"]?.string == "Core")
    #expect(view.evidence.contains { crossModule.evidenceIDs.contains($0.id) && $0.anchor?.path == "Package.swift" })
    let modules = try engine.view(GraphQuery(method: "graph.overview", level: "module"), snapshot: snapshot)
    let app = try #require(modules.nodes.first { $0.name == "App" })
    let core = try #require(modules.nodes.first { $0.name == "Core" })
    #expect(modules.edges.contains { $0.kind == "dependsOn" && $0.source == app.id && $0.target == core.id })

    try manifest(dependencies: #"["Unimported"]"#)
    let changed = try await indexer.reconcile()
    let after = try engine.view(query, snapshot: changed)
    #expect(after.edges.filter { $0.source == entry.id && $0.kind == "candidateTypeReference" }.map { $0.attributes["reference.scope"]?.string } == ["App"])
    let pinned = try await indexer.snapshot(snapshot.id)
    #expect(try engine.view(query, snapshot: pinned).edges == view.edges)
  }
  @Test(.timeLimit(.minutes(1))) func declarationRolesDistinguishTypesAndCallables() throws {
    let swift = try SkeletonFrontend().analyze(input("""
      class Reference {
        init() {}
        func update() {}
      }
      struct Value {}
      enum Choice { case first }
      actor Worker {}
      protocol Service { func execute() }
      extension Value { func inspect() {} }
      func standalone() {}
      """))
    for (name, role) in [("Reference", "class"), ("Value", "struct"), ("Choice", "enum"),
                         ("Worker", "actor"), ("Service", "protocol"), ("standalone", "function"),
                         ("update", "method"), ("init", "initializer")] {
      #expect(swift.entities.contains { $0.name == name && $0.attributes["declaration.kind"]?.string == role })
    }
    #expect(swift.entities.contains { $0.attributes["declaration.kind"]?.string == "extension" })
    let rust = try SkeletonFrontend().analyze(input("""
      struct Value {}
      enum Choice { First }
      trait Service { fn execute(&self); }
      impl Value { fn inspect(&self) {} fn create() -> Self { Value {} } }
      mod nested { fn standalone() {} }
      """, language: "rust"))
    for role in ["struct", "enum", "trait", "implementation", "module", "method", "associatedFunction", "function"] {
      #expect(rust.entities.contains { $0.attributes["declaration.kind"]?.string == role })
    }
    #expect(rust.entities.contains { $0.name == "create" && $0.attributes["declaration.kind"]?.string == "associatedFunction" })
  }

  @Test(.timeLimit(.minutes(1))) func callableIdentitySurvivesWhitespaceAndBodyEdits() throws {
    let a = try SkeletonFrontend().analyze(input("func value(_ x: Int) -> Int { return x + 1 }"))
    let b = try SkeletonFrontend().analyze(
      input("\n\nfunc value ( _ x : Int ) -> Int { return x + 2 }"))
    let first = try #require(a.entities.first { $0.kind == "function" })
    let second = try #require(b.entities.first { $0.kind == "function" })
    #expect(first.id == second.id)
    #expect(first.entityRevision != second.entityRevision)
  }
  @Test(.timeLimit(.minutes(1))) func overloadsAndLanguagesRemainDistinct() throws {
    let result = try SkeletonFrontend().analyze(
      input(
        "func same(_ x: Int) {}\nfunc same(_ x: String) {}\nstruct A { func same(_ x: Int) {} }"))
    let functions = result.entities.filter { ["function", "method"].contains($0.kind) }
    #expect(functions.count == 3)
    #expect(Set(functions.map(\.id)).count == 3)
  }
  @Test(.timeLimit(.minutes(1))) func unicodeCRLFAnchorsSelectOriginalBytes() throws {
    let source = "// 🧭 é\r\nfunc café() -> String { return \"👨‍👩‍👧‍👦\" }\r\n"
    let value = input(source)
    let result = try SkeletonFrontend().analyze(value)
    let function = try #require(result.entities.first { $0.kind == "function" })
    let anchor = try #require(function.anchor)
    #expect(
      String(decoding: value.bytes[anchor.startByte..<anchor.endByte], as: UTF8.self)
        == "func café() -> String { return \"👨‍👩‍👧‍👦\" }")
  }
  @Test(.timeLimit(.minutes(1))) func cfgBranchesLoopsAndLoopTransfers() throws {
    for language in ["swift", "rust"] {
      let source =
        language == "swift"
        ? "func run(_ x: Int) -> Int { var n = 0; while n < x { if n == 2 { n += 1; continue }; if n == 5 { break }; n += 1 }; guard n > 0 else { return 0 }; return n }"
        : "fn run(x: i32) -> i32 { let mut n = 0; while n < x { if n == 2 { n += 1; continue; } if n == 5 { break; } n += 1; } return n; }"
      let value = input(source, language: language)
      let syntax = try SkeletonFrontend().analyze(value)
      let function = try #require(syntax.entities.first { $0.kind == "function" })
      let result = try ControlFlowProvider().analyze(value, function: function)
      let labels = Set(result.facts.compactMap { $0.attributes["cfg.branch"]?.string })
      #expect(labels.isSuperset(of: ["true", "false", "continue", "break", "return", "entry"]))
      #expect(result.coverage.completeness == "completeWithinScope")
      let nodeIDs = Set(result.entities.map(\.id))
      #expect(
        result.facts.filter { $0.kind == "controlFlow" }.allSatisfy {
          nodeIDs.contains($0.source) && nodeIDs.contains($0.target)
        })
    }
  }
  @Test(.timeLimit(.minutes(1))) func cfgRejectsUnsupportedEffectsInsteadOfInventingEdges() throws {
    for (language, source) in [
      ("swift", "func f() { defer { print(1) }; print(2) }"),
      ("swift", "func f() async { await work() }"),
      ("swift", "func f(_ a: Bool, _ b: Bool) { if a && b { return } }"),
      ("rust", "fn f() { work()?; }"), ("rust", "fn f() { for x in xs { work(x); } }"),
    ] {
      let value = input(source, language: language)
      let syntax = try SkeletonFrontend().analyze(value)
      let function = try #require(syntax.entities.first { $0.kind == "function" })
      #expect(throws: ArchitectureError.self) {
        try ControlFlowProvider().analyze(value, function: function)
      }
    }
  }
  @Test(.timeLimit(.minutes(1))) func emptySavedSourcesRemainValidInputs() throws {
    for language in ["swift", "rust"] {
      let result = try SkeletonFrontend().analyze(input("", language: language))
      #expect(result.entities.count == 1)
      #expect(result.entities.first?.kind == "file")
      #expect(result.facts.isEmpty)
      #expect(result.coverage.freshness == "current")
    }
  }

  @Test(.timeLimit(.minutes(1))) func malformedSourceIsFailure() {
    #expect(throws: ArchitectureError.self) {
      try SkeletonFrontend().analyze(input("func broken( {"))
    }
  }
  @Test(.timeLimit(.minutes(1))) func containmentCycleAndDanglingEdgesAreRejected() throws {
    let a = Entity(
      id: "a", kind: "type", language: "swift", name: "A", identityKey: "a", entityRevision: "1")
    let b = Entity(
      id: "b", kind: "type", language: "rust", name: "B", identityKey: "b", entityRevision: "1")
    let edges = [
      Fact(
        id: "ab", producer: "test", scope: "test", kind: "contains", source: "a", target: "b",
        revision: "1"),
      Fact(
        id: "ba", producer: "test", scope: "test", kind: "contains", source: "b", target: "a",
        revision: "1"),
    ]
    let value = Snapshot(
      id: "s", workspaceID: "w", generation: 1, contextDigest: "c", inputs: [:], entities: [a, b],
      facts: edges, evidence: [], coverage: [])
    #expect(throws: ArchitectureError.self) { try GraphValidation.validate(value) }
  }
  @Test(.timeLimit(.minutes(1))) func paginationIsSnapshotPinnedAndSearchIsBounded() throws {
    let source = (0..<12).map { "func f\($0)() {}" }.joined(separator: "\n")
    let result = try SkeletonFrontend().analyze(input(source))
    let value = snapshot(result)
    let first = try GraphEngine().view(
      GraphQuery(method: "graph.search", text: "f", limit: 4), snapshot: value)
    let second = try GraphEngine().view(
      GraphQuery(method: "graph.search", text: "f", limit: 4, cursor: first.nextCursor),
      snapshot: value)
    #expect(first.truncated)
    #expect(Set(first.nodes.map(\.id)).isDisjoint(with: Set(second.nodes.map(\.id))))
    #expect(throws: ArchitectureError.self) {
      try GraphEngine().view(
        GraphQuery(method: "graph.search", text: "different", limit: 4, cursor: first.nextCursor),
        snapshot: value)
    }
    #expect(throws: ArchitectureError.self) {
      try GraphEngine().view(GraphQuery(method: "graph.search", limit: 201), snapshot: value)
    }
  }
  @Test(.timeLimit(.minutes(1))) func sqlitePublicationIsAtomicAndRejectsOldGeneration()
    async throws
  {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: "test")
    let result = try SkeletonFrontend().analyze(input("func f() {}"))
    let value = snapshot(result)
    try await store.publish(value)
    await #expect(throws: ArchitectureError.self) { try await store.publish(value) }
    #expect(try await store.latest() == value)
  }
  @Test(.timeLimit(.minutes(1))) func incrementalFailureRetainsStaleAndDeletionRemovesFacts()
    async throws
  {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Test.swift")
    try Data("func value() -> Int { return 1 }".utf8).write(to: source)
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let initial = try await indexer.reconcile()
    let id = try #require(initial.entities.first { $0.kind == "function" }?.id)
    try Data("\nfunc value() -> Int { return 2 }".utf8).write(to: source)
    let edited = try await indexer.reconcile()
    #expect(edited.entities.contains { $0.id == id })
    try Data("func value( {".utf8).write(to: source)
    let broken = try await indexer.reconcile()
    #expect(broken.entities.contains { $0.id == id })
    #expect(
      broken.coverage.contains {
        $0.scope == "Test.swift" && $0.freshness == "stale" && $0.completeness == "failed"
      })
    try FileManager.default.removeItem(at: source)
    let deleted = try await indexer.reconcile()
    #expect(!deleted.entities.contains { $0.id == id })
    try GraphValidation.validate(deleted)
  }
  @Test(.timeLimit(.minutes(1))) func pathTraversalAndSymlinkEscapeAreDenied() throws {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let paths = try WorkspacePaths(root.path)
    #expect(throws: ArchitectureError.self) { try paths.resolve("../outside") }
    try FileManager.default.createSymbolicLink(
      atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/etc")
    #expect(throws: ArchitectureError.self) { try paths.resolve("escape/passwd") }
  }
  @Test(.timeLimit(.minutes(1))) func annotationReportsKeepOwnershipInTheContributionEnvelope() throws {
    let report = ExtensionAnnotation(reportedStatus: "PROVED", claim: "Externally reported claim", scope: "fixture")
    let data = try JSONValue.encode(report)
    #expect(try data.decode(ExtensionAnnotation.self) == report)
    #expect(data["provider"] == .null && data["inputFingerprint"] == .null)
    let binding = ExtensionBinding(workspaceID: "test", snapshotID: "snapshot", inputManifestDigest: "digest")
    let provider = ExtensionManifest(extensionID: "provider", displayName: "Provider", requestedPermissions: [.annotationsWrite])
    try ExtensionRules.contribution(ExtensionContribution(id: "provider:1", kind: "annotation", binding: binding, data: data), provider: provider, binding: binding)
    #expect(throws: ArchitectureError.self) { try ExtensionRules.contribution(ExtensionContribution(id: "other:1", kind: "annotation", binding: binding, data: data), provider: provider, binding: binding) }
  }
  @Test(.timeLimit(.minutes(1))) func exportsEscapeSourceLabels() throws {
    let value = GraphView(
      workspaceID: "w", snapshotID: "s", queryID: "q", freshness: "current",
      completeness: "partial",
      nodes: [
        Entity(
          id: "a", kind: "type", language: "swift", name: "</script><script>alert(1)</script>",
          identityKey: "a", entityRevision: "r")
      ], edges: [])
    let svg = try GraphExporter.text(value, format: "svg")
    let mermaid = try GraphExporter.text(value, format: "mermaid")
    let html = try GraphExporter.text(value, format: "html")
    #expect(!svg.contains("<script>"))
    #expect(!mermaid.contains("<script>"))
    #expect(!html.contains("</script><script>alert(1)</script>"))
    #expect(html.contains("ARCHITECTURE_SAVED"))
    #expect(html.contains("globalThis.ArchitectureSyntax=hljs"))
    #expect(html.contains("registerLanguage(\"swift\""))
    #expect(html.contains("registerLanguage(\"rust\""))
    #expect(!html.contains("src=\"/assets/highlight.min.js"))
  }
  @Test(.timeLimit(.minutes(1))) func lspPositionsPreserveUnicodeAndCRLF() throws {
    let bytes = Data("😀café\r\nnext".utf8)
    #expect(try SourcePositions.byteOffset(bytes, line: 0, utf16Column: 2) == 4)
    #expect(try SourcePositions.byteOffset(bytes, line: 1, utf16Column: 0) == 11)
    #expect(
      try SourcePositions.lspPosition(bytes, byteOffset: 11)
        == .object(["line": .number(1), "character": .number(0)]))
    #expect(throws: ArchitectureError.self) {
      try SourcePositions.byteOffset(bytes, line: 0, utf16Column: 1)
    }
  }
  @Test(.timeLimit(.minutes(1))) func oldJobCannotPublishAfterInputChanges() async throws {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("Flow.swift")
    try Data("func first() {}".utf8).write(to: path)
    let control = SlowParseControl()
    let provider = SlowFrontend(control: control)
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store, provider: provider)
    let job = Task { try await indexer.reconcile() }
    while !control.entered.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
    try Data("func second() {}".utf8).write(to: path)
    do {
      _ = try await job.value
      Issue.record("Obsolete job unexpectedly published.")
    } catch let error as ArchitectureError {
      #expect(error.code == "INPUT_CHANGED_DURING_ANALYSIS")
    }
    #expect(try await store.latest() == nil)
    let next = try await indexer.reconcile()
    #expect(next.entities.contains { $0.name == "second" })
  }
  @Test(.timeLimit(.minutes(1))) func incrementalAndFreshIndexHaveTheSameRecordedMeaning()
    async throws
  {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Flow.swift")
    try Data("func first() {}".utf8).write(to: source)
    let paths = try WorkspacePaths(root.path)
    let a = try SQLiteGraphStore(
      path: root.appendingPathComponent("a.sqlite").path, workspaceID: paths.workspaceID)
    let b = try SQLiteGraphStore(
      path: root.appendingPathComponent("b.sqlite").path, workspaceID: paths.workspaceID)
    let incremental = WorkspaceIndexer(paths: paths, store: a)
    let fresh = WorkspaceIndexer(paths: paths, store: b)
    _ = try await incremental.reconcile()
    try Data("\nfunc first() { print(2) }\nfunc second() {}".utf8).write(to: source)
    let actual = try await incremental.reconcile()
    let reference = try await fresh.reconcile()
    #expect(actual.entities == reference.entities)
    #expect(actual.facts == reference.facts)
    #expect(actual.evidence == reference.evidence)
  }

  @Test(.timeLimit(.minutes(1))) func sourceParsingRunsConcurrentlyWithinWorkerBudget() async throws
  {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    for index in 0..<8 {
      try Data("func value\(index)() {}".utf8).write(
        to: root.appendingPathComponent("Flow\(index).swift"))
    }
    let control = ParallelParseControl()
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(
      paths: paths, store: store, provider: ParallelFrontend(control: control))
    _ = try await indexer.reconcile()
    let peak = control.state.withLock { $0.peak }
    #expect(peak >= 2)
    #expect(peak <= 4)
  }

  @Test(.timeLimit(.minutes(1))) func indexJobReturnsBeforeSlowParsingAndStatusStaysResponsive()
    async throws
  {
    let root = try temp()
    defer { try! FileManager.default.removeItem(at: root) }
    try Data("func value() {}".utf8).write(to: root.appendingPathComponent("Flow.swift"))
    let paths = try WorkspacePaths(root.path)
    let control = SlowParseControl()
    let store = try SQLiteGraphStore(
      path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let service = ArchitectureService(
      paths: paths, store: store, provider: SlowFrontend(control: control))
    let job = try await service.handle("workspace.index", params: .object([:]))
    let id = try #require(job["jobID"].string)
    #expect(job["state"].string == "running")
    while !control.entered.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(2)) }
    let status = try await service.handle("workspace.status", params: .object([:]))
    #expect(status["pending"].bool == true)
    #expect(status["snapshotID"] == .null)
    let shared = try await service.handle("workspace.index", params: .object([:]))
    #expect(shared["jobID"].string == id)
    var result: JSONValue
    repeat {
      try await Task.sleep(for: .milliseconds(5))
      result = try await service.handle(
        "workspace.index.result", params: .object(["jobID": .string(id)]))
    } while result["state"].string == "running"
    #expect(result["state"].string == "completed")
    #expect(result["result"]["entityCount"].int ?? 0 > 0)
    await service.shutdown()
  }

}

private final class SlowParseControl: Sendable {
  let entered = Mutex(false)
}
private struct SlowFrontend: FrontendProvider {
  let control: SlowParseControl
  var identity: String { SkeletonFrontend().identity }
  func capabilities() -> [Capability] { SkeletonFrontend().capabilities() }
  func analyze(_ input: SourceInput) throws -> FrontendResult {
    let first = control.entered.withLock { value in
      let first = !value
      value = true
      return first
    }
    if first { usleep(150000) }
    return try SkeletonFrontend().analyze(input)
  }
}

private final class ParallelParseControl: Sendable {
  struct State {
    var active = 0
    var peak = 0
  }
  let state = Mutex(State())
}
private struct ParallelFrontend: FrontendProvider {
  let control: ParallelParseControl
  var identity: String { SkeletonFrontend().identity }
  func capabilities() -> [Capability] { SkeletonFrontend().capabilities() }
  func analyze(_ input: SourceInput) throws -> FrontendResult {
    control.state.withLock {
      $0.active += 1
      $0.peak = max($0.peak, $0.active)
    }
    defer { control.state.withLock { $0.active -= 1 } }
    usleep(100000)
    return try SkeletonFrontend().analyze(input)
  }
}
