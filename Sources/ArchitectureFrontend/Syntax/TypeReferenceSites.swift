import ArchitectureCore
import ArchitectureIR
import Foundation

/// Representative lexical sites, keyed by the enclosing type and the spelling at the use site.
struct TypeReferenceSites {
  private var byOwner: [Int: [String: JSONValue]] = [:]
  private let lineStarts: [Int]

  init(bytes: Data) {
    var starts = [0]
    for offset in bytes.indices where bytes[offset] == 10 { starts.append(offset + 1) }
    lineStarts = starts
  }

  mutating func record(_ node: SyntaxNode, parent: String, owner: Int, input: SourceInput) {
    let identifier: SyntaxNode
    let end: Int
    switch node.kind {
    case "user_type":
      guard let first = node.namedChildren.first, first.kind == "type_identifier",
        !node.children.contains(where: { $0.kind == "." }) else { return }
      identifier = first
      end = first.end
    case "type_identifier" where input.language == "rust":
      guard node.field != "name", parent != "scoped_type_identifier", parent != "type_parameter" else { return }
      identifier = node
      end = node.end
    case "call_expression":
      guard let callee = node.child("function") ?? node.namedChildren.first,
        ["simple_identifier", "identifier"].contains(callee.kind) else { return }
      identifier = callee
      end = callee.end
    case "navigation_expression", "scoped_identifier":
      guard let receiver = node.child("target") ?? node.child("path"),
        ["simple_identifier", "identifier"].contains(receiver.kind) else { return }
      identifier = receiver
      end = node.end
    default: return
    }
    let spelling = input.text(identifier)
    guard byOwner[owner]?[spelling] == nil else { return }
    var lower = 0, upper = lineStarts.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if lineStarts[middle] <= identifier.start { lower = middle + 1 } else { upper = middle }
    }
    byOwner[owner, default: [:]][spelling] = .object([
      "name": .string(spelling), "line": .number(Double(lower)),
      "startByte": .number(Double(identifier.start)), "endByte": .number(Double(end)),
    ])
  }

  func apply(to nodes: inout [Entity]) {
    for (index, sites) in byOwner {
      let node = nodes[index]
      var attributes = node.attributes
      attributes["syntax.typeSites"] = .array(sites.keys.sorted().compactMap { sites[$0] })
      nodes[index] = Entity(id: node.id, kind: node.kind, language: node.language, name: node.name,
        identityKey: node.identityKey, entityRevision: node.entityRevision, anchor: node.anchor,
        attributes: attributes)
    }
  }
}
