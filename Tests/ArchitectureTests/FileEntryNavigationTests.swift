import ArchitectureCore
import ArchitectureGraph
import ArchitectureIR
import ArchitectureIndexer
import ArchitectureStore
import Foundation
import Testing

struct FileEntryNavigationTests {
  @Test(.timeLimit(.minutes(1))) func anchoredEntryOpensItsComponentsAndCurrentDirectImports() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(directory.path)
    let store = try SQLiteGraphStore(path: directory.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let indexer = WorkspaceIndexer(paths: paths, store: store)
    let engine = GraphEngine()
    func write(_ name: String, _ contents: String) throws {
      try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
    let statement = "import { save } from './storage';"
    let source = """
      // café
      \(statement)
      import './internal';
      import './missing';
      import 'external';
      export default { fetch() { return save(); } };
      """
    try write("entry.ts", source)
    try write("storage.ts", "import './internal';\nexport function save() { return 1; }")
    try write("internal.ts", "export function details() {}")
    try write("unrelated.ts", "export class Unrelated {}")
    let data = Data(source.utf8)
    let digest = CanonicalJSON.digest(data)
    try write("ARCHITECTURE.dsl", """
      workspace "Example" {
        !impliedRelationships false
        model {
          group "Operations" {
            system = softwareSystem "System" {
              // Entry: file 0..<\(data.count) sha256=\(digest) entry.ts
              server = container "Public endpoint" "Accepts requests" "TypeScript"
              // Source: entry.ts:2 sha256=\(digest)
              external = container "External endpoint" "Documentation only" "TypeScript"
            }
          }
        }
        views {
          systemContext system Context {
            include *
          }
          container system Containers {
            include *
          }
        }
      }
      """)
    let disabled = try await indexer.reconcile()
    #expect(disabled.entities.first { $0.name == "Public endpoint" }?.attributes["context.entryID"] == nil)

    try write("architecture.json", #"{"schemaVersion":"1.0","languages":["typescript"]}"#)
    let snapshot = try await indexer.reconcile()
    let context = try engine.view(GraphQuery(method: "graph.overview", level: "context"), snapshot: snapshot)
    let system = try #require(context.nodes.first)
    let containers = try engine.view(GraphQuery(method: "graph.overview", focus: system.id, level: "container"), snapshot: snapshot)
    let server = try #require(containers.nodes.first { $0.name == "Public endpoint" })
    #expect(containers.nodes.first { $0.name == "External endpoint" }?.attributes["context.entryID"] == nil)
    let entry = try #require(server.attributes["context.entryID"]?.string)
    let components = GraphQuery(method: "graph.overview", snapshotID: snapshot.id, focus: entry, level: "component")
    let view = try engine.view(components, snapshot: snapshot)
    #expect(view.snapshotID == snapshot.id)
    #expect(view.extensions?["implementation.scope"]?.string == "Entry file · entry.ts")
    #expect(Set(view.nodes.map(\.name)) == ["entry.ts", "storage.ts", "internal.ts", "fetch"])
    let dependency = try #require(view.edges.first { $0.kind == "candidateLocalImport" && $0.attributes["reference.site"]?["path"].string == "./storage" })
    #expect(view.edges.filter { $0.kind == "candidateLocalImport" }.count == 2)
    #expect(view.edges.filter { $0.kind == "candidateLocalImport" }.allSatisfy { $0.source == entry })
    let site = try #require(dependency.attributes["reference.site"])
    let start = try #require(site["startByte"].int)
    let stop = try #require(site["endByte"].int)
    #expect(String(decoding: data[start..<stop], as: UTF8.self) == statement)
    #expect(site["line"].int == 2)
    #expect(Set(dependency.evidenceIDs).isSubset(of: Set(view.evidence.map(\.id))))
    let neighbors = try engine.view(GraphQuery(method: "graph.neighbors", snapshotID: snapshot.id, focus: entry, depth: 1), snapshot: snapshot)
    let impact = try engine.view(GraphQuery(method: "graph.impact", snapshotID: snapshot.id, focus: dependency.target, depth: 1), snapshot: snapshot)
    #expect(neighbors.edges.contains(dependency))
    #expect(impact.edges.contains(dependency))
    let code = try engine.view(GraphQuery(method: "graph.children", snapshotID: snapshot.id, focus: dependency.target,
      depth: 2, level: "file"), snapshot: snapshot)
    #expect(Set(code.nodes.map(\.name)) == ["storage.ts", "save"])

    try write("storage.tsx", "function invalid(")
    let ambiguous = try await indexer.reconcile()
    #expect(ambiguous.entities.first { $0.id == server.id }?.attributes["context.entryID"]?.string == entry)
    #expect(!ambiguous.facts.contains { $0.id == dependency.id })
    try FileManager.default.removeItem(at: directory.appendingPathComponent("storage.tsx"))
    try write("storage.ts", "function invalid(")
    let invalidTarget = try await indexer.reconcile()
    #expect(!invalidTarget.facts.contains { $0.id == dependency.id })
    #expect(invalidTarget.coverage.contains { $0.scope == "storage.ts" && $0.language == "typescript" && $0.completeness == "failed" })
    try write("entry.ts", source + "\n")
    let stale = try await indexer.reconcile()
    #expect(stale.entities.first { $0.id == server.id }?.attributes["context.entryID"] == nil)
    #expect(try engine.view(components, snapshot: await indexer.snapshot(snapshot.id)).edges.contains(dependency))
  }
}
