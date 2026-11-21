import ArchitectureCore
import Foundation

public enum GraphValidation {
  public static func validate(_ snapshot: Snapshot) throws {
    guard snapshot.schemaVersion == "1.0" else {
      throw ArchitectureError("SCHEMA_MISMATCH", "Expected ArchitectureIR 1.0.", exitCode: 2)
    }
    guard Set(snapshot.entities.map(\.id)).count == snapshot.entities.count,
      Set(snapshot.facts.map(\.id)).count == snapshot.facts.count,
      Set(snapshot.evidence.map(\.id)).count == snapshot.evidence.count
    else { throw ArchitectureError("INVALID_GRAPH", "Duplicate identities.", exitCode: 7) }
    let ids = Set(snapshot.entities.map(\.id))
    let evidence = Set(snapshot.evidence.map(\.id))
    var parents: [String: [String]] = [:]
    for edge in snapshot.facts {
      guard ids.contains(edge.source), ids.contains(edge.target),
        Set(edge.evidenceIDs).isSubset(of: evidence)
      else {
        throw ArchitectureError(
          "INVALID_GRAPH", "Dangling edge or evidence: \(edge.id)", exitCode: 7)
      }
      if edge.kind == "contains" { parents[edge.target, default: []].append(edge.source) }
    }
    var done = Set<String>()
    var active = Set<String>()
    func visit(_ id: String) throws {
      if done.contains(id) { return }
      guard active.insert(id).inserted else {
        throw ArchitectureError("INVALID_GRAPH", "Containment cycle.", exitCode: 7)
      }
      for parent in parents[id, default: []] { try visit(parent) }
      active.remove(id)
      done.insert(id)
    }
    for entity in snapshot.entities {
      guard !entity.id.isEmpty, !entity.identityKey.isEmpty else {
        throw ArchitectureError("INVALID_GRAPH", "Missing identity key.", exitCode: 7)
      }
      if let anchor = entity.anchor {
        guard anchor.startByte >= 0, anchor.endByte >= anchor.startByte,
          !anchor.path.hasPrefix("/"), !anchor.path.split(separator: "/").contains("..")
        else { throw ArchitectureError("INVALID_GRAPH", "Invalid source anchor.", exitCode: 7) }
      }
      try visit(entity.id)
    }
  }
}
