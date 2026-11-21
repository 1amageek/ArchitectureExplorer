import ArchitectureCore
import ArchitectureIR
import Foundation

public struct SemanticGraphAdapter: Sendable {
  public init() {}
  public func facts(
    _ response: JSONValue, snapshot: Snapshot, subject: Entity, paths: WorkspacePaths
  ) throws -> FrontendResult {
    let operation = response["operation"].string ?? "definition"
    let producer = "semantic." + subject.language
    let scope = subject.id
    let evidenceID = CanonicalJSON.identity(
      producer + ":" + scope + ":" + operation + ":" + snapshot.id)
    let evidence = Evidence(
      id: evidenceID, producer: producer,
      version: response["providerInfo"]["version"].string ?? "unknown",
      inputDigest: response["inputDigest"].string ?? "unknown",
      contextDigest: snapshot.contextDigest, basis: "semantic", freshness: "unknown",
      anchor: subject.anchor)
    var entities: [String: Entity] = [:]
    var facts: [Fact] = []
    var diagnostics: [Diagnostic] = []
    let raw = response["data"]
    let items = raw.array.isEmpty && raw.object["uri"] != nil ? [raw] : raw.array
    func binding(_ location: JSONValue) throws -> Entity {
      let uri = location["uri"].string ?? location["targetUri"].string
      let range = location["range"] == .null ? location["targetRange"] : location["range"]
      guard let uri, let url = URL(string: uri), url.isFileURL else {
        throw ArchitectureError(
          "INVALID_GRAPH", "Provider returned an invalid source location.", exitCode: 7)
      }
      let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
      if normalized.path.hasPrefix(paths.root.path + "/"), let line = range["start"]["line"].int,
        let column = range["start"]["character"].int, let endLine = range["end"]["line"].int,
        let endColumn = range["end"]["character"].int
      {
        let relative = String(normalized.path.dropFirst(paths.root.path.count + 1))
        let data = try Data(contentsOf: paths.resolve(relative))
        guard CanonicalJSON.digest(data) == snapshot.inputs[relative] else {
          throw ArchitectureError(
            "INPUT_CHANGED_DURING_ANALYSIS", "Semantic target input changed.", exitCode: 7)
        }
        let start = try SourcePositions.byteOffset(data, line: line, utf16Column: column)
        let end = try SourcePositions.byteOffset(data, line: endLine, utf16Column: endColumn)
        let candidates = snapshot.entities.filter { entity in
          guard
            ["type", "actor", "interface", "function", "method", "field", "property"].contains(
              entity.kind), let anchor = entity.anchor
          else { return false }
          return anchor.path == relative && anchor.startByte <= start && anchor.endByte >= end
        }.sorted {
          ($0.anchor!.endByte - $0.anchor!.startByte) < ($1.anchor!.endByte - $1.anchor!.startByte)
        }
        if let first = candidates.first,
          candidates.count == 1
            || (candidates.count > 1
              && first.anchor!.endByte - first.anchor!.startByte < candidates[1].anchor!.endByte
                - candidates[1].anchor!.startByte)
        {
          return first
        }
        diagnostics.append(
          Diagnostic(
            "AMBIGUOUS_BINDING", "Provider location has no unique recorded declaration.",
            scope: relative, phase: "semantic"))
      }
      let name = location["name"].string ?? "provider-reported external or unmatched symbol"
      let key =
        paths.workspaceID + ":semantic-location:" + CanonicalJSON.digest(uri) + ":"
        + String(decoding: try CanonicalJSON.encode(range), as: UTF8.self)
      let entity = Entity(
        id: CanonicalJSON.identity(key),
        kind: normalized.path.hasPrefix(paths.root.path + "/")
          ? "unresolvedSymbol" : "externalSymbol", language: subject.language, name: name,
        identityKey: key, entityRevision: snapshot.contextDigest,
        attributes: [
          "semantic.binding": .string("provider location; no unique source declaration identity"),
          "semantic.location": range,
        ])
      entities[entity.id] = entity
      return entity
    }
    for item in items.prefix(500) {
      let location =
        operation == "outgoingCalls"
        ? item["to"] : (operation == "incomingCalls" ? item["from"] : item)
      let bound = try binding(location)
      let from = operation == "incomingCalls" ? bound.id : subject.id
      let to = operation == "incomingCalls" ? subject.id : bound.id
      let kind = operation.hasSuffix("Calls") ? "candidateCalls" : "references"
      let key = evidenceID + ":" + from + ":" + to
      if !facts.contains(where: { $0.id == CanonicalJSON.identity(key) }) {
        facts.append(
          Fact(
            id: CanonicalJSON.identity(key), producer: producer, scope: scope, kind: kind,
            source: from, target: to, revision: snapshot.id, evidenceIDs: [evidenceID],
            attributes: [
              "semantic.operation": .string(operation), "semantic.providerReported": .bool(true),
              "semantic.dispatch": .string("candidate; runtime dispatch is not established"),
            ]))
      }
    }
    return FrontendResult(
      entities: entities.values.sorted { $0.id < $1.id }, facts: facts, evidence: [evidence],
      coverage: Coverage(
        producer: producer, scope: scope, language: subject.language, freshness: "unknown",
        completeness: items.count > 500 ? "truncated" : "partial",
        exclusions: ["whole-project input consistency", "runtime dispatch", "complete call graph"],
        diagnostics: diagnostics))
  }
}
