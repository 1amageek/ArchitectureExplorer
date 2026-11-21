import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ControlFlowProvider: Sendable {
  public static let version = "2.0"
  public init() {}
  public func hasSupportedGraph(for functionID: String, in snapshot: Snapshot) -> Bool {
    guard let anchor = snapshot.entities.first(where: { $0.id == functionID })?.anchor,
      snapshot.coverage.contains(where: {
        $0.producer == "cfg.tree-sitter" && $0.scope == functionID
      })
    else { return false }
    let facts = snapshot.facts.filter {
      $0.producer == "cfg.tree-sitter" && $0.scope == functionID && $0.kind == "controlFlow"
    }
    let ids = Set(facts.flatMap(\.evidenceIDs))
    let evidence = Dictionary(uniqueKeysWithValues: snapshot.evidence.map { ($0.id, $0) })
    return !facts.isEmpty && !ids.isEmpty
      && ids.allSatisfy { id in
        guard let item = evidence[id] else { return false }
        return item.producer == "cfg.tree-sitter" && item.version == Self.version
          && item.inputDigest == anchor.digest && item.contextDigest == snapshot.contextDigest
          && item.anchor == anchor
      }
  }
  public func analyze(_ input: SourceInput, function: Entity) throws -> FrontendResult {
    guard ["swift", "rust"].contains(input.language) else {
      throw ArchitectureError("UNSUPPORTED_CAPABILITY", "Control-flow analysis is unavailable for " + input.language + ".", exitCode: 3)
    }
    let root = try SyntaxParser().parse(input)
    guard let anchor = function.anchor, anchor.digest == input.digest else {
      throw ArchitectureError(
        "STALE_ANALYSIS", "CFG source revision no longer matches the selected function.",
        exitCode: 7)
    }
    let declarations = root.descendants([
      "function_declaration", "function_item", "init_declaration",
    ])
    guard
      let declaration = declarations.first(where: {
        $0.start == anchor.startByte && $0.end == anchor.endByte
      }), let body = declaration.child("body")
    else {
      throw ArchitectureError(
        "UNSUPPORTED_CAPABILITY", "Selected declaration has no supported function body.",
        exitCode: 3)
    }
    let tokens = declaration.descendants([
      "async", "await", "throws", "rethrows", "throw", "defer", "try", "?", "&&", "||", "for",
      "switch", "match", "loop", "yield", "unsafe", "label", "lambda_literal", "closure_expression",
      "macro_invocation", "if_config_declaration", "conditional_compilation_block",
    ])
    guard tokens.isEmpty else {
      throw ArchitectureError(
        "UNSUPPORTED_CAPABILITY",
        "CFG cannot model \(tokens.first!.kind); no complete CFG was produced.", exitCode: 3)
    }
    let producer = "cfg.tree-sitter"
    let evidenceID = CanonicalJSON.identity(
      producer + ":" + function.id + ":" + input.digest + ":" + input.contextDigest)
    var nodes: [Entity] = []
    var edges: [Fact] = []
    var serial = 0
    func block(_ label: String, _ source: SyntaxNode?, synthetic: Bool = false) -> String {
      serial += 1
      let key = function.identityKey + ":cfg:" + String(serial)
      let id = CanonicalJSON.identity(key)
      let range =
        source.map { input.anchor($0.start, $0.end) } ?? input.anchor(body.start, body.start)
      nodes.append(
        Entity(
          id: id, kind: "basicBlock", language: input.language, name: label, identityKey: key,
          entityRevision: input.digest, anchor: range,
          attributes: [
            "cfg.synthetic": .bool(synthetic), "cfg.functionID": .string(function.id),
            "cfg.profile": .string("synchronous-structured-v1"),
          ]))
      return id
    }
    func edge(_ from: String, _ to: String, _ label: String) {
      let key = producer + ":" + function.id + ":" + from + ":" + to + ":" + label
      edges.append(
        Fact(
          id: CanonicalJSON.identity(key), producer: producer, scope: function.id,
          kind: "controlFlow", source: from, target: to, revision: input.digest,
          evidenceIDs: [evidenceID], attributes: ["cfg.branch": .string(label)]))
    }
    let exit = block("normal exit", nil, synthetic: true)
    let leaves: Set<String> = [
      "simple_identifier", "identifier", "field_identifier", "integer_literal", "real_literal",
      "float_literal", "boolean_literal", "boolean", "nil", "self", "super", "type_identifier",
      "primitive_type", "line_string_literal", "string_literal", "line_str_text", "string_content",
      "line_string_text", "string_segment", "character_literal",
    ]
    let containers: Set<String> = [
      "assignment", "assignment_expression", "compound_assignment_expr", "additive_expression",
      "multiplicative_expression", "comparison_expression", "equality_expression",
      "binary_expression", "prefix_expression", "unary_expression",
      "directly_assignable_expression", "navigation_expression", "navigation_suffix",
      "field_expression", "call_expression", "call_suffix", "value_arguments", "value_argument",
      "arguments", "parenthesized_expression", "tuple_expression", "tuple_literal",
      "property_declaration", "let_declaration", "value_binding_pattern", "pattern",
      "binding_pattern", "mutable_specifier", "user_type", "type_annotation", "array_type",
      "optional_type", "modifiers",
    ]
    func expression(_ node: SyntaxNode) throws {
      guard node.named else { return }
      if leaves.contains(node.kind) { return }
      guard containers.contains(node.kind) else {
        throw ArchitectureError(
          "UNSUPPORTED_CAPABILITY", "Unmodeled CFG expression: \(node.kind).", exitCode: 3)
      }
      for child in node.namedChildren { try expression(child) }
    }
    func statements(_ node: SyntaxNode) -> [SyntaxNode] {
      if let list = node.children.first(where: { $0.kind == "statements" }) {
        return list.namedChildren
      }
      return node.namedChildren
    }
    func sequence(
      _ values: [SyntaxNode], next: String, loop: (breakTo: String, continueTo: String)?
    ) throws -> String {
      var destination = next
      for value in values.reversed() {
        destination = try statement(value, next: destination, loop: loop)
      }
      return destination
    }
    func statement(
      _ original: SyntaxNode, next: String, loop: (breakTo: String, continueTo: String)?
    ) throws -> String {
      let node =
        original.kind == "expression_statement"
        ? (original.namedChildren.first ?? original) : original
      if ["block", "statements", "function_body"].contains(node.kind) {
        return try sequence(statements(node), next: next, loop: loop)
      }
      if ["if_statement", "if_expression", "guard_statement"].contains(node.kind) {
        let conditions = node.children.filter { $0.field == "condition" }
        guard conditions.count == 1, let condition = conditions.first else {
          throw ArchitectureError(
            "UNSUPPORTED_CAPABILITY", "CFG requires one non-pattern condition.", exitCode: 3)
        }
        try expression(condition)
        let test = block(input.text(condition), condition)
        let branches = node.children.filter {
          $0.kind == "statements" || $0.kind == "block" || $0.field == "alternative"
            || $0.kind == "if_statement"
        }
        guard let first = branches.first else {
          throw ArchitectureError(
            "UNSUPPORTED_CAPABILITY", "Missing conditional branch.", exitCode: 3)
        }
        if node.kind == "guard_statement" {
          let failure = try sequence(statements(first), next: exit, loop: loop)
          edge(test, next, "true")
          edge(test, failure, "false")
        } else {
          let positive = try statement(first, next: next, loop: loop)
          let negative: String
          if branches.count > 1 {
            let alternate = branches[1]
            if alternate.kind == "else_clause", let inner = alternate.namedChildren.first {
              negative = try statement(inner, next: next, loop: loop)
            } else {
              negative = try statement(alternate, next: next, loop: loop)
            }
          } else {
            negative = next
          }
          edge(test, positive, "true")
          edge(test, negative, "false")
        }
        return test
      }
      if ["while_statement", "while_expression"].contains(node.kind) {
        let conditions = node.children.filter { $0.field == "condition" }
        guard !conditions.isEmpty,
          let body = node.child("body") ?? node.children.first(where: { $0.kind == "statements" })
        else {
          throw ArchitectureError(
            "UNSUPPORTED_CAPABILITY", "Unsupported while pattern.", exitCode: 3)
        }
        for condition in conditions { try expression(condition) }
        let tests = conditions.map { block(input.text($0), $0) }
        let first = tests[0]
        let bodyEntry = try sequence(statements(body), next: first, loop: (next, first))
        for (index, test) in tests.enumerated() {
          edge(test, index + 1 < tests.count ? tests[index + 1] : bodyEntry, "true")
          edge(test, next, "false")
        }
        return first
      }
      let control =
        node.kind == "control_transfer_statement" ? node.children.first?.kind : node.kind
      if control == "return" || control == "return_expression" {
        for child in node.namedChildren { try expression(child) }
        let result = block(input.text(node), node)
        edge(result, exit, "return")
        return result
      }
      if ["break", "continue", "break_expression", "continue_expression"].contains(control ?? "") {
        guard let loop, node.namedChildren.isEmpty else {
          throw ArchitectureError(
            "UNSUPPORTED_CAPABILITY", "Unresolved/labeled loop transfer or break value.",
            exitCode: 3)
        }
        let result = block(input.text(node), node)
        edge(
          result, (control!.hasPrefix("break") ? loop.breakTo : loop.continueTo),
          control!.hasPrefix("break") ? "break" : "continue")
        return result
      }
      try expression(node)
      let result = block(input.text(node), node)
      edge(result, next, "next")
      return result
    }
    let first = try sequence(statements(body), next: exit, loop: nil)
    let entry = block("entry", nil, synthetic: true)
    edge(entry, first, "entry")
    for node in nodes {
      edges.append(
        Fact(
          id: CanonicalJSON.identity(function.id + ":cfg:contains:" + node.id), producer: producer,
          scope: function.id, kind: "contains", source: function.id, target: node.id,
          revision: input.digest, evidenceIDs: [evidenceID]))
    }
    let evidence = Evidence(
      id: evidenceID, producer: producer, version: Self.version, inputDigest: input.digest,
      contextDigest: input.contextDigest, anchor: anchor)
    return FrontendResult(
      entities: nodes, facts: edges, evidence: [evidence],
      coverage: Coverage(
        producer: producer, scope: function.id, language: input.language,
        completeness: "completeWithinScope",
        exclusions: [
          "path feasibility", "call internals", "exceptional runtime failures",
          "state-space exploration",
        ]))
  }
}
