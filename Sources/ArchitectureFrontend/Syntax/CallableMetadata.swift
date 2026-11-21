import ArchitectureCore
import Foundation

struct CallableMetadata {
  static func attributes(_ node: SyntaxNode, input: SourceInput, ownerKind: String) -> [String: JSONValue] {
    var result = DeclarationAccess.attributes(node, input: input)
    let header = Array(node.children.prefix { $0.field != "body" && !["function_body", "block"].contains($0.kind) })
    if let parameters = node.child("parameters") {
      result["declaration.parameters"] = .string(input.text(parameters))
    } else if let opening = header.firstIndex(where: { $0.kind == "(" }) {
      var nesting = 0
      for item in header.dropFirst(opening) {
        if item.kind == "(" { nesting += 1 }
        if item.kind == ")" { nesting -= 1 }
        if nesting == 0 {
          let spelling = String(decoding: input.bytes[header[opening].start..<item.end], as: UTF8.self)
          result["declaration.parameters"] = .string(spelling)
          break
        }
      }
    } else if node.kind == "deinit_declaration" {
      result["declaration.parameters"] = .string("")
    }
    let keywords: Set<String> = ["static", "class", "mutating", "nonmutating", "nonisolated", "async", "throws", "rethrows", "unsafe", "const"]
    let containers: Set<String> = ["modifiers", "function_modifiers", "property_modifier", "member_modifier", "mutation_modifier", "function_effects"]
    var modifiers: [String] = []
    func collect(_ item: SyntaxNode) {
      if keywords.contains(item.kind) || item.kind == "extern_modifier" {
        modifiers.append(input.text(item))
      } else if containers.contains(item.kind) {
        if keywords.contains(input.text(item)) { modifiers.append(input.text(item)) }
        else { for child in item.children { collect(child) } }
      }
    }
    for item in header { collect(item) }
    result["declaration.modifiers"] = .array(modifiers.map(JSONValue.string))
    guard !["init_declaration", "deinit_declaration"].contains(node.kind) else {
      result["declaration.callable"] = CallableSignature.value(node, input: input, ownerKind: ownerKind, legacy: result)
      return result
    }
    if let arrow = header.firstIndex(where: { $0.kind == "->" }) {
      result["declaration.returnTypeExplicit"] = .bool(true)
      let type = header.dropFirst(arrow + 1).prefix { !["type_constraints", "where_clause", "where", ";"].contains($0.kind) }
      if let first = type.first, let last = type.last {
        let spelling = String(decoding: input.bytes[first.start..<last.end], as: UTF8.self)
        result["declaration.returnType"] = .string(spelling)
      }
    } else {
      result["declaration.returnTypeExplicit"] = .bool(false)
      result["declaration.returnType"] = .string(input.language == "swift" ? "Void" : "()")
    }
    result["declaration.callable"] = CallableSignature.value(node, input: input, ownerKind: ownerKind, legacy: result)
    return result
  }
}
