import ArchitectureCore
import ArchitectureGraph
import ArchitectureIR
import ArchitectureIndexer
import ArchitectureStore
import Foundation
import Testing

struct SystemContextTests {
  @Test(.timeLimit(.minutes(1))) func catalogFactsResolveAcrossFilesAndStayPinned() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(directory.path)
    let store = try SQLiteGraphStore(path: directory.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    func view(_ snapshot: Snapshot) throws -> GraphView {
      try GraphEngine().view(GraphQuery(method: "graph.overview", level: "context"), snapshot: snapshot)
    }
    try Data("func example() {}".utf8).write(to: directory.appendingPathComponent("Source.swift"))
    let before = try await indexer.reconcile()
    #expect(try view(before).nodes.isEmpty)
    let a = """
      apiVersion: backstage.io/v1alpha1
      kind: System
      metadata: { name: payments }
      spec: { owner: billing }
      ---
      apiVersion: backstage.io/v1alpha1
      kind: Component
      metadata: { name: worker }
      spec:
        system: payments
        consumesApis: [balances]
        dependsOn: [component:gateway, component:unknown, component:worker]
      """
    let b = """
      apiVersion: backstage.io/v1alpha1
      kind: System
      metadata: { name: ledger }
      spec: { owner: finance }
      ---
      apiVersion: backstage.io/v1alpha1
      kind: Component
      metadata: { name: gateway }
      spec: { system: ledger, providesApis: [balances] }
      ---
      apiVersion: backstage.io/v1alpha1
      kind: API
      metadata: { name: balances }
      spec: { type: openapi }
      """
    let file = directory.appendingPathComponent("catalog-info.yaml")
    let sub = directory.appendingPathComponent("ledger")
    try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
    let other = sub.appendingPathComponent("catalog-info.yml")
    try Data(a.utf8).write(to: file)
    try Data(b.utf8).write(to: other)
    let snapshot = try await indexer.reconcile()
    let result = try view(snapshot)
    #expect(Set(result.nodes.map(\.name)) == ["payments", "ledger"])
    #expect(result.edges.count == 2)
    let edge = try #require(result.edges.first { $0.kind == "dependsOn" })
    let api = try #require(result.edges.first { $0.kind == "consumesApi" })
    #expect(api.source == edge.source && api.target == edge.target && api.evidenceIDs.count == 5)
    #expect(result.nodes.first { $0.id == edge.source }?.name == "payments")
    #expect(result.nodes.first { $0.id == edge.target }?.name == "ledger")
    #expect(Set(result.evidence.filter { edge.evidenceIDs.contains($0.id) }.compactMap { $0.anchor?.path }) == ["catalog-info.yaml", "ledger/catalog-info.yml"])
    #expect(result.diagnostics.contains { $0.code == "C4_UNRESOLVED" })
    try Data((b + "\n---\n" + b).utf8).write(to: other)
    let duplicate = try view(await indexer.reconcile())
    #expect(duplicate.edges.isEmpty && duplicate.diagnostics.contains { $0.code == "C4_AMBIGUOUS" })
    try Data("bad YAML: [".utf8).write(to: other)
    let invalid = try view(await indexer.reconcile())
    #expect(invalid.nodes.map(\.name) == ["payments"])
    #expect(invalid.edges.isEmpty && invalid.diagnostics.contains { $0.code == "C4_CATALOG_INVALID" })
    let historical = try view(await indexer.snapshot(snapshot.id))
    #expect(historical.edges == result.edges)
  }

  @Test(.timeLimit(.minutes(1))) func containerDrillDownKeepsRuntimeMembershipAndScopedEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/C4/catalog-info.yaml")
    try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("catalog-info.yaml"))
    let paths = try WorkspacePaths(directory.path)
    let store = try SQLiteGraphStore(path: directory.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let snapshot = try await WorkspaceIndexer(paths: paths, store: store).reconcile()
    let engine = GraphEngine()
    let context = try engine.view(GraphQuery(method: "graph.overview", level: "context"), snapshot: snapshot)
    let system = try #require(context.nodes.first { $0.name == "Booking" })
    #expect(context.nodes.count == 2 && context.edges.count == 1)
    #expect(system.attributes["context.areas"]?.array.map { $0["name"].string } == ["commerce", "reservations"])
    let detail = try engine.view(GraphQuery(method: "graph.overview", focus: system.id, level: "container"), snapshot: snapshot)
    #expect(detail.snapshotID == context.snapshotID)
    #expect(detail.nodes.filter { $0.kind == "dataStore" }.map(\.name) == ["Booking database"])
    let catalogTypes = Dictionary(uniqueKeysWithValues: detail.nodes.compactMap { node in
      node.attributes["context.catalogType"]?.string.map { (node.name, $0) }
    })
    #expect(catalogTypes == ["Booking database": "database", "Browser UI": "website", "Booking application": "service"])
    let firstPage = try engine.view(GraphQuery(method: "graph.overview", focus: system.id, limit: 2, level: "container"), snapshot: snapshot)
    let cursor = try #require(firstPage.nextCursor)
    let nextPage = try engine.view(GraphQuery(method: "graph.overview", focus: system.id, limit: 2, cursor: cursor, level: "container"), snapshot: snapshot)
    #expect(Set(firstPage.nodes.map(\.id)).intersection(nextPage.nodes.map(\.id)) == [system.id])
    let names = Dictionary(uniqueKeysWithValues: detail.nodes.map { ($0.id, $0.name) })
    #expect(Set(names.values) == ["Partner", "Browser UI", "Booking application", "Booking database", "Booking"])
    #expect(Set(detail.edges.map { "\(names[$0.source] ?? "") → \(names[$0.target] ?? "")" })
      == ["Partner → Booking application", "Browser UI → Booking application", "Booking application → Booking database"])
    #expect(detail.edges.allSatisfy { !$0.evidenceIDs.isEmpty && Set($0.evidenceIDs).isSubset(of: Set(detail.evidence.map(\.id))) })
  }
}

extension SystemContextTests {
  @Test(.timeLimit(.minutes(1))) func structurizrWorkspaceOpensDistinctSystemViews() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let file = root.appendingPathComponent("ARCHITECTURE.dsl")
    let model = """
      workspace {
        !impliedRelationships false
        model {
          group "Writing" {
            author = person "Author"
            editor = softwareSystem "Editor" {
              desktop = container "Desktop"
            }
          }
          group "Publishing" {
            publisher = person "Publisher"
            service = softwareSystem "Publication" {
              delivery = container "Delivery"
            }
          }
          author -> editor "Writes documents"
          author -> desktop "Edits text"
          publisher -> service "Publishes documents"
          publisher -> delivery "Delivers files"
        }
        views {
          systemContext editor EditorContext {
            include *
          }
          container editor EditorContainers {
            include *
          }
          systemContext service ServiceContext {
            include *
          }
          container service ServiceContainers {
            include *
          }
        }
      }
      """
    try Data(model.utf8).write(to: file)
    let snapshot = try await indexer.reconcile()
    let engine = GraphEngine()
    let overview = GraphQuery(method: "graph.overview", level: "context")
    let map = try engine.view(overview, snapshot: snapshot)
    #expect(Set(map.nodes.map(\.name)) == ["Author", "Editor", "Publisher", "Publication"])
    #expect(map.edges.count == 2)
    for (system, person, child) in [("Editor", "Author", "Desktop"), ("Publication", "Publisher", "Delivery")] {
      let subject = try #require(map.nodes.first { $0.name == system })
      let c1 = try engine.view(.init(method: "graph.overview", snapshotID: snapshot.id, focus: subject.id, level: "context"), snapshot: snapshot)
      let c2 = try engine.view(.init(method: "graph.overview", snapshotID: snapshot.id, focus: subject.id, level: "container"), snapshot: snapshot)
      #expect(Set(c1.nodes.map(\.name)) == [system, person])
      #expect(Set(c2.nodes.map(\.name)) == [system, person, child])
      #expect(c1.edges.count == 1 && c2.edges.count == 1)
      #expect(c1.evidence.contains { $0.anchor?.path == "ARCHITECTURE.dsl" })
      #expect(c2.evidence.contains { $0.anchor?.path == "ARCHITECTURE.dsl" })
      #expect(c1.snapshotID == snapshot.id && c2.snapshotID == snapshot.id)
    }
    let duplicate = model.replacingOccurrences(of: "ServiceContext", with: "EditorContext")
    try Data(duplicate.utf8).write(to: file)
    let invalid = try engine.view(overview, snapshot: await indexer.reconcile())
    #expect(invalid.diagnostics.contains { $0.code == "C4_DSL_INVALID" && $0.message.contains("Duplicate view key") })
    let incomplete = model.replacingOccurrences(of: "container service ServiceContainers", with: "container editor ServiceContainers")
    try Data(incomplete.utf8).write(to: file)
    let conflicting = try engine.view(overview, snapshot: await indexer.reconcile())
    #expect(conflicting.diagnostics.contains { $0.code == "C4_DSL_INVALID" && $0.message.contains("Duplicate container view") })
    #expect(try engine.view(overview, snapshot: await indexer.snapshot(snapshot.id)).nodes == map.nodes)
  }

  @Test(.timeLimit(.minutes(1))) func structurizrViewsShareIdentityAndInvalidEditsInvalidateHead() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: dir) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(dir.path)
    let store = try SQLiteGraphStore(path: dir.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let file = dir.appendingPathComponent("ARCHITECTURE.dsl")
    let code = "struct Runner { func run() {} }"
    let body = Data(code.utf8)
    let runner = dir.appendingPathComponent("Runner.swift")
    try body.write(to: runner)
    try Data("struct Other {}".utf8).write(to: dir.appendingPathComponent("Other.swift"))
    let model = """
    workspace "Example" {
        !impliedRelationships false
        model {
            group "Operations" {
                actor = person "Operator"
            }
            group "Platform" {
                service = softwareSystem "Service" {
                    group "App" {
                        client = container "Client"
                    }
                    group "Backend" {
                        // Entry: type 0..<\(body.count) sha256=\(CanonicalJSON.digest(body)) Runner.swift
                        // Source: Sources/Job.swift:12 sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
                        // Source: config.json sha256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
                        job = container "Job" "Processes work" "Swift" "worker"
                    }
                }
                other = softwareSystem "Unconnected"
            }
            actor -> service "Operates"
            actor -> client "Operates"
            client -> job "Starts"
        }
        views {
            systemContext service Context {
                include *
            }
            container service Containers {
                include *
            }
        }
    }
    """
    try Data(model.replacingOccurrences(of: "\n", with: "\r\n").utf8).write(to: file)
    let snapshot = try await indexer.reconcile()
    let engine = GraphEngine()
    let query = GraphQuery(method: "graph.overview", level: "context")
    let c1 = try engine.view(query, snapshot: snapshot)
    #expect(Set(c1.nodes.map(\.name)) == ["Operator", "Service"])
    let subject = try #require(c1.nodes.first { $0.name == "Service" })
    let actor = try #require(c1.nodes.first { $0.name == "Operator" })
    #expect(actor.attributes["context.areas"]?.array.first?["name"].string == "Operations")
    #expect(subject.attributes["context.areas"]?.array.first?["name"].string == "Platform")
    #expect(c1.edges.count == 1 && c1.edges.first?.target == subject.id)
    let c2 = try engine.view(GraphQuery(method: "graph.overview", focus: subject.id, level: "container"), snapshot: snapshot)
    let client = try #require(c2.nodes.first { $0.name == "Client" })
    let job = try #require(c2.nodes.first { $0.name == "Job" })
    #expect(job.attributes["context.citedSources"]?.array.first?["path"].string == "Sources/Job.swift")
    #expect(job.attributes["context.citedSources"]?.array.first?["line"] == .number(12))
    #expect(subject.attributes["context.citedSources"] == nil)
    #expect(Set(c2.edges.map { [$0.source, $0.target] }) == [[actor.id, client.id], [client.id, job.id]])
    #expect(client.attributes["context.owner"]?.string == subject.id)
    #expect(job.attributes["context.owner"]?.string == subject.id)
    let app = try #require(client.attributes["context.containerGroup"])
    let backend = try #require(job.attributes["context.containerGroup"])
    #expect(app["name"].string == "App" && backend["name"].string == "Backend")
    #expect(app["id"].string != backend["id"].string)
    #expect(c1.nodes.allSatisfy { $0.attributes["context.containerGroup"] == nil })
    #expect(c2.evidence.contains { $0.anchor?.path == "ARCHITECTURE.dsl" })
    #expect(c2.nodes.first { $0.name == "Job" }?.attributes["context.areas"] == subject.attributes["context.areas"])
    let entry = try #require(job.attributes["context.entryID"]?.string)
    let components = GraphQuery(method: "graph.overview", snapshotID: snapshot.id, focus: entry, level: "component")
    let sourceView = try engine.view(components, snapshot: snapshot)
    #expect(sourceView.nodes.map(\.name) == ["Runner"])
    #expect(sourceView.extensions?["implementation.scope"]?.string == "Entry file · Runner.swift")
    #expect(sourceView.extensions?["c4.container"] == nil)
    let codeView = try engine.view(GraphQuery(method: "graph.children", focus: entry, level: "file"), snapshot: snapshot)
    #expect(codeView.nodes.contains { $0.kind == "method" && $0.name == "run" })
    try Data((code + "\n").utf8).write(to: runner)
    let changed = try await indexer.reconcile()
    #expect(changed.entities.first { $0.id == job.id }?.attributes["context.entryID"] == nil)
    #expect(try engine.view(components, snapshot: await indexer.snapshot(snapshot.id)).nodes == sourceView.nodes)
    let unwrapped = model.replacingOccurrences(
      of: "group \"Operations\" {\n            actor = person \"Operator\"\n        }",
      with: "actor = person \"Operator\"")
    #expect(unwrapped != model)
    try Data(unwrapped.utf8).write(to: file)
    let ungrouped = try engine.view(query, snapshot: await indexer.reconcile())
    #expect(ungrouped.nodes.isEmpty && ungrouped.diagnostics.contains { $0.message.contains("domain group") })
    let duplicate = model.replacingOccurrences(of: "group \"Backend\"", with: "group \"App\"")
    try Data(duplicate.utf8).write(to: file)
    let ambiguous = try engine.view(query, snapshot: await indexer.reconcile())
    #expect(ambiguous.nodes.isEmpty && ambiguous.diagnostics.contains { $0.message.contains("container group") })
    try Data(model.replacingOccurrences(of: "include *", with: "!include remote.dsl").utf8).write(to: file)
    let failed = try engine.view(query, snapshot: await indexer.reconcile())
    #expect(failed.nodes.isEmpty && failed.diagnostics.contains { $0.code == "C4_DSL_INVALID" })
    #expect(try engine.view(query, snapshot: await indexer.snapshot(snapshot.id)).edges == c1.edges)
  }
}

extension SystemContextTests {
  @Test(.timeLimit(.minutes(1))) func packageIncludesPreserveOriginalDeclarationsAcrossSnapshots() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let pkg = root.appendingPathComponent("My Package")
    try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    func write(_ path: String, _ contents: String) throws {
      try Data(contents.utf8).write(to: root.appendingPathComponent(path), options: .atomic)
    }
    let model = """
    workspace "Example" {
        !impliedRelationships false
        model {
            group "Platform" {
                system = softwareSystem "System" {
                    !include "My Package/containers.dsl"
                }
                external = softwareSystem "External"
            }
            !include "My Package/relationships.dsl"
        }
    }
    """
    try write("workspace.dsl", model)
    let legacyOnly = try await indexer.reconcile()
    #expect(legacyOnly.inputs["workspace.dsl"] == nil)
    #expect(!legacyOnly.entities.contains { $0.name == "System" })
    try write("ARCHITECTURE.dsl", model)
    try write("My Package/containers.dsl", "!include entries.dsl")
    let statement = "worker = container \"Worker\" \"One\" \"Swift\""
    try write("My Package/entries.dsl", "// préface\r\n" + statement)
    try write("My Package/relationships.dsl", "worker -> external \"Writes\"")
    let old = try await indexer.reconcile()
    let worker = try #require(old.entities.first { $0.name == "Worker" })
    #expect(worker.anchor?.path == "My Package/entries.dsl")
    #expect(worker.anchor?.startByte == "// préface\r\n".utf8.count)
    #expect(worker.attributes["context.declaration"]?["line"] == .number(2))
    let relation = try #require(old.facts.first { $0.source == worker.id && $0.kind == "dependsOn" })
    #expect(relation.attributes["context.declarations"]?.array.first?["path"] == .string("My Package/relationships.dsl"))
    try write("unused.dsl", "!include unused.dsl")
    #expect(try await indexer.reconcile().id == old.id)
    try write("My Package/entries.dsl", statement.replacingOccurrences(of: "One", with: "Two"))
    let new = try await indexer.reconcile()
    #expect(new.id != old.id && new.inputs["ARCHITECTURE.dsl"] == old.inputs["ARCHITECTURE.dsl"])
    #expect(new.entities.first { $0.id == worker.id }?.attributes["context.purpose"] == .string("Two"))
    #expect(try await indexer.snapshot(old.id).entities.first { $0.id == worker.id }?.attributes["context.declaration"]?["text"] == .string(statement))
    for bad in ["!include containers.dsl", "!include absent.dsl", "!include ../../outside.dsl", "!include https://remote.invalid/a.dsl"] {
      try write("My Package/entries.dsl", bad)
      let invalid = try await indexer.reconcile()
      #expect(invalid.diagnostics.contains { $0.code == "C4_DSL_INVALID" })
      #expect(!invalid.entities.contains { $0.id == worker.id })
    }
  }
}
