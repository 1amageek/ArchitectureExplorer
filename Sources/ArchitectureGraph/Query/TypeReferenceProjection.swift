import ArchitectureCore
import ArchitectureIR
import Foundation

struct TypeReferenceProjection {
  private struct Scope: Hashable {
    let language: String
    let lexicalPath: String
    let module: String?

    static func module(_ id: String) -> Scope {
      Scope(language: "swift", lexicalPath: "", module: id)
    }
  }

  private struct ModuleOwner {
    let id: String
    let evidenceIDs: [String]
  }

  private let snapshotID: String
  private let records: [String: Evidence]
  private let owners: [String: ModuleOwner]
  private let imports: [String: Set<String>]
  private let dependencies: [String: [Fact]]
  private let modules: [String: Entity]
  private let declarations: [Scope: [String: [Entity]]]
  private let sourceSites: [String: [Entity]]

  private static func scope(of type: Entity, path: String, owners: [String: ModuleOwner]) -> Scope {
    if type.language == "swift" {
      if let owner = owners[path] { return .module(owner.id) }
      let parts = path.split(separator: "/")
      if let index = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }),
        index + 2 < parts.count {
        return Scope(language: "swift", lexicalPath: parts[...(index + 1)].joined(separator: "/"), module: nil)
      }
    }
    return Scope(language: type.language, lexicalPath: path, module: nil)
  }

  init?(snapshot: Snapshot, entities: [String: Entity], indexIncoming: Bool = false, deadline: ContinuousClock.Instant) {
    let syntax = "syntax.tree-sitter+skeleton"
    let topology: Set<String> = ["project.swiftpm.literal", "project.metadata"]
    var evidence: [String: Evidence] = [:], records: [String: Evidence] = [:]
    for item in snapshot.evidence {
      guard ContinuousClock.now < deadline else { return nil }
      if item.producer == syntax, item.freshness == "current", let path = item.anchor?.path,
        snapshot.inputs[path] == item.inputDigest { records[path] = item }
      if topology.contains(item.producer), item.freshness != "stale" { evidence[item.id] = item }
    }
    var fileOwners: [String: [Fact]] = [:], imports: [String: Set<String>] = [:]
    var dependencies: [String: [Fact]] = [:]
    for fact in snapshot.facts {
      guard ContinuousClock.now < deadline else { return nil }
      if topology.contains(fact.producer),
        let manifest = snapshot.inputs[fact.scope],
        fact.evidenceIDs.contains(where: { evidence[$0]?.inputDigest == manifest }),
        let source = entities[fact.source], source.kind == "module", source.language == "swift",
        let target = entities[fact.target] {
        if fact.kind == "contains", target.kind == "file", let path = target.anchor?.path {
          fileOwners[path, default: []].append(fact)
        }
        if fact.kind == "dependsOn", target.kind == "module", target.language == "swift" {
          dependencies[source.id, default: []].append(fact)
        }
      }
      if fact.kind == "imports", fact.producer == syntax,
        let file = entities[fact.source], file.language == "swift", let path = file.anchor?.path,
        let proof = records[path], fact.evidenceIDs.contains(proof.id),
        let name = entities[fact.target]?.name,
        let module = name.wholeMatch(of: #/(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)/#) {
        imports[path, default: []].insert(String(module.1))
      }
    }
    var owners: [String: ModuleOwner] = [:]
    for (path, facts) in fileOwners {
      guard let first = facts.first, facts.allSatisfy({ $0.source == first.source }) else { continue }
      owners[path] = ModuleOwner(id: first.source, evidenceIDs: facts.flatMap(\.evidenceIDs))
    }
    var declarations: [Scope: [String: [Entity]]] = [:]
    for type in snapshot.entities where ["type", "actor", "interface"].contains(type.kind) {
      guard ContinuousClock.now < deadline else { return nil }
      guard let path = type.anchor?.path,
        !["extension", "implementation"].contains(type.attributes["declaration.kind"]?.string ?? "") else { continue }
      let scope = Self.scope(of: type, path: path, owners: owners)
      declarations[scope, default: [:]][type.name, default: []].append(type)
    }
    var sourceSites: [String: [Entity]] = [:]
    if indexIncoming {
      for entity in snapshot.entities {
        guard ContinuousClock.now < deadline else { return nil }
        guard let anchor = entity.anchor, records[anchor.path]?.inputDigest == anchor.digest else { continue }
        for site in entity.attributes["syntax.typeSites"]?.array ?? [] {
          guard ContinuousClock.now < deadline else { return nil }
          if let spelling = site["name"].string { sourceSites[spelling, default: []].append(entity) }
        }
      }
    }
    guard ContinuousClock.now < deadline else { return nil }
    self.snapshotID = snapshot.id
    self.records = records
    self.owners = owners
    self.imports = imports
    self.dependencies = dependencies
    self.modules = entities
    self.declarations = declarations
    self.sourceSites = sourceSites
  }

  func incoming(to target: Entity, entities: [String: Entity], parents: [String: [Fact]],
    budget: Int, deadline: ContinuousClock.Instant) -> (facts: [Fact], truncated: Bool) {
    guard ["type", "actor", "interface"].contains(target.kind) else { return ([], false) }
    return edges(visible: [target.id], nodes: sourceSites[target.name, default: []], entities: entities,
      parents: parents, budget: budget, deadline: deadline, matching: target.name)
  }

  func edges(visible: Set<String>?, nodes: [Entity], entities: [String: Entity],
    parents: [String: [Fact]], budget: Int, deadline: ContinuousClock.Instant,
    matching: String? = nil) -> (facts: [Fact], truncated: Bool) {
    var facts: [Fact] = []
    for owner in nodes {
      guard ContinuousClock.now < deadline else { return (facts, true) }
      guard let anchor = owner.anchor, let proof = records[anchor.path],
        proof.inputDigest == anchor.digest else { continue }
      let scope = Self.scope(of: owner, path: anchor.path, owners: owners)
      var scopes = [scope]
      var imported: [Scope: Fact] = [:]
      if let module = scope.module, let importedNames = imports[anchor.path] {
        for edge in dependencies[module, default: []] {
          guard ContinuousClock.now < deadline else { return (facts, true) }
          guard let target = modules[edge.target], importedNames.contains(target.name) else { continue }
          let scope = Scope.module(target.id)
          if imported[scope] == nil { scopes.append(scope) }
          imported[scope] = edge
        }
      }
      for site in owner.attributes["syntax.typeSites"]?.array ?? [] {
        guard ContinuousClock.now < deadline else { return (facts, true) }
        guard let spelling = site["name"].string, matching == nil || matching == spelling else { continue }
        var match: (Scope, Entity)?
        for candidate in scopes {
          guard ContinuousClock.now < deadline else { return (facts, true) }
          guard let matches = declarations[candidate]?[spelling], let first = matches.first else { continue }
          if matches.count > 1 || match != nil {
            match = nil
            break
          }
          match = (candidate, first)
        }
        guard let (targetScope, target) = match, target.id != owner.id, visible?.contains(target.id) != false,
          let declaration = target.anchor, let targetProof = records[declaration.path],
          targetProof.inputDigest == declaration.digest,
          parents[target.id]?.contains(where: { entities[$0.source]?.kind == "file" }) == true else { continue }
        guard facts.count < budget else { return (facts, true) }
        var evidenceIDs = [proof.id, targetProof.id]
        if let dependency = imported[targetScope] {
          evidenceIDs += dependency.evidenceIDs
          evidenceIDs += owners[anchor.path]?.evidenceIDs ?? []
          evidenceIDs += owners[declaration.path]?.evidenceIDs ?? []
        }
        let scopeLabel = targetScope.module.flatMap { modules[$0]?.name } ?? targetScope.lexicalPath
        facts.append(Fact(id: CanonicalJSON.identity("candidate-type:" + owner.id + ":" + target.id),
          producer: "graph.typeReferences", scope: anchor.path, kind: "candidateTypeReference",
          source: owner.id, target: target.id, revision: snapshotID,
          evidenceIDs: Array(Set(evidenceIDs)).sorted(),
          attributes: ["reference.site": site, "reference.scope": .string(scopeLabel)]))
      }
    }
    return (facts, false)
  }
}
