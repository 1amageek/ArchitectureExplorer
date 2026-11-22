import ArchitectureCanvas
import ArchitectureCore
import ArchitectureIR
import ArchitectureStore
@testable import ArchitectureService
import Foundation
import Testing

struct WorkspaceSequenceTests {
  @Test(.timeLimit(.minutes(1))) func capturedScenariosKeepOrderEvidenceAndHistoricalDeclarations() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    func write(_ filename: String, _ source: String) throws {
      try Data(source.utf8).write(to: root.appendingPathComponent(filename), options: .atomic)
    }
    try write("ARCHITECTURE.dsl", """
      workspace "Orders" {
        !impliedRelationships false
        model {
          group "Users" {
            person = person "Customer"
          }
          group "Orders" {
            orders = softwareSystem "Orders" {
              group "Order entry" {
                ui = container "Order app" "Collects orders"
              }
              group "Order persistence" {
                db = container "Ledger" "Stores orders" "SQLite" "database"
              }
            }
          }
          person -> orders "Places orders"
          person -> ui "Places orders"
          ui -> db "Commits orders" "SQL"
        }
        views {
          systemContext orders "Context" {
            include *
          }
          container orders "Containers" {
            include *
          }
        }
      }
      """)
    let evidence = "assert(commitCount === 1);"
    let digest = CanonicalJSON.digest(Data(evidence.utf8))
    try write("orders.test.mjs", evidence)
    let valid = """
      workspace extends "ARCHITECTURE.dsl" {
        views {
          dynamic orders "SaveOrder" {
            title "Save order"
            properties {
              "invar.requirements" "ORD01"
            }
            person -> ui "Taps Save"
            2: ui -> db "Write order" "SQL"
            // Source: orders.test.mjs:1 sha256=\(digest)
            3: db -> ui "Return committed revision"
          }
          dynamic orders "MissingEvidence" {
            // Source: missing.txt:1 sha256=\(digest)
            person -> ui "Starts order"
          }
        }
      }
      """
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("index.db").path, workspaceID: paths.workspaceID)
    let service = ArchitectureService(paths: paths, store: store)
    defer { await service.shutdown() }
    await service.refresh()
    #expect(try await service.handle("workspace.sequences", params: .object([:]))["status"].string == "missing")
    try write("SEQUENCES.dsl", valid.replacingOccurrences(of: "\n", with: "\r\n"))
    await service.refresh()
    let catalogue = try await service.handle("workspace.sequences", params: .object([:]))
    let pinned = catalogue["snapshotID"]
    #expect(catalogue["status"].string == "available")
    #expect(catalogue["sequences"].array.compactMap { $0["key"].string } == ["SaveOrder", "MissingEvidence"])
    let context = try await service.handle("graph.overview", params: .object(["level": .string("context"), "snapshotID": pinned]))
    let system = try #require(context["nodes"].array.first { $0["name"].string == "Orders" })
    let graph = try await service.handle("graph.overview",
      params: .object(["level": .string("container"), "snapshotID": pinned, "focus": system["id"]]))
    let ledger = try #require(graph["nodes"].array.first { $0["name"].string == "Ledger" })
    let subset = try await service.handle("workspace.sequences", params: .object(["snapshotID": pinned, "subjectID": ledger["id"]]))
    #expect(subset["sequences"].array.compactMap { $0["key"].string } == ["SaveOrder"])
    let parameters = JSONValue.object(["snapshotID": pinned, "key": .string("SaveOrder")])
    let document = try await service.handle("workspace.sequence", params: parameters)
    let canvas = try document.decode(CanvasDocument.self)
    try canvas.validate()
    #expect(canvas.lanes.map(\.label) == ["Customer", "Order app", "Ledger"])
    #expect(canvas.edges.map(\.role) == ["message", "message", "reply"])
    #expect(canvas.edges.map(\.order) == [0, 1, 2])
    #expect(canvas.edges.last?.details["relationship"]["path"].string == "ARCHITECTURE.dsl")
    #expect(canvas.edges.last?.details["declaration"]["path"].string == "SEQUENCES.dsl")
    #expect(canvas.edges.last?.details["citations"].array.first?["excerpt"].string == evidence)
    #expect(canvas.metadata["workspaceSequence"]["snapshotID"] == pinned)

    let id = try #require(pinned.string)
    let snapshot = try await store.load(id)
    let original = try #require(snapshot.sequences?.first)
    let duplicated = ArchitectureSequence(key: original.key, title: original.title,
      subjectID: original.subjectID, participants: original.participants + [original.participants[0]],
      requirements: original.requirements, declaration: original.declaration, messages: original.messages)
    var imported = try JSONValue.encode(snapshot).object
    imported["sequences"] = try JSONValue.encode([duplicated])
    await #expect(throws: ArchitectureError.self) {
      try await service.handle("workspace.import", params: .object(["snapshot": .object(imported)]))
    }

    try write("orders.test.mjs", "assert(commitCount === 2);")
    await service.refresh()
    let fresh = try await service.handle("workspace.sequences", params: .object([:]))
    #expect(fresh["snapshotID"] != pinned)
    let stale = try await service.handle("workspace.sequence", params: .object(["snapshotID": fresh["snapshotID"], "key": .string("SaveOrder")]))
    #expect(stale["edges"].array.last?["details"]["citations"].array.first?["status"].string == "stale")
    #expect(stale["edges"].array.last?["details"]["citations"].array.first?["excerpt"] == JSONValue.null)
    let missing = try await service.handle("workspace.sequence", params: .object(["snapshotID": fresh["snapshotID"], "key": .string("MissingEvidence")]))
    #expect(missing["edges"].array.first?["details"]["citations"].array.first?["status"].string == "unavailable")
    #expect(try await service.handle("workspace.sequence", params: parameters) == document)

    for bad in [valid.replacingOccurrences(of: "2: ui -> db", with: "2: ui -> unknown"),
      valid.replacingOccurrences(of: "2: ui -> db", with: "4: ui -> db"),
      valid.replacingOccurrences(of: "db -> ui", with: "db -> person"),
      valid.replacingOccurrences(of: "ARCHITECTURE.dsl", with: "https://invalid.example/base.dsl"),
      valid.replacingOccurrences(of: "Source: orders.test.mjs", with: "Source: ../orders.test.mjs")] {
      try write("SEQUENCES.dsl", bad)
      await service.refresh()
      let invalid = try await service.handle("workspace.sequences", params: .object([:]))
      #expect(invalid["status"].string == "invalid" && invalid["sequences"].array.isEmpty)
      let map = try await service.handle("graph.overview", params: .object(["level": .string("context")]))
      #expect(map["nodes"].array.contains { $0["name"].string == "Orders" })
    }
    #expect(try await service.handle("workspace.sequence", params: parameters) == document)
  }
}
