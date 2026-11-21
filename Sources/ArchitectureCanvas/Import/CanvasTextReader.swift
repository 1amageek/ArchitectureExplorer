import ArchitectureCore
import Foundation

enum CanvasTextReader {
  static func read(_ text: String, plant: Bool, into builder: CanvasBuilder) throws {
    var lines = text.components(separatedBy: .newlines).flatMap(statements).map(CanvasSyntax.clean)
    if plant {
      guard lines.first(where: { !$0.isEmpty })?.hasPrefix("@startuml") == true, lines.last(where: { !$0.isEmpty }) == "@enduml" else { throw CanvasSyntax.invalid("PlantUML requires @startuml and @enduml.") }
      lines.removeAll { $0.hasPrefix("@startuml") || $0 == "@enduml" }
    } else {
      lines.removeAll { $0.hasPrefix("%%") || $0.isEmpty }
      guard let header = lines.first else { throw CanvasSyntax.invalid("Empty Mermaid document.") }
      if header.hasPrefix("sequenceDiagram") { builder.document.kind = "sequence" }
      else if header.hasPrefix("stateDiagram") { builder.document.kind = "stateTransition" }
      else if header.hasPrefix("flowchart") || header.hasPrefix("graph ") { builder.document.kind = "relations"; if let direction = header.split(separator: " ").last, ["LR", "RL", "TB", "TD", "BT"].contains(String(direction)) { builder.document.metadata = .object(["rankdir": .string(String(direction))]) } }
      else { throw CanvasSyntax.unsupported("Supported Mermaid families: flowchart, graph, stateDiagram, sequenceDiagram.") }
      lines.removeFirst()
    }
    if plant {
      if lines.contains(where: { CanvasSyntax.match("^(participant|actor|boundary|control|entity|database|collections|queue)\\b", $0) != nil }) { builder.document.kind = "sequence" }
      else if lines.contains(where: { $0.hasPrefix("state ") || $0.contains("[*]") }) { builder.document.kind = "stateTransition" }
    }
    if builder.document.kind == "sequence" { try sequence(lines, plant: plant, into: builder); return }
    var stack: [String] = [], classOwner: String?, serial = 0
    for raw in lines {
      var line = CanvasSyntax.clean(raw)
      if line.isEmpty || line.hasPrefix("%%") || plant && line.hasPrefix("'") { continue }
      if line.hasPrefix("!") || line.hasPrefix("%%{") || line.hasPrefix("click ") || line.hasPrefix("link ") { throw CanvasSyntax.unsupported("Executable/include/link directives are not imported.") }
      if let owner = classOwner {
        if line == "}" { classOwner = nil; continue }
        guard let i = builder.nodeIndex[owner] else { throw CanvasSyntax.invalid("Class member owner is missing.") }
        var data = builder.document.nodes[i].details.object; data["members"] = .array(data["members", default: .array([])].array + [.string(line)]); builder.document.nodes[i].details = .object(data); continue
      }
      if line.hasPrefix("title ") { builder.document.title = String(line.dropFirst(6)); continue }
      if line.hasPrefix("direction ") || line.hasPrefix("left to right direction") { var data = builder.document.metadata.object; data["direction"] = .string(line); builder.document.metadata = .object(data); continue }
      if line.hasPrefix("classDef ") || line.hasPrefix("style ") || line.hasPrefix("skinparam ") || line.hasPrefix("hide ") || line.hasPrefix("show ") {
        var data = builder.document.metadata.object; data["presentationDirectives"] = .array(data["presentationDirectives", default: .array([])].array + [.string(line)]); builder.document.metadata = .object(data); continue
      }
      if line == "end" || line == "}" { guard !stack.isEmpty else { throw CanvasSyntax.invalid("Unmatched diagram group end.") }; stack.removeLast(); continue }
      if line.hasPrefix("subgraph ") {
        line = CanvasSyntax.clean(String(line.dropFirst(9))); let (id, label, _, _) = try endpoint(line)
        try builder.node(id, label: label ?? id, role: "group", parent: stack.last); stack.append(id); guard stack.count < 64 else { throw CanvasSyntax.limit() }; continue
      }
      if builder.document.kind == "stateTransition", let alias = CanvasSyntax.match("^state +([\\w.$-]+) *: *(.*)$", line) { try builder.node(alias[1], label: alias[2], role: "state", parent: stack.last); continue }
      if let declaration = CanvasSyntax.match("^(abstract +class|class|interface|enum|package|state) +(.+)$", line) {
        let role = declaration[1] == "abstract class" ? "class" : declaration[1]
        var content = declaration[2], body = "", opens = false
        if let brace = content.firstIndex(of: "{") { body = CanvasSyntax.clean(String(content[content.index(after: brace)...])); content = CanvasSyntax.clean(String(content[..<brace])); opens = true }
        var id: String, label: String
        if let alias = CanvasSyntax.match("^\"(.*)\" +as +([\\w.$-]+)$", content) { id = alias[2]; label = alias[1] }
        else if let alias = CanvasSyntax.match("^([\\w.$-]+) +as +\"(.*)\"$", content) { id = alias[1]; label = alias[2] }
        else { id = CanvasSyntax.unquote(content); label = id }
        guard !id.isEmpty, !id.contains(" ") || content.hasPrefix("\"") else { throw CanvasSyntax.unsupported("Unsupported declaration: \(line)") }
        try builder.node(id, label: label, role: role, parent: stack.last)
        if opens {
          if ["class", "interface", "enum"].contains(role) {
            if body.hasSuffix("}") { let members = CanvasSyntax.clean(String(body.dropLast())); if !members.isEmpty, let i = builder.nodeIndex[id] { builder.document.nodes[i].details = .object(["members": .array(members.components(separatedBy: ";").map(JSONValue.string))]) } }
            else { classOwner = id }
          } else { stack.append(id) }
        }
        continue
      }
      try flow(line, parent: stack.last, state: builder.document.kind == "stateTransition", serial: &serial, into: builder)
    }
    guard stack.isEmpty, classOwner == nil else { throw CanvasSyntax.invalid("Unclosed diagram group/class.") }
  }
  private static func statements(_ line: String) -> [String] {
    var parts: [String] = [], current = "", quoted = false, escaped = false, depth = 0
    for char in line {
      if char == "\\" && !escaped { escaped = true; current.append(char); continue }
      if char == "\"" && !escaped { quoted.toggle() }
      if !quoted { if "[({".contains(char) { depth += 1 }; if "])}".contains(char) { depth -= 1 } }
      if char == ";" && !quoted && depth == 0 { parts.append(current); current = "" } else { current.append(char) }
      escaped = false
    }
    parts.append(current); return parts
  }
  private static func endpoint(_ input: String) throws -> (String, String?, String, String?) {
    guard let match = CanvasSyntax.match(#"^ *(\[\*\]|[\p{L}\p{N}_.$-]+?)(?=-->|==>|-\.->|--|->|\.\.[|>]|<\||[\[({\s:]|$)(.*)$"#, input) else { throw CanvasSyntax.unsupported("Unsupported node syntax: \(input)") }
    var rest = CanvasSyntax.clean(match[2]), label: String?, shape: String?
    if let first = rest.first, "[({".contains(first) {
      shape = first == "{" ? "condition" : "node"
      let closing: Character = first == "[" ? "]" : first == "(" ? ")" : "}"
      var depth = 0, quoted = false, end: String.Index?
      for i in rest.indices { let char = rest[i]; if char == "\"" { quoted.toggle() }; if !quoted { if char == first { depth += 1 }; if char == closing { depth -= 1; if depth == 0 { end = i; break } } } }
      guard let end else { throw CanvasSyntax.invalid("Unclosed node label.") }
      var value = String(rest[rest.index(after: rest.startIndex)..<end]); while let a = value.first, let b = value.last, (a == "[" && b == "]") || (a == "(" && b == ")") { value = String(value.dropFirst().dropLast()) }
      label = CanvasSyntax.unquote(value); rest = CanvasSyntax.clean(String(rest[rest.index(after: end)...]))
    }
    return (match[1], label, rest, shape)
  }
  private static func flow(_ input: String, parent: String?, state: Bool, serial: inout Int, into builder: CanvasBuilder) throws {
    var (id, label, rest, shape) = try endpoint(input)
    func resolve(_ raw: String, target: Bool, shape: String? = nil) throws -> String {
      if raw == "[*]" { serial += 1; let id = "__\(target ? "final" : "initial")_\(serial)"; try builder.node(id, label: target ? "Final" : "Initial", role: target ? "final" : "initial", parent: parent); return id }
      try builder.node(raw, role: state ? "state" : shape ?? "node", parent: parent); return raw
    }
    id = try resolve(id, target: false, shape: shape); if let label { try builder.node(id, label: label) }
    while !rest.isEmpty {
      if rest == ";" { return }
      guard let arrow = CanvasSyntax.match("^(<\\|--|<\\|\\.\\.|--\\|>|\\.\\.\\|>|\\*--|o--|-->|==>|-\\.->|-->?>?|--|->|\\.\\.>) *(.*)$", rest) else {
        if rest.hasPrefix(":::"), !rest.contains(" ") { return }
        if rest.hasPrefix(":"), state { if let i = builder.nodeIndex[id] { builder.document.nodes[i].details = .object(["description": .string(CanvasSyntax.clean(String(rest.dropFirst())))]) }; return }
        throw CanvasSyntax.unsupported("Unsupported connection syntax: \(rest)")
      }
      rest = arrow[2]; var edgeLabel = ""
      if rest.hasPrefix("|") { guard let end = rest.dropFirst().firstIndex(of: "|") else { throw CanvasSyntax.invalid("Unclosed edge label.") }; edgeLabel = String(rest[rest.index(after: rest.startIndex)..<end]); rest = CanvasSyntax.clean(String(rest[rest.index(after: end)...])) }
      let next = try endpoint(rest), target = try resolve(next.0, target: true, shape: next.3); if let label = next.1 { try builder.node(target, label: label) }; rest = next.2
      if rest.hasPrefix(":" ) { edgeLabel = CanvasSyntax.clean(String(rest.dropFirst())); rest = "" }
      let reverse = arrow[1].hasPrefix("<"), role = state ? "transition" : arrow[1].contains("|") ? "inheritance" : "relation"
      try builder.edge(reverse ? target : id, reverse ? id : target, label: edgeLabel, role: role, directed: arrow[1] != "--", details: .object(["syntax": .string(arrow[1])]))
      id = target
    }
  }
  private static func sequence(_ lines: [String], plant: Bool, into builder: CanvasBuilder) throws {
    var stack: [[String: JSONValue]] = [], fragments: [JSONValue] = [], order = 0
    for line in lines {
      if line.isEmpty || line.hasPrefix("%%") || plant && line.hasPrefix("'") || line == "autonumber" { continue }
      if line.hasPrefix("!") || line.hasPrefix("%%{") || line.hasPrefix("link ") { throw CanvasSyntax.unsupported("Executable/include directives are not imported.") }
      if let p = CanvasSyntax.match("^(participant|actor|boundary|control|entity|database|collections|queue) +(.+)$", line) {
        if let alias = CanvasSyntax.match("^\"(.*)\" +as +([\\w.$-]+)$", p[2]) { try builder.lane(alias[2], label: alias[1]) }
        else if let alias = CanvasSyntax.match("^([\\w.$-]+) +as +(.+)$", p[2]) { try builder.lane(alias[1], label: CanvasSyntax.unquote(alias[2])) }
        else { try builder.lane(CanvasSyntax.unquote(p[2])) }; continue
      }
      if let message = CanvasSyntax.match("^([\\w.$-]+?) *(-{1,2}(?:>>|>|\\)|x)|\\.\\.>) *([\\w.$-]+) *: *(.*)$", line) {
        try builder.message(message[1], message[3], label: message[4], role: message[2].contains(")") ? "asyncMessage" : message[2].hasPrefix("--") ? "reply" : "message")
        for i in (builder.document.nodes.count - 2)..<builder.document.nodes.count { builder.document.nodes[i].order = Double(order) }; builder.document.edges[builder.document.edges.count - 1].order = Double(order); order += 1; continue
      }
      if let note = CanvasSyntax.match("^(?:[Nn]ote) +(?:right of|left of|over) +([\\w.$-]+)(?:,[\\w.$-]+)? *: *(.*)$", line) { try builder.lane(note[1]); builder.document.nodes.append(CanvasNode(id: "__note_\(order)", label: note[2], role: "note", laneID: note[1], order: Double(order))); order += 1; continue }
      if let fragment = CanvasSyntax.match("^(loop|alt|opt|par|critical|break|rect|group) *(.*)$", line) { stack.append(["kind": .string(fragment[1]), "label": .string(fragment[2]), "start": .number(Double(order))]); guard stack.count <= 64 else { throw CanvasSyntax.limit() }; continue }
      if line == "end" { guard var fragment = stack.popLast() else { throw CanvasSyntax.invalid("Unmatched sequence fragment end.") }; fragment["end"] = .number(Double(order)); fragments.append(.object(fragment)); continue }
      if line.hasPrefix("else") || line.hasPrefix("and ") { guard !stack.isEmpty else { throw CanvasSyntax.invalid("Sequence branch has no fragment.") }; fragments.append(.object(["kind": .string("branch"), "label": .string(line), "start": .number(Double(order)), "end": .number(Double(order))])); continue }
      if line.hasPrefix("activate ") || line.hasPrefix("deactivate ") || line.hasPrefix("destroy ") { fragments.append(.object(["kind": .string("activation"), "label": .string(line), "start": .number(Double(order)), "end": .number(Double(order))])); continue }
      if line.hasPrefix("title ") { builder.document.title = String(line.dropFirst(6)); continue }
      throw CanvasSyntax.unsupported("Unsupported sequence syntax: \(line)")
    }
    guard stack.isEmpty else { throw CanvasSyntax.invalid("Unclosed sequence fragment.") }; builder.document.metadata = .object(["fragments": .array(fragments)])
  }
}
