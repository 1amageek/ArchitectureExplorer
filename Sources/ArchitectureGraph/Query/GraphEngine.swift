import ArchitectureCore
import ArchitectureIR
import Foundation

public struct GraphEngine: GraphQuerying {
  public init() {}
  public func view(_ query: GraphQuery, snapshot: Snapshot) throws -> GraphView {
    let search = query.method == "graph.search"
    guard ["outgoing", "incoming", "both"].contains(query.direction) else {
      throw ArchitectureError("INVALID_ARGUMENT", "Unknown graph direction.", exitCode: 2)
    }
    guard query.limit > 0, query.limit <= (search ? 200 : 500), query.edgeLimit >= 0,
      query.edgeLimit <= 1500, query.depth >= 0, query.depth <= 8
    else {
      throw ArchitectureError(
        "RESOURCE_LIMIT",
        "Maximum nodes 500 (search 200), edges 1500, depth 8; direction outgoing/incoming/both.",
        exitCode: 6)
    }
    let entities = Dictionary(uniqueKeysWithValues: snapshot.entities.map { ($0.id, $0) })
    let ordered = snapshot.entities.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    var selected = Set<String>()
    var implementationScope: String?
    var aggregation = false
    func focus() throws -> String {
      guard let focus = query.focus, entities[focus] != nil else {
        throw ArchitectureError(
          "ENTITY_NOT_FOUND", "A valid focus entity is required.", exitCode: 2)
      }
      return focus
    }
    let contextView = query.method == "graph.overview" && query.level == "context"
    let containerView = query.method == "graph.overview" && query.level == "container"
    let fileOutline = query.level == "file"
      && ["graph.children", "graph.overview"].contains(query.method)
    let containment = snapshot.facts.filter { $0.kind == "contains" }
    let outlineParents = Dictionary(grouping: containment, by: \.target)
    let mapProducers: Set<String> = ["c4.backstage", "c4.structurizr"]
    let contextSubject = query.focus ?? (contextView ? ordered.first { $0.attributes["context.mapSubject"]?.bool == true }?.id : nil)
    let eligible = snapshot.facts.filter {
      if containerView { return mapProducers.contains($0.producer) && $0.scope == query.focus }
      if contextView { return mapProducers.contains($0.producer) && $0.scope == "workspace" }
      if mapProducers.contains($0.producer) && $0.scope != "workspace" { return false }
      return (fileOutline && $0.kind == "contains") || query.kinds.isEmpty || query.kinds.contains($0.kind)
    }
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(200))
    var workTruncated = false
    func selectOutline(_ roots: [String], includeRoots: Bool) {
      let excluded: Set<String> = ["callSite", "basicBlock", "unresolvedSymbol", "externalSymbol"]
      let children = Dictionary(grouping: containment, by: \.source)
      var seen = Set(roots)
      if includeRoots { selected.formUnion(roots) }
      var frontier = roots.sorted()
      for _ in 0..<query.depth {
        var next: [String] = []
        for owner in frontier {
          for edge in children[owner, default: []].sorted(by: { $0.target < $1.target }) {
            guard let child = entities[edge.target], !excluded.contains(child.kind),
              seen.insert(child.id).inserted else { continue }
            selected.insert(child.id)
            next.append(child.id)
            if seen.count > 20000 || ContinuousClock.now >= deadline {
              workTruncated = true
              break
            }
          }
          if workTruncated { break }
        }
        frontier = next
        if frontier.isEmpty || workTruncated { break }
      }
    }
    switch query.method {
    case "graph.search":
      let text = query.text.lowercased()
      selected = Set(
        ordered.filter { entity in
          let matchesLanguage = query.languages.isEmpty || query.languages.contains(entity.language)
          return matchesLanguage
            && (entity.name.lowercased().contains(text)
              || (entity.anchor?.path.lowercased().contains(text) ?? false)
              || entity.kind.lowercased().contains(text))
        }.map(\.id))
    case "graph.node", "graph.explain", "graph.evidence": selected.insert(try focus())
    case "graph.children":
      let id = try focus()
      if fileOutline {
        let projectScope = ["workspace", "system", "package", "module", "designGroup"].contains(entities[id]?.kind ?? "")
        selectOutline([id], includeRoots: !projectScope)
      } else {
        selected = Set(
        eligible.compactMap { edge in
          if edge.kind == "contains", edge.source == id { return edge.target }
          if edge.kind == "memberOf", edge.target == id { return edge.source }
          return nil
        })
      }
    case "graph.overview":
      let kinds: Set<String>
      switch query.level {
      case "container": kinds = []
      case "context": kinds = ["softwareSystem", "person"]
      case "system": kinds = ["workspace", "system", "package"]
      case "module": kinds = ["workspace", "system", "package", "module"]
      case "component": kinds = ["type", "interface", "actor", "designGroup"]
      case "function": kinds = ["function", "method"]
      case "file": kinds = ["file"]
      default: throw ArchitectureError("INVALID_ARGUMENT", "Unknown overview level.", exitCode: 2)
      }
      let roots = ordered.filter { kinds.contains($0.kind) }.map(\.id)
      if fileOutline { selectOutline(roots, includeRoots: true) }
      else { selected = Set(roots) }
      if ["component", "function"].contains(query.level), query.focus != nil {
        let entryID = try focus()
        guard let entry = entities[entryID], let anchor = entry.anchor,
          snapshot.inputs[anchor.path] == anchor.digest else {
          throw ArchitectureError("SOURCE_UNAVAILABLE", "An indexed source declaration is required.", exitCode: 3)
        }
        let files = ordered.filter { $0.kind == "file" && $0.anchor?.path == anchor.path && $0.anchor?.digest == anchor.digest }
        guard files.count == 1, let file = files.first else {
          throw ArchitectureError("SOURCE_UNAVAILABLE", "The file for this declaration is unresolved.", exitCode: 3)
        }
        var paths: Set<String> = [anchor.path]
        let owners = Set(outlineParents[file.id, default: []].map(\.source).filter { entities[$0]?.kind == "module" })
        implementationScope = "Entry file · " + file.name
        if owners.count == 1, let owner = owners.first, let module = entities[owner] {
          for fact in containment where fact.source == owner {
            if let child = entities[fact.target], child.kind == "file", let path = child.anchor?.path { paths.insert(path) }
          }
          implementationScope = "Module · " + module.name
        }
        selected = query.level == "component" ? [entryID] : []
        for entity in ordered where kinds.contains(entity.kind) && entity.anchor.map({ paths.contains($0.path) }) == true {
          selected.insert(entity.id)
        }
        for fact in snapshot.facts where query.level == "component" && fact.kind == "memberOf" && entities[fact.target]?.kind == "designGroup" {
          if let path = entities[fact.source]?.anchor?.path, paths.contains(path) { selected.insert(fact.target) }
        }
      }
      if contextView, let subject = contextSubject {
        guard selected.contains(subject) else {
          throw ArchitectureError("ENTITY_NOT_FOUND", "Unknown Context subject.", exitCode: 2)
        }
        selected = [subject]
        for edge in eligible where edge.source == subject || edge.target == subject {
          selected.insert(edge.source)
          selected.insert(edge.target)
        }
      }
      if containerView {
        let owner = try focus()
        guard entities[owner]?.kind == "softwareSystem" else {
          throw ArchitectureError("INVALID_ARGUMENT", "Container overview requires a software system.", exitCode: 2)
        }
        selected = [owner]
        selected.formUnion(ordered.filter { $0.attributes["context.owner"]?.string == owner }.map(\.id))
        for edge in eligible { selected.insert(edge.source); selected.insert(edge.target) }
      }
      aggregation = !contextView && !containerView
    case "graph.path":
      let start = try focus()
      guard let target = query.target, entities[target] != nil else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Path requires a valid target entity.", exitCode: 2)
      }
      var adjacency: [String: [String]] = [:]
      for edge in eligible {
        if query.direction != "incoming" {
          adjacency[edge.source, default: []].append(edge.target)
        }
        if query.direction != "outgoing" {
          adjacency[edge.target, default: []].append(edge.source)
        }
      }
      var parents: [String: String] = [:]
      var frontier = [start]
      var visited: Set<String> = [start]
      var found = start == target
      for _ in 0..<query.depth where !found {
        var next: [String] = []
        for id in frontier {
          for neighbor in adjacency[id, default: []].sorted()
          where visited.insert(neighbor).inserted {
            parents[neighbor] = id
            next.append(neighbor)
            if neighbor == target {
              found = true
              break
            }
            if visited.count > 20000 || ContinuousClock.now >= deadline {
              workTruncated = true
              break
            }
          }
          if found || workTruncated { break }
        }
        frontier = next
        if found || workTruncated || frontier.isEmpty { break }
      }
      if found {
        var id = target
        selected.insert(id)
        while id != start {
          guard let parent = parents[id] else { break }
          selected.insert(parent)
          id = parent
        }
      }
    case "graph.neighbors", "graph.impact", "graph.cfg":
      let id = try focus()
      selected.insert(id)
      var frontier = [id]
      var adjacency: [String: [String]] = [:]
      let edges =
        query.method == "graph.cfg"
        ? eligible.filter { $0.producer == "cfg.tree-sitter" && $0.scope == id } : eligible
      for edge in edges {
        let reverse = query.method == "graph.impact" || query.direction == "incoming"
        if !reverse { adjacency[edge.source, default: []].append(edge.target) }
        if reverse || query.direction == "both" {
          adjacency[edge.target, default: []].append(edge.source)
        }
      }
      for _ in 0..<query.depth {
        var next: [String] = []
        for node in frontier {
          for neighbor in adjacency[node, default: []].sorted() {
            if selected.insert(neighbor).inserted { next.append(neighbor) }
            if selected.count > 20000 || ContinuousClock.now >= deadline {
              workTruncated = true
              break
            }
          }
          if workTruncated { break }
        }
        frontier = next
        if frontier.isEmpty || workTruncated { break }
      }
    default:
      throw ArchitectureError(
        "UNSUPPORTED_CAPABILITY", "Unknown graph query: \(query.method)", exitCode: 3)
    }
    let filtered = ordered.filter {
      selected.contains($0.id) && (query.languages.isEmpty || query.languages.contains($0.language))
    }
    let signature = try CanonicalJSON.encode([
      "method": JSONValue.string(query.method), "focus": query.focus.map(JSONValue.string) ?? .null,
      "text": .string(query.text), "kinds": .array(query.kinds.map(JSONValue.string)),
      "languages": .array(query.languages.map(JSONValue.string)),
      "direction": .string(query.direction), "depth": .number(Double(query.depth)),
      "limit": .number(Double(query.limit)), "edgeLimit": .number(Double(query.edgeLimit)),
      "level": .string(query.level),
    ])
    let queryID = CanonicalJSON.digest(signature)
    var offset = 0
    if let cursor = query.cursor {
      guard let data = Data(base64Encoded: cursor) else {
        throw ArchitectureError("INVALID_CURSOR", "Invalid cursor encoding.", exitCode: 2)
      }
      let value = try JSONDecoder().decode(JSONValue.self, from: data)
      guard value["snapshot"].string == snapshot.id, value["query"].string == queryID,
        let index = value["offset"].int, index >= 0, index <= filtered.count
      else {
        throw ArchitectureError(
          "SNAPSHOT_EXPIRED", "Cursor does not match the pinned snapshot/query.", exitCode: 7)
      }
      offset = index
    }
    var endOffset = offset
    var visible = Set<String>()
    if fileOutline {
      for candidate in filtered.dropFirst(offset) {
        var context: Set<String> = [candidate.id]
        var pending = [candidate.id]
        while let id = pending.popLast() {
          for edge in outlineParents[id, default: []] where selected.contains(edge.source) {
            if context.insert(edge.source).inserted { pending.append(edge.source) }
          }
        }
        guard visible.union(context).count <= query.limit else {
          if endOffset == offset {
            throw ArchitectureError("RESOURCE_LIMIT", "Node budget cannot fit a declaration and its ancestor context.", exitCode: 6)
          }
          break
        }
        visible.formUnion(context)
        endOffset += 1
      }
    } else if containerView, let subject = query.focus {
      // The area accompanies every page, including pages starting after its name.
      let payload = filtered.filter { $0.id != subject }
      guard query.limit > 1 || payload.isEmpty else {
        throw ArchitectureError("RESOURCE_LIMIT", "The node budget must fit the system and a container.", exitCode: 6)
      }
      guard offset <= payload.count else {
        throw ArchitectureError("INVALID_CURSOR", "Container cursor exceeds the projection.", exitCode: 2)
      }
      endOffset = min(payload.count, offset + query.limit - 1)
      visible = Set(payload[offset..<endOffset].map(\.id))
      visible.insert(subject)
    } else {
      endOffset = min(filtered.count, offset + query.limit)
      visible = Set(filtered[offset..<endOffset].map(\.id))
    }
    let nodes = ordered.filter { visible.contains($0.id) }
    var projected = eligible.filter { visible.contains($0.source) && visible.contains($0.target) }
    if contextView, let subject = contextSubject {
      projected.removeAll { $0.source != subject && $0.target != subject }
    }
    if aggregation {
      projected.removeAll { !["contains", "memberOf"].contains($0.kind) }
      let parentEdges = snapshot.facts.filter { $0.kind == "contains" }
      let parents = Dictionary(grouping: parentEdges, by: \.target)
      func ancestor(_ id: String) -> String? {
        var next = [id]
        var seen = Set<String>()
        while !next.isEmpty {
          let value = next.removeLast()
          guard seen.insert(value).inserted else { continue }
          if visible.contains(value) { return value }
          next.append(contentsOf: parents[value, default: []].map(\.source))
        }
        return nil
      }
      var groups: [String: [Fact]] = [:]
      var endpoints: [String: (String, String, String)] = [:]
      for edge in eligible where !["contains", "memberOf"].contains(edge.kind) {
        guard let from = ancestor(edge.source), let to = ancestor(edge.target), from != to else {
          continue
        }
        let key = from + ":" + edge.kind + ":" + to
        groups[key, default: []].append(edge)
        endpoints[key] = (from, to, edge.kind)
      }
      for key in groups.keys.sorted() {
        guard let members = groups[key], let (from, to, kind) = endpoints[key] else { continue }
        projected.append(
          Fact(
            id: CanonicalJSON.identity("aggregate:" + key), producer: "graph.aggregate",
            scope: query.level, kind: kind, source: from, target: to, revision: snapshot.id,
            evidenceIDs: Array(Set(members.flatMap(\.evidenceIDs))).sorted(),
            attributes: [
              "aggregate.count": .number(Double(members.count)),
              "aggregate.uniqueTargets": .number(Double(Set(members.map(\.target)).count)),
              "aggregate.sourceEdgeIDs": .array(
                members.map { .string($0.id) }.sorted { ($0.string ?? "") < ($1.string ?? "") }),
              "aggregate.scope": .string("all recorded facts in snapshot"),
            ]))
      }
    }
    if fileOutline || (query.method == "graph.overview" && query.level == "component"),
      query.kinds.isEmpty || query.kinds.contains("candidateTypeReference") {
      let references = TypeReferenceProjection.edges(snapshot: snapshot, visible: visible,
        nodes: nodes, entities: entities, parents: outlineParents, budget: query.edgeLimit,
        deadline: deadline)
      projected.append(contentsOf: references.facts)
      workTruncated = workTruncated || references.truncated
    }
    if fileOutline && projected.filter({ $0.kind == "contains" }).count > query.edgeLimit {
      throw ArchitectureError("RESOURCE_LIMIT", "Edge budget cannot fit the file outline's structural context.", exitCode: 6)
    }
    projected.sort {
      if fileOutline && ($0.kind == "contains") != ($1.kind == "contains") { return $0.kind == "contains" }
      return $0.id < $1.id
    }
    let edges = Array(projected.prefix(query.edgeLimit))
    let nodeTruncated = endOffset < filtered.count - (containerView ? 1 : 0)
    var cursor: String?
    if nodeTruncated {
      let value: JSONValue = .object([
        "snapshot": .string(snapshot.id), "query": .string(queryID),
        "offset": .number(Double(endOffset)),
      ])
      cursor = try CanonicalJSON.encode(value).base64EncodedString()
    }
    let evidenceIDs = Set(edges.flatMap(\.evidenceIDs))
    let relevantPaths = Set(nodes.compactMap { $0.anchor?.path })
    let evidence = snapshot.evidence.filter {
      evidenceIDs.contains($0.id) || ($0.anchor.map { relevantPaths.contains($0.path) } ?? false)
    }
    let coverage = snapshot.coverage.filter { item in
      if contextView || containerView { return mapProducers.contains(item.producer) }
      if query.method == "graph.cfg" {
        return item.producer == "cfg.tree-sitter" && item.scope == query.focus
      }
      return relevantPaths.isEmpty || relevantPaths.contains(item.scope)
        || item.scope == "workspace"
    }
    let freshness =
      coverage.contains { $0.freshness == "stale" }
      ? "stale" : (coverage.contains { $0.freshness == "unknown" } ? "unknown" : "current")
    let complete =
      coverage.allSatisfy { $0.completeness == "completeWithinScope" } && !coverage.isEmpty
    let truncated = nodeTruncated || projected.count > edges.count || workTruncated
    return GraphView(
      workspaceID: snapshot.workspaceID, snapshotID: snapshot.id, queryID: queryID,
      freshness: freshness,
      completeness: truncated ? "truncated" : (complete ? "completeWithinScope" : "partial"),
      nodes: nodes, edges: edges, evidence: evidence, coverage: coverage, truncated: truncated,
      nextCursor: cursor,
      diagnostics: ((contextView || containerView) ? snapshot.diagnostics.filter {
        $0.code.hasPrefix("C4_") || [WorkspacePaths.architectureModelFilename, "catalog-info.yaml", "catalog-info.yml", "catalog-info.json"].contains(($0.scope as NSString).lastPathComponent)
      } : snapshot.diagnostics)
        + (truncated
          ? [
            Diagnostic(
              "RESOURCE_LIMIT", "View was truncated to its declared query budget.", phase: "query")
          ] : []),
      extensions: (containerView || contextView) ? [containerView ? "c4.container" : "c4.context": .object([
        "subject": query.focus.map(JSONValue.string) ?? .null,
        "workspace": .string(entities[snapshot.workspaceID]?.name ?? ""),
        "scope": .string((snapshot.inputs[WorkspacePaths.architectureModelFilename] != nil || coverage.contains { $0.producer == "c4.structurizr" }) ? "Structurizr workspace" : "workspace catalog")
      ])] : (fileOutline ? ["file.outline": .bool(true)] : implementationScope.map { ["implementation.scope": .string($0)] }))
  }
  public func diff(_ from: Snapshot, _ to: Snapshot) throws -> JSONValue {
    guard from.workspaceID == to.workspaceID else {
      throw ArchitectureError("INVALID_GRAPH", "Cannot diff different workspaces.", exitCode: 7)
    }
    let old = Dictionary(uniqueKeysWithValues: from.entities.map { ($0.id, $0) })
    let new = Dictionary(uniqueKeysWithValues: to.entities.map { ($0.id, $0) })
    let oldEdges = Dictionary(uniqueKeysWithValues: from.facts.map { ($0.id, $0) })
    let newEdges = Dictionary(uniqueKeysWithValues: to.facts.map { ($0.id, $0) })
    let delta = GraphDelta(
      workspaceID: to.workspaceID, streamEpoch: "snapshot-diff", sequence: to.generation,
      queryID: "all-recorded-facts", baseSnapshotID: from.id, targetSnapshotID: to.id,
      upsertNodes: to.entities.filter { old[$0.id] != $0 },
      removeNodeIDs: old.keys.filter { new[$0] == nil }.sorted(),
      upsertEdges: to.facts.filter { oldEdges[$0.id] != $0 },
      removeEdgeIDs: oldEdges.keys.filter { newEdges[$0] == nil }.sorted(),
      coverageChanged: from.coverage != to.coverage)
    return try JSONValue.encode(delta)
  }
}
