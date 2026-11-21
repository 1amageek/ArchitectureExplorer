import ArchitectureCore
import ArchitectureIR
import Foundation

/// Records declarations and import sites from one immutable TypeScript input.
struct TypeScriptOutline {
  let input: SourceInput
  let tree: SyntaxNode
  let producer: String

  func result() throws -> FrontendResult {
    let evidence = Evidence(
      id: CanonicalJSON.identity(producer + ":" + input.path + ":" + input.digest + ":" + input.contextDigest),
      producer: producer, inputDigest: input.digest, contextDigest: input.contextDigest,
      anchor: input.anchor(0, input.bytes.count))
    let key = input.workspaceID + ":file:" + input.path
    let file = Entity(id: CanonicalJSON.identity(key), kind: "file", language: input.language,
      name: input.path, identityKey: key, entityRevision: input.digest, anchor: evidence.anchor,
      attributes: ["syntax.relativeImports": .array(importSites())])
    var entities = [file]
    var facts: [Fact] = []
    var occurrences: [String: Int] = [:]
    var pending: [(SyntaxNode, Entity)] = [(tree, file)]
    while let (node, parent) = pending.popLast() {
      try Task.checkCancellation()
      var owner = parent
      if let (role, kind) = Self.declaration(node.kind), let nameNode = node.child("name"),
        ["identifier", "type_identifier", "property_identifier", "private_property_identifier"].contains(nameNode.kind)
      {
        let name = input.text(nameNode)
        let base = parent.identityKey + ":" + kind + ":" + name
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        let key = base + ":" + String(occurrence)
        let headerEnd = node.child("body")?.start ?? node.child("value")?.start ?? node.end
        let signature = String(decoding: input.bytes[node.start..<headerEnd], as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        owner = Entity(id: CanonicalJSON.identity(key), kind: kind, language: input.language,
          name: name, identityKey: key, entityRevision: CanonicalJSON.digest(input.bytes[node.start..<node.end]),
          anchor: input.anchor(node.start, node.end),
          attributes: ["declaration.kind": .string(role), "syntax.signature": .string(signature)])
        entities.append(owner)
        facts.append(Fact(id: CanonicalJSON.identity(producer + ":contains:" + owner.id),
          producer: producer, scope: input.path, kind: "contains", source: parent.id, target: owner.id,
          revision: input.digest, evidenceIDs: [evidence.id]))
      }
      for child in node.namedChildren.reversed() { pending.append((child, owner)) }
    }
    return FrontendResult(entities: entities, facts: facts, evidence: [evidence],
      coverage: Coverage(producer: producer, scope: input.path, language: input.language,
        completeness: "partial", exclusions: ["compiler resolution", "dynamic imports", "control-flow graphs"]))
  }

  private func importSites() -> [JSONValue] {
    var byte = 0, line = 1
    return tree.namedChildren.compactMap { node in
      guard ["import_statement", "export_statement"].contains(node.kind),
        let literal = node.child("source"), literal.kind == "string" else { return nil }
      let raw = input.text(literal)
      let path = String(raw.dropFirst().dropLast())
      guard path.hasPrefix("./") || path.hasPrefix("../"),
        !path.contains("\\"), !path.contains("?"), !path.contains("#"), !path.contains("%") else { return nil }
      while byte < node.start {
        if input.bytes[byte] == 10 { line += 1 }
        byte += 1
      }
      return .object(["path": .string(path), "startByte": .number(Double(node.start)),
        "endByte": .number(Double(node.end)), "line": .number(Double(line))])
    }
  }

  private static func declaration(_ node: String) -> (role: String, kind: String)? {
    switch node {
    case "class_declaration", "abstract_class_declaration": ("class", "type")
    case "interface_declaration": ("interface", "interface")
    case "enum_declaration": ("enum", "type")
    case "type_alias_declaration": ("typeAlias", "type")
    case "function_declaration", "function_signature": ("function", "function")
    case "method_definition", "method_signature": ("method", "method")
    case "variable_declarator": ("variable", "variable")
    case "public_field_definition", "property_signature": ("field", "field")
    default: nil
    }
  }
}
