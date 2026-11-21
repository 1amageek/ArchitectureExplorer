import ArchitectureCore
import ArchitectureGraph
import ArchitectureIR
import Foundation
import Testing

struct FileOutlineTests {
  private func snapshot() -> Snapshot {
    let nodes = [
      ("module", "module", "Module", "none"), ("file", "file", "Sources/Z.swift", "none"),
      ("type", "actor", "ZActor", "swift"), ("a", "method", "a", "swift"),
      ("b", "field", "b", "swift"), ("top", "function", "top", "swift"),
      ("site", "callSite", "site", "swift"), ("block", "basicBlock", "entry", "swift"),
    ].map { id, kind, name, language in
      Entity(id: id, kind: kind, language: language, name: name, identityKey: id, entityRevision: "1")
    }
    let ownership = [("module", "file"), ("file", "type"), ("file", "top"),
                     ("type", "a"), ("type", "b"), ("a", "site"), ("a", "block")]
    var facts = ownership.map { owner, child in
      Fact(id: owner + "-" + child, producer: "fixture", scope: "fixture", kind: "contains",
           source: owner, target: child, revision: "1")
    }
    facts.append(Fact(id: "call", producer: "fixture", scope: "fixture", kind: "calls",
                      source: "a", target: "top", revision: "1"))
    return Snapshot(id: "outline", workspaceID: "outline", generation: 1, contextDigest: "context",
                    inputs: [:], entities: nodes, facts: facts, evidence: [], coverage: [])
  }

  @Test(.timeLimit(.minutes(1))) func fileModeIncludesRecordedNestedDeclarations() throws {
    let value = snapshot()
    let engine = GraphEngine()
    let direct = try engine.view(GraphQuery(method: "graph.children", focus: "module"), snapshot: value)
    #expect(direct.nodes.map(\.id) == ["file"])
    let outline = try engine.view(GraphQuery(method: "graph.children", focus: "module", depth: 3,
                                             level: "file"), snapshot: value)
    #expect(Set(outline.nodes.map(\.id)) == ["file", "type", "a", "b", "top"])
    #expect(outline.edges.contains { $0.id == "type-a" })
    #expect(outline.edges.contains { $0.id == "call" && $0.producer == "fixture" })
    let overview = try engine.view(GraphQuery(method: "graph.overview", depth: 2, level: "file"), snapshot: value)
    #expect(Set(overview.nodes.map(\.id)) == Set(outline.nodes.map(\.id)))
    let file = try engine.view(GraphQuery(method: "graph.children", focus: "file", depth: 8,
                                          level: "file"), snapshot: value)
    #expect(Set(file.nodes.map(\.id)) == Set(outline.nodes.map(\.id)))
    let shallow = try engine.view(GraphQuery(method: "graph.children", focus: "file", depth: 0,
                                             level: "file"), snapshot: value)
    #expect(shallow.nodes.map(\.id) == ["file"])
  }

  @Test(.timeLimit(.minutes(1))) func filteredPagesKeepAncestorsAndAdvancePayloadCursor() throws {
    let value = snapshot()
    var cursor: String?
    var seen = Set<String>()
    var pages = 0
    repeat {
      let page = try GraphEngine().view(GraphQuery(method: "graph.children", focus: "module",
        kinds: ["calls"], languages: ["swift"], depth: 3, limit: 3, cursor: cursor, level: "file"), snapshot: value)
      #expect(page.nodes.count <= 3)
      let ids = Set(page.nodes.map(\.id))
      for edge in value.facts where edge.kind == "contains" && ids.contains(edge.target) && edge.source != "module" {
        #expect(ids.contains(edge.source))
        #expect(page.edges.contains { $0.id == edge.id })
      }
      #expect(page.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
      seen.formUnion(ids)
      cursor = page.nextCursor
      pages += 1
      #expect(pages <= 5)
      if pages > 5 { break }
    } while cursor != nil
    #expect(seen == ["file", "type", "a", "b", "top"])
    #expect(pages > 1)
    let small = try GraphEngine().view(GraphQuery(method: "graph.children", focus: "module", depth: 3,
                                                  limit: 2, level: "file"), snapshot: value)
    #expect(small.nextCursor != nil)
    #expect(throws: ArchitectureError.self) {
      try GraphEngine().view(GraphQuery(method: "graph.children", focus: "module", depth: 3,
                                        limit: 2, cursor: small.nextCursor, level: "file"), snapshot: value)
    }
    #expect(throws: ArchitectureError.self) {
      try GraphEngine().view(GraphQuery(method: "graph.children", focus: "module", depth: 3,
                                        edgeLimit: 0, level: "file"), snapshot: value)
    }
  }
}
