import ArchitectureCore

struct DeclarationAccess {
  static func attributes(_ node: SyntaxNode, input: SourceInput) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    if input.language == "swift", let modifiers = node.children.first(where: { $0.kind == "modifiers" }) {
      for access in modifiers.children where access.kind == "visibility_modifier" {
        guard let keyword = access.children.first else { continue }
        let setter = access.children.contains { $0.kind == "set" }
        result[setter ? "declaration.setterAccess" : "declaration.access"] = .string(input.text(keyword))
      }
    } else if input.language == "rust", let access = node.children.first(where: { $0.kind == "visibility_modifier" }) {
      result["declaration.access"] = .string(input.text(access))
    }
    return result
  }
}
