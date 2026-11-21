import ArchitectureCore
import ArchitectureIR
import Foundation

struct PropertyMetadata {
  static func attributes(_ node: SyntaxNode, input: SourceInput) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    if input.language == "swift", node.kind == "property_declaration" {
      if let binding = node.child("mutability") ?? node.children.first(where: { $0.kind == "value_binding_pattern" })?.child("mutability"), ["let", "var"].contains(input.text(binding)) {
        result["declaration.binding"] = .string(input.text(binding))
      }
      result.merge(DeclarationAccess.attributes(node, input: input)) { _, new in new }
      if let name = node.child("name"), let index = node.children.firstIndex(where: { $0.start == name.start && $0.end == name.end }) {
        let binding = node.children.dropFirst(index + 1).prefix { $0.kind != "," && $0.field != "name" && $0.field != "value" }
        if let annotation = binding.first(where: { $0.kind == "type_annotation" }) {
          let spelling = input.text(annotation).dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
          if !spelling.isEmpty { result["declaration.type"] = .string(spelling) }
        }
      }
    } else if input.language == "rust", ["field_declaration", "const_item", "static_item"].contains(node.kind) {
      let binding = node.kind == "const_item" ? "const" : node.kind == "static_item"
        ? (node.children.contains { $0.kind == "mutable_specifier" } ? "static mut" : "static") : "field"
      result["declaration.binding"] = .string(binding)
      result.merge(DeclarationAccess.attributes(node, input: input)) { _, new in new }
      if let type = node.child("type") { result["declaration.type"] = .string(input.text(type)) }
    }
    return result
  }
}
