import ArchitectureCore
import ArchitectureIR
import Foundation

/// Projects candidate imports from current files in the same captured workspace.
enum LocalSourceImports {
  static let producer = "project.localImports"

  static func facts(nodes: [String: Entity], inputs: [String: String], evidence: [String: Evidence]) throws -> [Fact] {
    let files = Dictionary(grouping: nodes.values.filter {
      $0.kind == "file" && $0.language == "typescript" && $0.anchor.map { inputs[$0.path] == $0.digest } == true
    }, by: \.name)
    let proofs = Dictionary(grouping: evidence.values.filter {
      $0.producer == "syntax.tree-sitter+skeleton" && $0.freshness == "current"
    }, by: { $0.anchor?.path ?? "" })
    var result: [Fact] = []
    for source in files.values.joined() {
      try Task.checkCancellation()
      guard let anchor = source.anchor,
        let proof = proofs[anchor.path]?.first(where: { $0.inputDigest == anchor.digest }) else { continue }
      for site in source.attributes["syntax.relativeImports"]?.array ?? [] {
        try Task.checkCancellation()
        guard let specifier = site["path"].string, let start = site["startByte"].int,
          let base = localPath(specifier, relativeTo: anchor.path) else { continue }
        let candidates = (base as NSString).pathExtension.isEmpty
          ? [base + ".ts", base + ".tsx", base + "/index.ts", base + "/index.tsx"]
          : [base]
        let matches = candidates.filter { inputs[$0] != nil }
        guard matches.count == 1, let path = matches.first,
          let indexed = files[path], indexed.count == 1, let target = indexed.first, target.id != source.id,
          let targetAnchor = target.anchor,
          let targetProof = proofs[targetAnchor.path]?.first(where: { $0.inputDigest == targetAnchor.digest }) else { continue }
        result.append(Fact(id: CanonicalJSON.identity(producer + ":" + source.id + ":" + String(start) + ":" + target.id),
          producer: producer, scope: anchor.path, kind: "candidateLocalImport", source: source.id,
          target: target.id, revision: anchor.digest, evidenceIDs: [proof.id, targetProof.id],
          attributes: ["reference.site": site]))
      }
    }
    return result
  }

  private static func localPath(_ specifier: String, relativeTo source: String) -> String? {
    var segments = Array(source.split(separator: "/").dropLast())
    for part in specifier.split(separator: "/") {
      switch part {
      case ".": continue
      case "..":
        guard !segments.isEmpty else { return nil }
        segments.removeLast()
      default: segments.append(part)
      }
    }
    return segments.isEmpty ? nil : segments.joined(separator: "/")
  }
}
