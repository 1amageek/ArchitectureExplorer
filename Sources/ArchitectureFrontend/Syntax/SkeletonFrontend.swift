import ArchitectureCore
import ArchitectureIR
import Foundation
import SkeletonIndexCore
import SkeletonRustParser
import SkeletonSwiftParser

public struct SkeletonFrontend: FrontendProvider {
  public let identity = "syntax.tree-sitter+skeleton"
  public init() {}
  public func capabilities() -> [Capability] {
    ["swift", "rust"].flatMap { language in
      [
        Capability(
          language: language, producer: identity, feature: "declarations", supported: true,
          scope: "saved UTF-8 source; lexical ownership",
          reason: "Pinned skeleton index plus original AST supplemental adapter."),
        Capability(
          language: language, producer: identity, feature: "callSites", supported: true,
          scope: "syntactic call expressions; unresolved targets",
          reason: "Syntax alone cannot establish dispatch targets."),
        Capability(
          language: language, producer: "cfg.tree-sitter", feature: "cfg", supported: true,
          scope: "synchronous sequential/if/while/return/break/continue; Swift guard",
          reason: "Unsupported control effects reject the entire function."),
      ]
    } + [Capability(language: "typescript", producer: identity, feature: "declarations", supported: true,
      scope: "saved TypeScript/TSX; lexical declarations and static relative imports",
      reason: "Original AST extraction; compiler resolution and CFG are outside this capability.")]
  }
  public func analyze(_ input: SourceInput) throws -> FrontendResult {
    let root = try SyntaxParser().parse(input)
    if input.language == "typescript" { return try TypeScriptOutline(input: input, tree: root, producer: identity).result() }
    let source = String(decoding: input.bytes, as: UTF8.self)
    // FIXME(INCOMPLETE_IMPLEMENTATION): The upstream skeleton pass is synchronous and cannot be forcibly cancelled.
    // The production syntax provider invokes it after the bounded original-AST parse.
    // Do not claim adversarial-input deadline coverage until isolated-worker termination tests pass.
    let skeleton: ParsedFile
    if input.language == "swift" {
      skeleton = SwiftSkeletonParser().parse(path: input.path, source: source)
    } else {
      skeleton = RustSkeletonParser().parse(path: input.path, source: source)
    }
    guard !skeleton.hasParseError else {
      throw ArchitectureError("SOURCE_PARSE_FAILED", "Skeleton rejected \(input.path).")
    }
    let fileKey = input.workspaceID + ":file:" + input.path
    let fileID = CanonicalJSON.identity(fileKey)
    let evidenceID = CanonicalJSON.identity(
      identity + ":" + input.path + ":" + input.digest + ":" + input.contextDigest)
    let evidence = Evidence(
      id: evidenceID, producer: identity, inputDigest: input.digest,
      contextDigest: input.contextDigest, anchor: input.anchor(0, input.bytes.count))
    var nodes = [
      Entity(
        id: fileID, kind: "file", language: input.language, name: input.path, identityKey: fileKey,
        entityRevision: input.digest, anchor: input.anchor(0, input.bytes.count),
        attributes: [
          "skeleton.blockCount": .number(Double(skeleton.blocks.count)),
          "skeleton.revision": .string("1215a3bd86d172e07151c7ccc9a213cb6ea27434"),
        ])
    ]
    var facts: [Fact] = []
    var duplicates: [String: Int] = [:]
    var edgeIDs = Set<String>()
    func edge(_ kind: String, _ from: String, _ to: String, attributes: [String: JSONValue] = [:]) {
      let key = identity + ":" + input.path + ":" + kind + ":" + from + ":" + to
      let id = CanonicalJSON.identity(key)
      guard edgeIDs.insert(id).inserted else { return }
      facts.append(
        Fact(
          id: id, producer: identity, scope: input.path, kind: kind, source: from, target: to,
          revision: input.digest, evidenceIDs: [evidenceID], attributes: attributes))
    }
    let types: Set<String> = [
      "class_declaration", "struct_declaration", "enum_declaration", "protocol_declaration",
      "actor_declaration", "extension_declaration", "struct_item", "enum_item", "trait_item",
      "impl_item", "union_item", "mod_item",
    ]
    let functions: Set<String> = [
      "function_declaration", "init_declaration", "deinit_declaration", "function_item",
      "function_signature_item",
    ]
    let members: Set<String> = [
      "property_declaration", "field_declaration", "const_item", "static_item", "type_item",
      "associatedtype_declaration",
    ]
    let swiftTypeKeywords: Set<String> = ["class", "struct", "enum", "actor", "protocol", "extension"]
    func normalized(_ node: SyntaxNode, before: Int) -> String {
      func tokens(_ n: SyntaxNode) -> [String] {
        guard n.start < before else { return [] }
        if n.children.isEmpty { return [input.text(n)] }
        return n.children.flatMap(tokens)
      }
      return tokens(node).joined(separator: " ")
    }
    var sites = TypeReferenceSites(bytes: input.bytes)
    var pending: [(SyntaxNode, Entity, Entity?, [String], Int?, String)] = [(root, nodes[0], nil, [], nil, "")]
    while let (node, owner, callable, priorConditions, enclosingType, parentKind) = pending.popLast() {
      var typeIndex = enclosingType
      var currentOwner = owner
      var currentCallable = callable
      var conditions = priorConditions
      if ["conditional_compilation_block", "if_config_declaration", "attribute_item"].contains(
        node.kind)
      {
        conditions.append(input.text(node))
      }
      let isFunction = functions.contains(node.kind)
      let isType = types.contains(node.kind)
      let isMember = members.contains(node.kind)
      if isFunction || isType || isMember {
        let body =
          node.child("body")
          ?? node.children.first {
            [
              "function_body", "class_body", "enum_class_body", "protocol_body", "declaration_list",
              "field_declaration_list", "block",
            ].contains($0.kind)
          }
        let nameNode =
          node.child("name")
          ?? node.children.first {
            ["simple_identifier", "type_identifier", "identifier", "user_type", "pattern"].contains(
              $0.kind)
          }
        let name =
          nameNode.map(input.text)
          ?? (node.kind.contains("init")
            ? node.kind.replacingOccurrences(of: "_declaration", with: "")
            : input.text(node).prefix(80).description)
        let initializer = isMember ? node.children.first(where: { $0.kind == "=" })?.start : nil
        let signature = normalized(node, before: body?.start ?? initializer ?? node.end)
        let kind: String
        if isFunction {
          kind = ["type", "actor", "interface"].contains(owner.kind) ? "method" : "function"
        } else if isMember {
          kind = owner.kind == "file" ? "property" : "field"
        } else if node.kind == "mod_item" {
          kind = "module"
        } else if node.kind.contains("protocol") || node.kind == "trait_item" {
          kind = "interface"
        } else if node.child("declaration_kind")?.kind == "actor"
          || node.kind == "actor_declaration"
        {
          kind = "actor"
        } else {
          kind = "type"
        }
        let baseKey = owner.identityKey + ":" + kind + ":" + signature
        let occurrence = duplicates[baseKey, default: 0]
        duplicates[baseKey] = occurrence + 1
        let key = baseKey + ":occurrence:" + String(occurrence)
        var attrs: [String: JSONValue] = [
          "syntax.kind": .string(node.kind), "syntax.signature": .string(signature),
        ]
        attrs.merge(PropertyMetadata.attributes(node, input: input)) { _, new in new }
        if isFunction { attrs.merge(CallableMetadata.attributes(node, input: input, ownerKind: owner.kind)) { _, new in new } }
        let declarationKind: String?
        if input.language == "swift",
          let keyword = node.child("declaration_kind")?.kind
            ?? node.children.first(where: { swiftTypeKeywords.contains($0.kind) })?.kind,
          swiftTypeKeywords.contains(keyword)
        {
          declarationKind = keyword
        } else {
          switch node.kind {
          case "struct_declaration", "struct_item": declarationKind = "struct"
          case "enum_declaration", "enum_item": declarationKind = "enum"
          case "actor_declaration": declarationKind = "actor"
          case "protocol_declaration": declarationKind = "protocol"
          case "extension_declaration": declarationKind = "extension"
          case "trait_item": declarationKind = "trait"
          case "impl_item": declarationKind = "implementation"
          case "union_item": declarationKind = "union"
          case "mod_item": declarationKind = "module"
          case "init_declaration": declarationKind = "initializer"
          case "deinit_declaration": declarationKind = "deinitializer"
          case "const_item": declarationKind = "constant"
          case "static_item": declarationKind = "static"
          case "type_item": declarationKind = "typeAlias"
          case "associatedtype_declaration": declarationKind = "associatedType"
          default:
            if input.language == "rust", isFunction, kind == "method",
              node.child("parameters")?.children.contains(where: { $0.kind == "self_parameter" || $0.child("pattern")?.kind == "self" }) == false
            {
              declarationKind = "associatedFunction"
            } else {
              declarationKind = isFunction || isMember ? kind : nil
            }
          }
        }
        if let declarationKind { attrs["declaration.kind"] = .string(declarationKind) }
        if !conditions.isEmpty {
          attrs["syntax.conditions"] = .array(conditions.map(JSONValue.string))
          attrs["syntax.activation"] = .string("unknown")
        }
        if let body {
          attrs["syntax.bodyStart"] = .number(Double(body.start))
          attrs["syntax.bodyEnd"] = .number(Double(body.end))
        }
        let entity = Entity(
          id: CanonicalJSON.identity(key), kind: kind, language: input.language, name: name,
          identityKey: key,
          entityRevision: CanonicalJSON.digest(input.bytes[node.start..<node.end]),
          anchor: input.anchor(node.start, node.end), attributes: attrs)
        if ["type", "actor", "interface"].contains(kind) { typeIndex = nodes.count }
        nodes.append(entity)
        edge("contains", owner.id, entity.id)
        currentOwner = entity
        if isFunction { currentCallable = entity }
      }
      if node.kind == "call_expression", let caller = currentCallable {
        let function =
          node.child("function")
          ?? node.children.first {
            $0.kind != "call_suffix" && $0.kind != "value_arguments" && $0.kind != "arguments"
          }
        let name = function.map(input.text) ?? "unresolved call"
        let base = caller.identityKey + ":callsite:" + name
        let occurrence = duplicates[base, default: 0]
        duplicates[base] = occurrence + 1
        let key = base + ":" + String(occurrence)
        let site = Entity(
          id: CanonicalJSON.identity(key), kind: "callSite", language: input.language, name: name,
          identityKey: key, entityRevision: input.digest, anchor: input.anchor(node.start, node.end)
        )
        let targetKey =
          input.workspaceID + ":unresolved:" + input.path + ":" + caller.id + ":" + name
        let targetID = CanonicalJSON.identity(targetKey)
        nodes.append(site)
        if !nodes.contains(where: { $0.id == targetID }) {
          nodes.append(
            Entity(
              id: targetID, kind: "unresolvedSymbol", language: input.language, name: name,
              identityKey: targetKey, entityRevision: input.digest,
              attributes: [
                "reason": .string("Semantic provider has not resolved this call expression.")
              ]))
        }
        edge("contains", caller.id, site.id)
        edge("candidateCalls", site.id, targetID)
      }
      if ["import_declaration", "use_declaration", "extern_crate_declaration"].contains(node.kind) {
        let name = input.text(node)
        let key = input.workspaceID + ":external-import:" + input.language + ":" + name
        let targetID = CanonicalJSON.identity(key)
        if !nodes.contains(where: { $0.id == targetID }) {
          nodes.append(
            Entity(
              id: targetID, kind: "externalSymbol", language: input.language, name: name,
              identityKey: key, entityRevision: input.digest))
        }
        edge("imports", fileID, targetID)
      }
      if ["user_type", "primitive_type", "type_identifier"].contains(node.kind),
        node.field != "name", currentOwner.kind != "file"
      {
        let name = input.text(node)
        let key = input.workspaceID + ":unresolved-type:" + input.language + ":" + name
        let targetID = CanonicalJSON.identity(key)
        if !nodes.contains(where: { $0.id == targetID }) {
          nodes.append(
            Entity(
              id: targetID, kind: "unresolvedSymbol", language: input.language, name: name,
              identityKey: key, entityRevision: input.contextDigest,
              attributes: [
                "reason": .string("Syntactic type spelling; semantic binding is not established.")
              ]))
        }
        edge("usesType", currentOwner.id, targetID, attributes: ["basis": .string("syntax")])
      }
      if let typeIndex { sites.record(node, parent: parentKind, owner: typeIndex, input: input) }
      for child in node.namedChildren.reversed() {
        pending.append((child, currentOwner, currentCallable, conditions, typeIndex, node.kind))
      }
    }
    sites.apply(to: &nodes)
    let coverage = Coverage(
      producer: identity, scope: input.path, language: input.language, completeness: "partial",
      exclusions: [
        "semantic binding", "macro expansion", "active build configuration", "generated sources",
        "project targets without trust",
      ])
    return FrontendResult(entities: nodes, facts: facts, evidence: [evidence], coverage: coverage)
  }
}
