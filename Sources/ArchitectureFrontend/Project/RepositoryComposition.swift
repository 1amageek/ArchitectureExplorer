import ArchitectureCore
import CArchitectureSyntax
import Foundation

enum RepositoryComposition {
  /// Static references in the selected entry module. Neither execution order nor runtime binding is inferred.
  static func project(service: String, checkout: String, path: [String], source: String) throws -> JSONValue {
    let filename = path.joined(separator: "/")
    let input = SourceInput(workspaceID: checkout, path: filename, language: "typescript", bytes: Data(source.utf8), contextDigest: "", generation: 0)
    let tree = try SyntaxParser().parse(input, grammar: tree_sitter_tsx())
    var imports: [String: String] = [:]
    for statement in tree.namedChildren where statement.kind == "import_statement" {
      guard let location = statement.child("source") else { continue }
      for spec in statement.descendants(["import_specifier"]) {
        if let binding = spec.child("alias") ?? spec.child("name") { imports[input.text(binding)] = input.text(location) }
      }
    }
    var graph = RepositoryArchitecture.Graph()
    let origin = "entry"
    graph.node(origin, service, "Service entry point", filename, language: input.language, source: path)
    var stack = [tree]
    var cursor = 0, line = 1
    while let node = stack.popLast() {
      stack.append(contentsOf: node.namedChildren.reversed())
      let binding: String, operation: String
      if node.kind == "new_expression", let ctor = node.child("constructor"), ctor.kind == "identifier" {
        binding = input.text(ctor); operation = "Constructs"
      } else if node.kind == "call_expression", let callee = node.child("function"), callee.kind == "member_expression",
                let base = callee.child("object"), base.kind == "identifier", let property = callee.child("property") {
        binding = input.text(base); operation = "Calls ." + input.text(property)
      } else { continue }
      guard let module = imports[binding] else { continue }
      let id = "binding:" + binding
      graph.node(id, binding, "Imported binding", module, language: input.language)
      while cursor < node.start {
        if input.bytes[cursor] == 10 { line += 1 }
        cursor += 1
      }
      graph.edge(origin, id, operation, "candidateCalls", filename + ":" + String(line) + " · " + operation + " " + binding + " · imported from " + module)
    }
    if graph.edges.isEmpty { graph.notice = "No supported construction or member-call sites on named imports in this entry point." }
    return try graph.view(service, "Entry-point composition", checkout: checkout)
  }
}
