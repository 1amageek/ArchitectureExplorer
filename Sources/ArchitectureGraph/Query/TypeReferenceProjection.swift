import ArchitectureCore
import ArchitectureIR
import Foundation

enum TypeReferenceProjection {
  private struct Name: Hashable {
    let language: String
    let scope: String
    let spelling: String
  }

  private static func scope(of type: Entity, path: String) -> String {
    if type.language == "swift" {
      let parts = path.split(separator: "/")
      if let index = parts.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }),
        index + 2 < parts.count {
        return parts[...(index + 1)].joined(separator: "/")
      }
    }
    return path
  }

  static func edges(snapshot: Snapshot, visible: Set<String>, nodes: [Entity],
    entities: [String: Entity], parents: [String: [Fact]], budget: Int,
    deadline: ContinuousClock.Instant) -> (facts: [Fact], truncated: Bool) {
    var declarations: [Name: [Entity]] = [:]
    for type in snapshot.entities where ["type", "actor", "interface"].contains(type.kind) {
      guard ContinuousClock.now < deadline else { return ([], true) }
      guard let path = type.anchor?.path,
        !["extension","implementation"].contains(type.attributes["declaration.kind"]?.string ?? "") else { continue }
      let key = Name(language: type.language, scope: scope(of: type, path: path), spelling: type.name)
      declarations[key, default: []].append(type)
    }
    var records: [String: Evidence] = [:]
    for item in snapshot.evidence where item.producer == "syntax.tree-sitter+skeleton" && item.freshness == "current" {
      if let path = item.anchor?.path { records[path] = item }
    }
    var facts: [Fact] = []
    for owner in nodes {
      guard let anchor = owner.anchor, let proof = records[anchor.path],
        proof.inputDigest == anchor.digest else { continue }
      let scope = scope(of: owner, path: anchor.path)
      for site in owner.attributes["syntax.typeSites"]?.array ?? [] {
        guard ContinuousClock.now < deadline else { return (facts, true) }
        guard let spelling = site["name"].string else { continue }
        let key = Name(language: owner.language, scope: scope, spelling: spelling)
        guard let matches = declarations[key], matches.count == 1, let target = matches.first,
          target.id != owner.id, visible.contains(target.id), let declaration = target.anchor,
          let targetProof = records[declaration.path], targetProof.inputDigest == declaration.digest,
          parents[target.id]?.contains(where: { entities[$0.source]?.kind == "file" }) == true else { continue }
        guard facts.count < budget else { return (facts, true) }
        facts.append(Fact(id: CanonicalJSON.identity("candidate-type:" + owner.id + ":" + target.id),
          producer: "graph.typeReferences", scope: anchor.path, kind: "candidateTypeReference",
          source: owner.id, target: target.id, revision: snapshot.id,
          evidenceIDs: Array(Set([proof.id, targetProof.id])).sorted(),
          attributes: ["reference.site": site, "reference.scope": .string(scope)]))
      }
    }
    return (facts, false)
  }
}
