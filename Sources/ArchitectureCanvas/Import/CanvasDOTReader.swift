import ArchitectureCore
import Foundation

final class CanvasDOTReader {
  private struct Token { var value: String; var literal = false }
  private var tokens: [Token] = []
  private var strict = false
  private var index = 0
  private let builder: CanvasBuilder
  private var directed = true
  private var depth = 0
  private var nodeDefaults: [String: String] = [:]
  private var ports: [String: String] = [:]
  private var edgeDefaults: [String: String] = [:]
  init(text: String, builder: CanvasBuilder) throws { self.builder = builder; tokens = try Self.lex(text) }
  private var peek: String { index < tokens.count ? (tokens[index].literal ? "\u{0}" + tokens[index].value : tokens[index].value) : "" }
  @discardableResult private func take() throws -> String { guard index < tokens.count else { throw CanvasSyntax.invalid("Unexpected end of DOT.") }; defer { index += 1 }; return tokens[index].value }
  private func expect(_ token: String) throws { guard try take() == token else { throw CanvasSyntax.invalid("Expected DOT '\(token)'.") } }
  func read() throws {
    if peek.lowercased() == "strict" { strict = true; _ = try take() }
    let type = try take().lowercased(); guard ["graph", "digraph"].contains(type) else { throw CanvasSyntax.invalid("DOT requires graph or digraph.") }; directed = type == "digraph"
    if peek != "{" { builder.document.title = try take() }
    try expect("{"); _ = try statements(parent: nil); try expect("}")
    guard peek.isEmpty else { throw CanvasSyntax.invalid("Trailing DOT content.") }
  }
  private func statements(parent: String?) throws -> [String] {
    depth += 1; defer { depth -= 1 }; guard depth <= 64 else { throw CanvasSyntax.limit() }
    var members: [String] = []
    while !peek.isEmpty && peek != "}" {
      if peek == ";" || peek == "," { _ = try take(); continue }
      if ["graph", "node", "edge"].contains(peek.lowercased()), index + 1 < tokens.count, !tokens[index + 1].literal, tokens[index + 1].value == "[" {
        let kind = try take().lowercased(), attributes = try attributes()
        if kind == "node" { nodeDefaults.merge(attributes) { _, b in b } }
        else if kind == "edge" { edgeDefaults.merge(attributes) { _, b in b } }
        else { builder.document.metadata = CanvasSyntax.strings(builder.document.metadata.object.compactMapValues(\.string).merging(attributes) { _, b in b }); if let label = attributes["label"] { if let parent { try builder.node(parent, label: label) } else { builder.document.title = label } } }
        continue
      }
      if index + 1 < tokens.count, !tokens[index + 1].literal, tokens[index + 1].value == "=" { let key = try take(); _ = try take(); let value = try take(); var metadata = builder.document.metadata.object; metadata[key] = .string(value); builder.document.metadata = .object(metadata); continue }
      var from = try endpoint(parent: parent); members.append(contentsOf: from)
      if peek == "=" {
        _ = try take(); let value = try take(); var metadata = builder.document.metadata.object; metadata[from[0]] = .string(value); builder.document.metadata = .object(metadata); continue
      }
      var fromPorts = ports
      var pending: [(String, String, Bool, String?, String?)] = []
      while peek == "->" || peek == "--" {
        let arrow = try take(); guard (arrow == "->") == directed else { throw CanvasSyntax.invalid("DOT edge operator differs from graph direction.") }
        let targets = try endpoint(parent: parent); members.append(contentsOf: targets)
        for a in from { for b in targets { pending.append((a, b, arrow == "->", fromPorts[a], ports[b])); guard pending.count <= 1500 else { throw CanvasSyntax.limit() } } }
        from = targets; fromPorts = ports
      }
      let attributes = try attributes()
      if pending.isEmpty {
        for id in from { _ = try builder.node(id, label: attributes["label"], role: attributes["role"] ?? attributes["kind"] ?? (attributes["shape"] == "diamond" ? "condition" : "node"), parent: parent, details: CanvasSyntax.strings(nodeDefaults.merging(attributes) { _, b in b })) }
      } else {
        let all = edgeDefaults.merging(attributes) { _, b in b }
        for (a, b, direction, sourcePort, targetPort) in pending { var detail = all; detail["sourcePort"] = sourcePort; detail["targetPort"] = targetPort; if strict, let existing = builder.document.edges.firstIndex(where: { $0.source == a && $0.target == b || !directed && $0.source == b && $0.target == a }) {
            builder.document.edges[existing].details = .object(builder.document.edges[existing].details.object.merging(CanvasSyntax.strings(detail).object) { _, value in value })
            if let label = all["label"] { builder.document.edges[existing].label = label }
            if let role = all["role"] ?? all["kind"] { builder.document.edges[existing].role = role }
          } else { try builder.edge(a, b, label: all["label"] ?? "", role: all["role"] ?? all["kind"] ?? "relation", directed: direction, details: CanvasSyntax.strings(detail)) } }
      }
    }
    return Array(Set(members)).sorted()
  }
  private func endpoint(parent: String?) throws -> [String] {
    if peek == "subgraph" || peek == "{" {
      var name: String?
      if peek == "subgraph" { _ = try take(); if peek != "{" { name = try take() } }
      let oldNode = nodeDefaults, oldEdge = edgeDefaults
      let cluster = name?.hasPrefix("cluster") == true ? name : nil
      if let cluster { try builder.node(cluster, label: String(cluster.dropFirst("cluster".count)).trimmingCharacters(in: CharacterSet(charactersIn: "_")), role: "group", parent: parent) }
      try expect("{"); let members = try statements(parent: cluster ?? parent); try expect("}")
      nodeDefaults = oldNode; edgeDefaults = oldEdge
      for member in members { ports[member] = nil }
      return members
    }
    let literal = index < tokens.count && tokens[index].literal
    let id = try take(); guard literal || !["[", "]", "=", ";", "}", "->", "--"].contains(id) else { throw CanvasSyntax.invalid("Invalid DOT endpoint.") }
    ports[id] = nil
    if peek == ":" { _ = try take(); var port = try take(); guard ![";", "}", "[", "->", "--"].contains(port) else { throw CanvasSyntax.invalid("Invalid DOT port.") }; if peek == ":" { _ = try take(); port += ":" + (try take()) }; ports[id] = port }
    try builder.node(id, parent: parent, details: CanvasSyntax.strings(nodeDefaults)); return [id]
  }
  private func attributes() throws -> [String: String] {
    var result: [String: String] = [:]
    while peek == "[" {
      _ = try take()
      while peek != "]" {
        guard !peek.isEmpty else { throw CanvasSyntax.invalid("Unclosed DOT attributes.") }
        if peek == "," || peek == ";" { _ = try take(); continue }
        let key = try take(); try expect("="); var value = try take()
        while peek == "+" { _ = try take(); value += try take() }
        result[key] = value
      }
      _ = try take()
    }
    return result
  }
  private static func lex(_ text: String) throws -> [Token] {
    let chars = Array(text); var i = 0, result: [Token] = []
    while i < chars.count {
      let c = chars[i]
      if c.isWhitespace { i += 1; continue }
      if c == "#" || c == "/" && i + 1 < chars.count && chars[i + 1] == "/" { while i < chars.count && chars[i] != "\n" { i += 1 }; continue }
      if c == "/", i + 1 < chars.count, chars[i + 1] == "*" { i += 2; while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }; guard i + 1 < chars.count else { throw CanvasSyntax.invalid("Unclosed DOT comment.") }; i += 2; continue }
      if c == "\"" {
        i += 1; var value = "", closed = false
        while i < chars.count {
          if chars[i] == "\"" { i += 1; closed = true; break }
          if chars[i] == "\\", i + 1 < chars.count { i += 1; let escaped = chars[i]; if escaped != "\n" { value.append(escaped == "n" || escaped == "l" || escaped == "r" ? "\n" : escaped) }; i += 1 }
          else { value.append(chars[i]); i += 1 }
        }
        guard closed else { throw CanvasSyntax.invalid("Unclosed DOT string.") }; result.append(Token(value: value, literal: true))
      } else if c == "<" {
        var level = 0, value = ""
        repeat { let char = chars[i]; value.append(char); if char == "<" { level += 1 }; if char == ">" { level -= 1 }; i += 1 } while i < chars.count && level > 0
        guard level == 0 else { throw CanvasSyntax.invalid("Unclosed DOT HTML label.") }; result.append(Token(value: value, literal: true))
      } else if c == "-", i + 1 < chars.count, [">", "-"].contains(chars[i + 1]) { result.append(Token(value: String(chars[i...i + 1]))); i += 2 }
      else if "{}[];=,:+".contains(c) { result.append(Token(value: String(c))); i += 1 }
      else {
        let start = i
        while i < chars.count && !chars[i].isWhitespace && !"{}[];=,:+\"".contains(chars[i]) && !(chars[i] == "-" && i + 1 < chars.count && [">", "-"].contains(chars[i + 1])) { i += 1 }
        guard i > start else { throw CanvasSyntax.invalid("Invalid DOT token.") }; result.append(Token(value: String(chars[start..<i])))
      }
      guard result.count <= 100000 else { throw CanvasSyntax.limit() }
    }
    return result
  }
}
