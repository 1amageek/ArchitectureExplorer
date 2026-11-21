import ArchitectureCore

struct CallableSignature {
  static func value(_ node: SyntaxNode, input: SourceInput, ownerKind: String, legacy: [String: JSONValue]) -> JSONValue {
    let header = Array(node.children.prefix { $0.field != "body" && !["function_body", "block"].contains($0.kind) })
    let modifiers = legacy["declaration.modifiers"]?.array.compactMap(\.string) ?? []
    let effects = modifiers.filter { ["async", "throws", "rethrows"].contains($0) }
    let safety = modifiers.filter { $0 == "unsafe" }
    var result: [String: JSONValue] = [
      "version": .number(1), "effects": .array(effects.map(JSONValue.string)),
      "safety": .array(safety.map(JSONValue.string)),
      "modifiers": .array(modifiers.filter { !effects.contains($0) && !safety.contains($0) }.map(JSONValue.string)),
    ]
    if let access = legacy["declaration.access"] { result["access"] = access }
    let generic = header.first { $0.kind == "type_parameters" }
    result["typeParameters"] = .array((generic?.namedChildren ?? []).map { .string(input.text($0)) })
    result["constraints"] = .array(header.filter { ["type_constraints", "where_clause"].contains($0.kind) }.map { .string(input.text($0)) })
    let annotations = header.flatMap { $0.kind == "modifiers" ? $0.children : [$0] }.filter { ["attribute", "attribute_item"].contains($0.kind) }
    result["annotations"] = .array(annotations.map { .string(input.text($0)) })
    var parameters: [JSONValue] = []
    var receiver: [String: JSONValue] = ["kind": .string("none")]
    if ["type", "actor", "interface"].contains(ownerKind) {
      receiver = ["kind": .string(input.language == "rust" || modifiers.contains("static") || modifiers.contains("class") ? "type" : "instance")]
    }
    let items = node.child("parameters")?.children ?? header
    for (index, item) in items.enumerated() where ["parameter", "self_parameter", "variadic_parameter"].contains(item.kind) {
      let pattern = item.child("pattern")
      if input.language == "rust", item.kind == "self_parameter" || pattern?.kind == "self" {
        let reference = item.children.contains { $0.kind == "&" }
        let mutable = item.children.contains { $0.kind == "mutable_specifier" }
        let kind = item.child("type") != nil ? "explicitType" : reference ? (mutable ? "mutableBorrow" : "sharedBorrow") : "owned"
        receiver = ["kind": .string(kind), "spelling": .string(input.text(item))]
        if let type = item.child("type") { receiver["type"] = .string(input.text(type)) }
        continue
      }
      var end = item.end
      // Direct delimiters separate parameters; nested default-expression commas stay inside their AST node.
      if input.language == "swift" {
        for sibling in items.dropFirst(index + 1) {
          if [",", ")"].contains(sibling.kind) { break }
          end = sibling.end
        }
      }
      var parameter: [String: JSONValue] = ["spelling": .string(String(decoding: input.bytes[item.start..<end], as: UTF8.self))]
      if input.language == "swift" {
        if let name = item.children.first(where: { $0.field == "name" && $0.kind == "simple_identifier" }) { parameter["name"] = .string(input.text(name)) }
        if let label = item.child("external_name") { parameter["label"] = .string(input.text(label)) }
        if let type = item.children.last(where: { $0.field == "name" && $0.kind != "simple_identifier" }) { parameter["type"] = .string(input.text(type)) }
        let passing = item.children.filter { $0.kind == "parameter_modifiers" }.flatMap(\.namedChildren)
        parameter["passing"] = .array(passing.map { .string(input.text($0)) })
      } else {
        if let pattern { parameter["name"] = .string(input.text(pattern)) }
        if let type = item.child("type") { parameter["type"] = .string(input.text(type)) }
      }
      parameters.append(.object(parameter))
    }
    if legacy["declaration.parameters"] != nil { result["parameters"] = .array(parameters) }
    result["receiver"] = .object(receiver)
    if ["init_declaration", "deinit_declaration"].contains(node.kind) {
      result["resultStatus"] = .string("notApplicable")
      result["results"] = .array([])
    } else if let type = legacy["declaration.returnType"] {
      result["resultStatus"] = .string("recorded")
      result["results"] = .array([.object(["type": type, "origin": .string(legacy["declaration.returnTypeExplicit"]?.bool == true ? "explicit" : "languageDefault")])])
    } else { result["resultStatus"] = .string("unknown") }
    return .object(result)
  }
}
