import ArchitectureCore
import Foundation

public enum RepositoryOutline {
  private static let roles = [
    "class_declaration": "Class", "abstract_class_declaration": "Class", "struct_item": "Struct",
    "interface_declaration": "Interface", "protocol_declaration": "Protocol", "trait_item": "Trait",
    "enum_declaration": "Enum", "enum_item": "Enum", "type_alias_declaration": "Type alias",
    "function_item": "Function", "function_declaration": "Function", "method_definition": "Method",
    "method_signature": "Method", "property_signature": "Property", "public_field_definition": "Field",
    "variable_declarator": "Variable", "init_declaration": "Initializer", "impl_item": "Implementation",
    "type_item": "Type alias", "struct_declaration": "Struct", "actor_declaration": "Actor"
  ]

  public static func annotate(_ scope: JSONValue) -> JSONValue {
    guard let source = scope["text"].string, let path = scope["title"].string else { return scope }
    var result = scope.object
    let ext = (path as NSString).pathExtension.lowercased()
    let language = ["ts": "typescript", "tsx": "typescript", "swift": "swift", "rs": "rust"][ext]
    guard let language else { return scope }
    guard scope["truncated"].bool == false else {
      result["outlineNotice"] = .string("Outline unavailable: the file exceeds the source preview budget.")
      return .object(result)
    }
    let input = SourceInput(workspaceID: "", path: path, language: language, bytes: Data(source.utf8), contextDigest: "", generation: 0)
    do {
      let syntax = try SyntaxParser().parse(input)
      var nodes: [JSONValue] = []
      var byte = 0, line = 1
      var pending: [(SyntaxNode, String?)] = [(syntax, nil)]
      while let (node, parent) = pending.popLast() {
        var owner = parent
        if var role = roles[node.kind] {
          if language == "swift", node.kind == "class_declaration", let keyword = node.children.first(where: { ["struct", "actor", "enum", "extension", "class"].contains($0.kind) }) {
            role = keyword.kind.capitalized
          }
          let name = node.child("name") ?? node.child("type")
          let label = name.map(input.text) ?? (node.kind == "init_declaration" ? "init" : nil)
          if let label {
            guard nodes.count < 300 else { throw ArchitectureError("RESOURCE_LIMIT", "File outline exceeds 300 declarations.") }
            // Preorder visits declaration starts monotonically; scan line breaks once per file.
            while byte < node.start {
              if input.bytes[byte] == 10 { line += 1 }
              byte += 1
            }
            let id = "\(node.kind)-\(node.start)"
            var card: [String: JSONValue] = ["id": .string(id), "label": .string(label), "role": .string(role), "language": .string(language),
              "startByte": .number(Double(node.start)), "endByte": .number(Double(node.end)),
              "details": .object(["status": .string("Line \(line)")])]
            if let parent { card["parentID"] = .string(parent) }
            nodes.append(.object(card)); owner = id
          }
        }
        for child in node.children.reversed() where child.named { pending.append((child, owner)) }
      }
      result["nodes"] = .array(nodes)
      if nodes.isEmpty { result["outlineNotice"] = .string("No supported declarations in this file.") }
    } catch { result["outlineNotice"] = .string(String(describing: error)) }
    return .object(result)
  }
}
