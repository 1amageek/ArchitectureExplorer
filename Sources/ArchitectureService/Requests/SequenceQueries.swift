import ArchitectureCanvas
import ArchitectureCore
import ArchitectureIR
import Foundation

enum SequenceQueries {
  static func list(in snapshot: Snapshot, subjectID: String?) throws -> JSONValue {
    let subject = subjectID.flatMap { id in snapshot.entities.first { $0.id == id } }
    if subjectID != nil, subject == nil {
      throw ArchitectureError("SEQUENCE_SUBJECT_UNAVAILABLE", "The selected architecture element is absent from this snapshot.", exitCode: 3)
    }
    let sequences = snapshot.sequences?.filter { sequence in
      guard let subjectID else { return true }
      return sequence.subjectID == subjectID || sequence.participants.contains { $0.id == subjectID }
    } ?? []
    let path = WorkspacePaths.sequenceModelFilename
    let status = snapshot.inputs[path] == nil ? "missing" : snapshot.sequences == nil ? "invalid" : "available"
    var fields: [String: JSONValue] = [
      "snapshotID": .string(snapshot.id), "status": .string(status), "path": .string(path),
      "sequences": .array(sequences.map { sequence in
        .object(["key": .string(sequence.key), "title": .string(sequence.title),
          "requirements": .array(sequence.requirements.map(JSONValue.string)),
          "participants": .array(sequence.participants.map { .string($0.name) })])
      }),
      "diagnostics": try JSONValue.encode(snapshot.diagnostics.filter { $0.scope == path }),
    ]
    if let subject { fields["subject"] = .string(subject.name) }
    return .object(fields)
  }

  static func document(in snapshot: Snapshot, key: String) throws -> JSONValue {
    let path = WorkspacePaths.sequenceModelFilename
    guard let sequence = snapshot.sequences?.first(where: { $0.key == key }),
      let digest = snapshot.inputs[path] else {
      throw ArchitectureError("SEQUENCE_UNAVAILABLE", "This scenario is unavailable in the selected snapshot.", exitCode: 3)
    }
    let participants = Dictionary(uniqueKeysWithValues: sequence.participants.map { ($0.id, $0) })
    var nodes: [CanvasNode] = []
    var edges: [CanvasEdge] = []
    for (offset, message) in sequence.messages.enumerated() {
      let number = offset + 1
      let from = "step-\(number)-from", to = "step-\(number)-to"
      let order = Double(offset)
      guard let source = participants[message.source], let target = participants[message.target] else {
        throw ArchitectureError("SEQUENCE_INVALID", "A recorded scenario has an unresolved participant.", exitCode: 7)
      }
      nodes.append(.init(id: from, label: source.name, role: "interaction", laneID: source.id, order: order))
      nodes.append(.init(id: to, label: target.name, role: "interaction", laneID: target.id, order: order))
      let details: JSONValue = .object([
        "number": .number(Double(number)), "from": .string(source.name), "to": .string(target.name),
        "declaration": try JSONValue.encode(message.declaration),
        "relationship": try JSONValue.encode(message.relationship),
        "citations": try JSONValue.encode(message.citations),
      ])
      edges.append(.init(id: "step-\(number)", source: from, target: to, label: message.label,
        role: message.reply ? "reply" : "message", order: order, details: details))
    }
    let metadata: JSONValue = .object(["workspaceSequence": .object([
      "snapshotID": .string(snapshot.id), "workspaceID": .string(snapshot.workspaceID),
      "subjectID": sequence.subjectID.map(JSONValue.string) ?? .null,
      "key": .string(key), "path": .string(path), "digest": .string(digest),
      "requirements": .array(sequence.requirements.map(JSONValue.string)),
      "participants": try JSONValue.encode(sequence.participants),
      "declaration": try JSONValue.encode(sequence.declaration),
    ])])
    let document = CanvasDocument(kind: "sequence", title: sequence.title, format: "structurizr",
      sourceName: path, sourceDigest: digest, nodes: nodes, edges: edges,
      lanes: sequence.participants.map { .init(id: $0.id, label: $0.name) }, metadata: metadata)
    try document.validate()
    let encoded = try CanonicalJSON.encode(document)
    guard encoded.count <= 1024 * 1024 else {
      throw ArchitectureError("RESOURCE_LIMIT", "The recorded sequence exceeds the Canvas byte budget.", exitCode: 6)
    }
    return try JSONDecoder().decode(JSONValue.self, from: encoded)
  }
}
