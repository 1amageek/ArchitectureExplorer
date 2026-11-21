import ArchitectureCore
import ArchitectureIR
import Foundation

enum PropertyContext {
  private struct Link: Hashable, Codable {
    let source: String
    let target: String
    let kind: String
    let symbol: String
  }

  static func build(_ snapshot: Snapshot, files: [String: Data], entityID: String) throws -> JSONValue {
    guard snapshot.inputs["@designDocuments"] == "markdown-v1" else {
      throw ArchitectureError("SNAPSHOT_EXPIRED", "This snapshot predates design document capture. Open the current indexed snapshot.")
    }
    let entities = Dictionary(uniqueKeysWithValues: snapshot.entities.map { ($0.id, $0) })
    guard let focus = entities[entityID] else { throw ArchitectureError("UNKNOWN_ENTITY", "Node not present in the requested snapshot.") }
    func path(_ entity: Entity?) -> String? {
      guard let anchor = entity?.anchor, snapshot.inputs[anchor.path] == anchor.digest else { return nil }
      return anchor.path
    }
    let children = Dictionary(grouping: snapshot.facts.filter { $0.kind == "contains" }, by: \.source)
    var roots = Set<String>(), seen = Set<String>(), queue = [entityID]
    while let id = queue.popLast() {
      guard seen.insert(id).inserted, let node = entities[id] else { continue }
      if node.anchor != nil {
        guard let p = path(node) else { throw ArchitectureError("STALE_ANALYSIS", "Selected declaration differs from the captured source.") }
        roots.insert(p)
      } else { queue.append(contentsOf: (children[id] ?? []).map(\.target)) }
    }
    guard !roots.isEmpty else { throw ArchitectureError("SOURCE_UNAVAILABLE", "This node has no captured source or contained declarations.") }
    var names = [String: Set<String>]()
    for node in snapshot.entities where ["type","interface","actor","function"].contains(node.kind) {
      if let p = path(node) { names[node.name, default: []].insert(p) }
    }
    var links = Set<Link>()
    for fact in snapshot.facts where fact.kind != "contains" {
      if let from = path(entities[fact.source]), let to = path(entities[fact.target]), from != to {
        links.insert(Link(source: from, target: to, kind: fact.kind, symbol: entities[fact.target]?.name ?? fact.target))
      }
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(12))
    var sources = [String: String]()
    for (p, bytes) in files where p.hasSuffix(".swift") || p.hasSuffix(".rs") || SnapshotDesignDocument.matches(p) || roots.contains(p) {
      try Task.checkCancellation()
      guard let contents = String(data: bytes, encoding: .utf8) else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Invalid UTF-8: " + p) }
      sources[p] = contents
      if SnapshotDesignDocument.matches(p) { continue }
      // Identifier matches also recover possible consumers in files with parser diagnostics.
      // They may occur in comments or shadowed declarations and never assert semantic binding.
      for token in Set(contents.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })) {
        guard ContinuousClock.now < deadline, links.count < 50000 else {
          throw ArchitectureError("RESOURCE_LIMIT", "Property context exceeds the relationship scan budget.")
        }
        let name = String(token)
        for target in names[name] ?? [] where target != p && (target.hasSuffix(".rs") == p.hasSuffix(".rs")) {
          links.insert(Link(source: p, target: target, kind: "identifierCandidate", symbol: name))
        }
      }
    }
    let outgoing = Dictionary(grouping: links, by: \.source)
    func closure(_ start: Set<String>) -> Set<String> {
      var found = start, work = Array(start)
      while let next = work.popLast() {
        for edge in outgoing[next] ?? [] where found.insert(edge.target).inserted { work.append(edge.target) }
      }
      return found
    }
    let dependencies = closure(roots)
    let incoming = Set(links.lazy.filter { dependencies.contains($0.target) }.map(\.source)).subtracting(dependencies)
    let subjects = closure(dependencies.union(incoming))
    let documents = sources.keys.filter { p in
      guard SnapshotDesignDocument.matches(p) else { return false }
      var parts = p.split(separator: "/").dropLast()
      if let i = parts.firstIndex(where: { ["documentation","docs","adr","adrs"].contains($0.lowercased()) }) { parts = parts[..<i] }
      let scope = parts.joined(separator: "/")
      return scope.isEmpty || subjects.contains { $0.hasPrefix(scope + "/") }
    }
    let selected = subjects.union(documents)
    var size = 0, inventory = [JSONValue]()
    for p in selected.sorted() {
      guard let contents = sources[p], let digest = snapshot.inputs[p] else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Missing full text: " + p) }
      size += contents.utf8.count
      guard size <= 384 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Full property context exceeds 384 KiB. Select a narrower node.") }
      let parts = p.lowercased().split(separator: "/")
      let role = roots.contains(p) ? "selected" : SnapshotDesignDocument.matches(p) ? "design" :
        parts.contains(where: { $0 == "tests" || $0.hasSuffix("tests") }) ? "test" :
        incoming.contains(p) ? "possibleCaller" : "dependency"
      inventory.append(.object(["path": .string(p), "role": .string(role), "digest": .string(digest), "text": .string(contents)]))
    }
    let included = links.filter { selected.contains($0.source) && selected.contains($0.target) }
      .sorted { ($0.source,$0.target,$0.kind,$0.symbol) < ($1.source,$1.target,$1.kind,$1.symbol) }
    let result: JSONValue = .object(["workspaceID": .string(snapshot.workspaceID), "snapshotID": .string(snapshot.id),
      "entityID": .string(focus.id), "name": .string(focus.name), "files": .array(inventory),
      "relations": try .encode(included), "diagnostics": try .encode(snapshot.diagnostics.filter { selected.contains($0.scope) }),
      "coverage": .string("Workspace file dependencies and incoming references. Identifier candidates are lexical, not resolved calls. External libraries and dynamic dispatch are not closed.")])
    guard try CanonicalJSON.encode(result).count <= 512 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Complete source and relation payload exceeds 512 KiB.") }
    return result
  }
}
