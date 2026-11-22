import ArchitectureCore
import ArchitectureFrontend
import ArchitectureIR
import Foundation

/// Reads the non-executable C1/C2 workspace profile of the Map contract.
struct StructurizrContext {
  static let producer = "c4.structurizr"
  var nodes: [Entity] = []
  var facts: [Fact] = []
  var evidence: [Evidence] = []

  private struct Element {
    let kind: String, name: String, description: String, technology: String, tags: String
    let owner: String?
    let domain: String
    let containerGroup: String?
    let entry: EntryLink?
    let sources: [JSONValue]
    let declaration: JSONValue
    let anchor: SourceAnchor
  }

  private struct EntryLink: Hashable {
    let path: String, digest: String, kind: String
    let start: Int, end: Int
  }

  private(set) var sequenceRelationships: [StructurizrSequence.Relationship] = []
  private(set) var viewKeys: Set<String> = []

  private struct Relation {
    let source: String, target: String, label: String, technology: String
    let declaration: JSONValue
    let anchor: SourceAnchor
  }

  private enum Block: Equatable {
    case workspace, model, domain(String), system(String), containerGroup(owner: String, name: String), views, view
  }

  static func tokens(_ line: Substring) throws -> [String] {
    var result: [String] = []
    var rest = line[...]
    while !rest.isEmpty {
      if rest.first!.isWhitespace { rest.removeFirst(); continue }
      if rest.hasPrefix("//") || rest.first == "#" { break }
      if rest.first == "\"" {
        rest.removeFirst()
        let value = rest.prefix { $0 != "\"" }
        guard value.count < rest.count, !value.contains("\\") else {
          throw ArchitectureError("C4_DSL_INVALID", "Unsupported or unclosed quoted value.")
        }
        result.append(String(value))
        rest = rest.dropFirst(value.count + 1)
      } else {
        let word = rest.prefix { !$0.isWhitespace }
        result.append(String(word))
        rest = rest.dropFirst(word.count)
      }
    }
    return result
  }

  init(workspaceID: String, input: SourceInput, catalogs: [SourceInput], contextDigest: String, indexed: [String: Entity], inputs: [String: String], failedSources: Set<String>) throws {
    guard input.bytes.count <= 512 * 1024, String(data: input.bytes, encoding: .utf8) != nil else {
      throw ArchitectureError("C4_DSL_INVALID", "\(input.path) must be UTF-8 within 512 KiB.")
    }
    var stack: [Block] = [], elements: [String: Element] = [:], relations: [Relation] = []
    var workspaceSeen = false, modelSeen = false, viewsSeen = false, explicitRelations = false
    var domains = Set<String>()
    var containerGroups: [String: Set<String>] = [:]
    var viewSubject: String?, viewKinds = Set<String>(), viewKeys = Set<String>(), includesAll = false
    func validID(_ s: String) -> Bool {
      s.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
    var pendingEntry: EntryLink?
    var pendingSources: [JSONValue] = []
    let files = Dictionary(uniqueKeysWithValues: catalogs.filter { $0.path.hasSuffix(".dsl") }.map { ($0.path, $0) })
    let modelRevision = CanonicalJSON.digest(try CanonicalJSON.encode(files.mapValues(\.digest)))
    try StructurizrIncludes.walk(input) { path, _ in
      guard let file = files[path] else { throw ArchitectureError("C4_DSL_INVALID", "Missing captured input: " + path) }
      return file
    } visit: { file, index, start, line in
      let anchor = file.anchor(start, start + line.utf8.count)
      func invalid(_ reason: String) -> ArchitectureError {
        ArchitectureError("C4_DSL_INVALID", "\(file.path):\(index + 1): \(reason)")
      }
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("// Entry:") {
        guard pendingEntry == nil,
          let match = trimmed.wholeMatch(of: #/\/\/ Entry: ([a-zA-Z]+) ([0-9]+)\.\.<([0-9]+) sha256=([a-f0-9]{64}) (.+)/#),
          let lower = Int(match.2), let upper = Int(match.3), lower < upper else {
          throw invalid("Invalid or duplicate typed entry link.")
        }
        pendingEntry = EntryLink(path: String(match.5), digest: String(match.4), kind: String(match.1), start: lower, end: upper)
        return
      }
      if let match = trimmed.wholeMatch(of: /\/\/ Source: (.+):([0-9]+) sha256=([a-f0-9]{64})/),
        let number = Int(match.2), number > 0 {
        pendingSources.append(.object(["path": .string(String(match.1)), "line": .number(Double(number)),
          "digest": .string(String(match.3))]))
        return
      }
      if let match = trimmed.wholeMatch(of: #/\/\/ Source: (.+) sha256=([a-f0-9]{64})/#) {
        pendingSources.append(.object(["path": .string(String(match.1)), "digest": .string(String(match.2))]))
        return
      }
      let entry = pendingEntry
      pendingEntry = nil
      let sources = pendingSources
      pendingSources.removeAll()
      let words: [String]
      do { words = try Self.tokens(line) } catch { throw invalid("Invalid quoted value.") }
      guard let first = words.first else { return }
      guard elements.count + relations.count <= 4096 else { throw invalid("Model size limit exceeded.") }
      if words == ["}"] {
        guard let last = stack.popLast() else { throw invalid("Unexpected closing brace.") }
        if last == .view && !includesAll { throw invalid("Map views require include *.") }
        return
      }
      let declaration: JSONValue = .object(["path": .string(file.path), "line": .number(Double(index + 1)), "text": .string(String(line))])
      let opens = words.last == "{"
      let w = opens ? Array(words.dropLast()) : words
      switch stack.last {
      case nil where first == "workspace" && opens && !workspaceSeen && (1...3).contains(w.count) && w.dropFirst().first != "extends":
        workspaceSeen = true; stack.append(.workspace)
      case .workspace where w == ["model"] && opens && !modelSeen:
        modelSeen = true; stack.append(.model)
      case .workspace where w == ["views"] && opens && modelSeen && !viewsSeen:
        viewsSeen = true; stack.append(.views)
      case .workspace where words == ["!impliedRelationships", "false"] && !modelSeen:
        explicitRelations = true
      case .views where opens && ["systemContext", "container"].contains(first) && (2...3).contains(w.count):
        guard elements[w[1]]?.kind == "softwareSystem", viewSubject == nil || viewSubject == w[1],
          viewKinds.insert(first).inserted, w.count < 3 || viewKeys.insert(w[2]).inserted else {
          throw invalid("Expected unique views of one declared software system.")
        }
        viewSubject = w[1]; includesAll = false; stack.append(.view)
      case .view where words == ["include", "*"] && !includesAll:
        includesAll = true
      case .model where !opens && (4...5).contains(w.count) && w[1] == "->":
        guard elements[first] != nil, elements[w[2]] != nil, first != w[2], !w[3].trimmingCharacters(in: .whitespaces).isEmpty else {
          throw invalid("Relationship needs two declared endpoints and a description.")
        }
        relations.append(Relation(source: first, target: w[2], label: w[3],
          technology: w.count == 5 ? w[4] : "", declaration: declaration, anchor: anchor))
      case .model where opens && first == "group" && w.count == 2:
        let name = w[1]
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, domains.insert(name).inserted else {
          throw invalid("A domain group needs a unique, nonblank name.")
        }
        stack.append(.domain(name))
      case .model:
        throw invalid("Declare each system or person inside a named domain group.")
      case .system(let owner) where opens && first == "group" && w.count == 2:
        let name = w[1]
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
          containerGroups[owner, default: []].insert(name).inserted else {
          throw invalid("A container group needs a unique, nonblank name within its software system.")
        }
        stack.append(.containerGroup(owner: owner, name: name))
      case .domain, .system, .containerGroup:
        guard (4...7).contains(w.count), w[1] == "=", validID(first), elements[first] == nil,
          !w[3].trimmingCharacters(in: .whitespaces).isEmpty else { throw invalid("Invalid or duplicate element declaration.") }
        let kind = w[2]
        let owner: String?
        let domain: String
        let containerGroup: String?
        switch stack.last {
        case .system(let id):
          guard let parent = elements[id] else { throw invalid("Unknown container owner.") }
          owner = id; domain = parent.domain; containerGroup = nil
        case .containerGroup(let id, let name):
          guard let parent = elements[id] else { throw invalid("Unknown container owner.") }
          owner = id; domain = parent.domain; containerGroup = name
        case .domain(let name):
          owner = nil; domain = name; containerGroup = nil
        default: throw invalid("Missing domain group.")
        }
        guard (owner == nil ? ["person", "softwareSystem"].contains(kind) : kind == "container"),
          !opens || kind == "softwareSystem", kind == "container" || w.count <= 6 else {
          throw invalid("Unsupported element or nesting.")
        }
        let tagIndex = kind == "container" ? 6 : 5
        elements[first] = Element(kind: kind, name: w[3], description: w.count > 4 ? w[4] : "",
          technology: kind == "container" && w.count > 5 ? w[5] : "",
          tags: w.count > tagIndex ? w[tagIndex] : "", owner: owner, domain: domain,
          containerGroup: containerGroup, entry: kind == "container" ? entry : nil, sources: sources,
          declaration: declaration, anchor: anchor)
        if opens { stack.append(.system(first)) }
      default: throw invalid("Unsupported Structurizr statement in this scope.")
      }
    }
    guard explicitRelations else { throw ArchitectureError("C4_DSL_INVALID", "Map requires !impliedRelationships false before model.") }
    guard stack.isEmpty, modelSeen, !elements.isEmpty,
      !viewsSeen || viewKinds == ["systemContext", "container"] else {
      throw ArchitectureError("C4_DSL_INVALID", "Incomplete model or missing C1/C2 wildcard view.")
    }
    func identity(_ alias: String) -> String { CanonicalJSON.identity(workspaceID + ":structurizr:" + alias) }
    let counts = Dictionary(grouping: elements.values.compactMap(\.owner), by: { $0 }).mapValues(\.count)
    func support(_ anchor: SourceAnchor) -> Evidence {
      Evidence(id: identity("evidence:\(anchor.path):\(anchor.digest):\(anchor.startByte)"), producer: Self.producer,
        inputDigest: anchor.digest, contextDigest: contextDigest, basis: "designDeclared", anchor: anchor)
    }
    let requested = Set(elements.values.compactMap(\.entry))
    var bindings: [EntryLink: [String]] = [:]
    if !requested.isEmpty {
      for entity in indexed.values {
        guard let a = entity.anchor, inputs[a.path] == a.digest, !failedSources.contains(a.path),
          ["file", "type", "interface", "actor", "function", "method"].contains(entity.kind) else { continue }
        let key = EntryLink(path: a.path, digest: a.digest, kind: entity.kind, start: a.startByte, end: a.endByte)
        if requested.contains(key) { bindings[key, default: []].append(entity.id) }
      }
    }
    for (alias, el) in elements {
      let tags = Set(el.tags.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
      let subtype = ["database", "cache", "queue", "object-storage", "website", "mobile-app", "worker", "api-gateway", "service"].first(where: tags.contains) ?? ""
      let store = ["database", "cache", "queue", "object-storage"].contains(subtype)
      var attrs: [String: JSONValue] = ["context.ref": .string(alias), "context.purpose": .string(el.description),
        "context.technology": .string(el.technology), "context.catalogType": .string(subtype)]
      attrs["context.declaration"] = el.declaration
      attrs["context.areas"] = .array([.object(["id": .string(identity("domain:" + el.domain)), "name": .string(el.domain)])])
      if let entry = el.entry, let ids = bindings[entry], ids.count == 1 { attrs["context.entryID"] = .string(ids[0]) }
      if !el.sources.isEmpty { attrs["context.citedSources"] = .array(el.sources) }
      if let owner = el.owner {
        attrs["context.owner"] = .string(identity(owner))
        if let group = el.containerGroup {
          attrs["context.containerGroup"] = .object([
            "id": .string(identity("container-group:\(owner):\(group)")), "name": .string(group)
          ])
        }
      }
      if alias == viewSubject { attrs["context.mapSubject"] = .bool(true) }
      if el.kind == "softwareSystem" { attrs["context.containerCount"] = .number(Double(counts[alias, default: 0])) }
      nodes.append(Entity(id: identity(alias), kind: el.kind == "container" ? (store ? "dataStore" : "application") : el.kind,
        language: "none", name: el.name, identityKey: alias, entityRevision: modelRevision, anchor: el.anchor, attributes: attrs))
      evidence.append(support(el.anchor))
    }
    struct Link: Hashable { let scope: String, from: String, to: String, label: String, technology: String }
    var links: [Link: Set<String>] = [:]
    var declarations: [String: JSONValue] = [:]
    self.viewKeys = viewKeys
    for r in relations {
      sequenceRelationships.append(.init(source: r.source, target: r.target, label: r.label,
        technology: r.technology, declaration: .init(path: r.anchor.path,
          line: r.declaration["line"].int ?? 1, text: r.declaration["text"].string ?? "")))
      let fromOwner = elements[r.source]!.owner, toOwner = elements[r.target]!.owner
      let from = fromOwner ?? r.source, to = toOwner ?? r.target
      let e = support(r.anchor)
      evidence.append(e)
      declarations[e.id] = r.declaration
      if from != to && fromOwner == nil && toOwner == nil {
        links[Link(scope: "workspace", from: from, to: to, label: r.label, technology: r.technology), default: []].insert(e.id)
      }
      for owner in Set([fromOwner, toOwner].compactMap { $0 }) {
        let a = fromOwner == owner ? r.source : from, b = toOwner == owner ? r.target : to
        guard a != b else { continue }
        links[Link(scope: identity(owner), from: a, to: b, label: r.label, technology: r.technology), default: []].insert(e.id)
      }
    }
    for (key, ids) in links {
      let parts = try CanonicalJSON.encode([key.scope,key.from,key.to,key.label,key.technology])
      facts.append(Fact(id: identity("relation:" + CanonicalJSON.digest(parts)), producer: Self.producer,
        scope: key.scope, kind: "dependsOn", source: identity(key.from), target: identity(key.to),
        revision: modelRevision, evidenceIDs: ids.sorted(),
        attributes: ["context.declarations": .array(ids.sorted().compactMap { declarations[$0] }), "context.operation": .string(key.label), "context.technology": .string(key.technology)]))
    }
  }
}
