import ArchitectureCore
import ArchitectureIR
import Foundation

/// Projects source-declared SwiftPM targets without evaluating the manifest.
package enum SwiftPMManifest {
  package static let producer = "project.swiftpm.literal"

  package static func analyze(_ input: SourceInput, package: Entity, files: [Entity], contextDigest: String) throws -> FrontendResult {
    let root = try SyntaxParser().parse(input)
    func argument(_ name: String, in call: SyntaxNode) -> SyntaxNode? {
      let arguments = call.children.first { $0.kind == "call_suffix" }?.children.first { $0.kind == "value_arguments" }
      return arguments?.namedChildren.first { $0.namedChildren.first.map(input.text) == name }?.namedChildren.last
    }
    func literal(_ node: SyntaxNode) -> String? {
      input.text(node).wholeMatch(of: #/"([A-Za-z0-9_][A-Za-z0-9_.+-]*)"/#).map { String($0.1) }
    }
    func selector(_ call: SyntaxNode) -> String? {
      guard call.kind == "call_expression" else { return nil }
      return call.namedChildren.first.map(input.text)
    }
    let initializers = root.namedChildren.filter { $0.kind == "property_declaration" }
      .flatMap(\.namedChildren).filter { selector($0) == "Package" }
    let exclusions = ["computed target lists and dependencies", "custom source selection", "active build configuration"]
    guard initializers.count == 1, let initializer = initializers.first,
      let targets = argument("targets", in: initializer), targets.kind == "array_literal" else {
      return FrontendResult(entities: [], facts: [], evidence: [], coverage: Coverage(
        producer: producer, scope: input.path, language: "swift", completeness: "partial", exclusions: exclusions,
        diagnostics: [Diagnostic("PROJECT_CONTEXT_UNAVAILABLE", "SwiftPM targets are not a literal array in a top-level Package initializer.", scope: input.path)]))
    }
    let declarations = targets.namedChildren.compactMap { call -> (String, String, SyntaxNode)? in
      guard let factory = selector(call), [".target", ".executableTarget", ".testTarget"].contains(factory),
        let name = argument("name", in: call).flatMap(literal) else { return nil }
      return (name, factory, call)
    }
    let counts = Dictionary(grouping: declarations, by: { $0.0 })
    let directory = (input.path as NSString).deletingLastPathComponent
    var modules: [Entity] = [], facts: [Fact] = [], evidence: [Evidence] = []
    var ids: [String: String] = [:]
    var recorded = Set<String>()
    let prefix = directory.isEmpty ? "" : directory + "/"
    var defaultFiles: [String: [Entity]] = [:]
    for file in files where file.language == "swift" {
      guard let path = file.anchor?.path, path.hasPrefix(prefix) else { continue }
      let parts = path.dropFirst(prefix.count).split(separator: "/", maxSplits: 2)
      guard parts.count == 3 else { continue }
      defaultFiles[parts[0] + "/" + parts[1], default: []].append(file)
    }
    func record(_ kind: String, _ source: String, _ target: String, site: SyntaxNode) {
      let factID = CanonicalJSON.identity(producer + ":" + kind + ":" + source + ":" + target)
      guard recorded.insert(factID).inserted else { return }
      let sourceEvidence = CanonicalJSON.identity(factID + ":" + input.digest)
      evidence.append(Evidence(id: sourceEvidence, producer: producer, inputDigest: input.digest,
        contextDigest: contextDigest, basis: "syntax", anchor: input.anchor(site.start, site.end)))
      facts.append(Fact(id: factID, producer: producer, scope: input.path, kind: kind,
        source: source, target: target, revision: input.digest, evidenceIDs: [sourceEvidence],
        attributes: ["projection": .string("literal-manifest")]))
    }
    for (name, _, call) in declarations where counts[name]?.count == 1 {
      let identity = package.identityKey + ":module:" + name
      let id = CanonicalJSON.identity(identity)
      ids[name] = id
      modules.append(Entity(id: id, kind: "module", language: "swift", name: name,
        identityKey: identity, entityRevision: input.digest,
        attributes: ["project.manifest": .string(input.path), "project.context": .string("Literal SwiftPM declaration")]))
      record("contains", package.id, id, site: call)
    }
    for (name, factory, call) in declarations {
      guard let module = ids[name] else { continue }
      if ["path", "sources", "exclude"].allSatisfy({ argument($0, in: call) == nil }) {
        let root = factory == ".testTarget" ? "Tests" : "Sources"
        for file in defaultFiles[root + "/" + name, default: []] {
          record("contains", module, file.id, site: call)
        }
      }
      if let dependencies = argument("dependencies", in: call), dependencies.kind == "array_literal" {
        for item in dependencies.namedChildren {
          let isLocalFactory = [".target", ".byName"].contains(selector(item) ?? "")
          let localName = isLocalFactory && argument("condition", in: item) == nil
            ? argument("name", in: item).flatMap(literal) : literal(item)
          guard let localName, let dependency = ids[localName], dependency != module else { continue }
          record("dependsOn", module, dependency, site: item)
        }
      }
    }
    return FrontendResult(entities: modules, facts: facts, evidence: evidence, coverage: Coverage(
      producer: producer, scope: input.path, language: "swift", completeness: "partial", exclusions: exclusions))
  }
}
