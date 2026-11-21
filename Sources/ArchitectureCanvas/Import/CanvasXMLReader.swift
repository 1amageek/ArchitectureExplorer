import ArchitectureCore
import Foundation

enum CanvasXMLReader {
  typealias Element = CanvasXMLTree.Element
  static func read(_ text: String, format: String, into builder: CanvasBuilder) throws {
    let root = try CanvasXMLTree.parse(text)
    switch format {
    case "svg": builder.document.svg = try CanvasSVGReader.sanitize(root); builder.document.title = root.children.first { $0.local == "title" }?.content ?? builder.document.title
    case "graphml": guard root.local == "graphml" else { throw CanvasSyntax.invalid("Expected graphml root.") }; try graphML(root, into: builder)
    case "scxml": guard root.local == "scxml", root.attributes.values.contains("http://www.w3.org/2005/07/scxml") else { throw CanvasSyntax.invalid("Expected W3C SCXML namespace/root.") }; builder.document.kind = "stateTransition"; try scxml(root, parent: nil, into: builder)
    case "xmi": try CanvasXMIReader.read(root, into: builder)
    default: throw CanvasSyntax.unsupported("Unknown XML diagram profile.")
    }
  }
  private static func unique(_ id: String, into builder: CanvasBuilder) throws { guard builder.nodeIndex[id] == nil else { throw CanvasSyntax.invalid("Duplicate XML node id: \(id)") } }
  private static func graphML(_ root: Element, into builder: CanvasBuilder) throws {
    var keys: [String: Element] = [:]
    for key in root.children where key.local == "key" { guard let id = key.attributes["id"], keys[id] == nil else { throw CanvasSyntax.invalid("Duplicate/missing GraphML key identity.") }; keys[id] = key }
    func attributes(_ element: Element) -> [String: JSONValue] {
      var values: [String: JSONValue] = [:]
      for (id, key) in keys where key.attributes["for"] == nil || key.attributes["for"] == "all" || key.attributes["for"] == element.local { if let value = key.children.first(where: { $0.local == "default" }) { values[key.attributes["attr.name"] ?? id] = .string(value.content) } }
      for data in element.children where data.local == "data" { let id = data.attributes["key"] ?? "data", name = keys[id]?.attributes["attr.name"] ?? id; values[name] = .string(data.content) }
      return values
    }
    func graph(_ element: Element, parent: String?) throws {
      guard ["directed", "undirected"].contains(element.attributes["edgedefault"] ?? "") else { throw CanvasSyntax.invalid("GraphML requires an explicit edgedefault.") }
      for child in element.children {
        switch child.local {
        case "node":
          guard let id = child.attributes["id"] else { throw CanvasSyntax.invalid("GraphML node id missing.") }; try unique(id, into: builder)
          let data = attributes(child), label = child.descendants("NodeLabel").first?.content ?? data["label"]?.string ?? data["name"]?.string ?? id
          try builder.node(id, label: label, role: child.children.contains { $0.local == "graph" } ? "group" : "node", parent: parent, details: .object(data))
          for nested in child.children where nested.local == "graph" { try graph(nested, parent: id) }
        case "edge":
          guard child.attributes["sourceport"] == nil, child.attributes["targetport"] == nil else { throw CanvasSyntax.unsupported("GraphML ports require a dedicated import profile.") }
          if let directed = child.attributes["directed"], !["true", "false"].contains(directed) { throw CanvasSyntax.invalid("Invalid GraphML directed flag.") }
          guard let a = child.attributes["source"], let b = child.attributes["target"] else { throw CanvasSyntax.invalid("GraphML endpoints missing.") }
          let data = attributes(child), directed = child.attributes["directed"].map { $0 == "true" } ?? (element.attributes["edgedefault"] != "undirected")
          try builder.edge(a, b, label: child.descendants("EdgeLabel").first?.content ?? data["label"]?.string ?? "", directed: directed, details: .object(data.merging(["originalID": .string(child.attributes["id"] ?? "")]) { a, _ in a }))
        case "hyperedge", "port": throw CanvasSyntax.unsupported("GraphML hyperedges/ports require a dedicated import profile.")
        case "data", "desc": break
        default: throw CanvasSyntax.unsupported("Unsupported GraphML graph element: \(child.local)")
        }
      }
    }
    for element in root.children where element.local == "graph" { try graph(element, parent: nil) }
    if !root.descendants("port").isEmpty { throw CanvasSyntax.unsupported("GraphML ports are not supported.") }
  }
  private static func scxml(_ root: Element, parent: String?, into builder: CanvasBuilder) throws {
    let stateNames: Set<String> = ["state", "parallel", "final", "history"]
    for child in root.children where stateNames.contains(child.local) {
      guard let id = child.attributes["id"] else { throw CanvasSyntax.invalid("SCXML states require id attributes.") }; try unique(id, into: builder)
      try builder.node(id, label: child.attributes["name"] ?? id, role: child.local, parent: parent, details: child.literal)
      try scxml(child, parent: id, into: builder)
    }
    var initialTargets = root.attributes["initial"]?.split(separator: " ").map(String.init) ?? []
    for child in root.children where child.local == "initial" { for transition in child.children where transition.local == "transition" { initialTargets += transition.attributes["target"]?.split(separator: " ").map(String.init) ?? [] } }
    if initialTargets.isEmpty, ["scxml", "state"].contains(root.local), let first = root.children.first(where: { ["state", "parallel", "final"].contains($0.local) })?.attributes["id"] { initialTargets = [first] }
    if !initialTargets.isEmpty {
      let id = "__initial_" + (parent ?? "root"); try unique(id, into: builder); try builder.node(id, label: "Initial", role: "initial", parent: parent)
      for target in initialTargets { try builder.edge(id, target, role: "transition") }
    }
    for child in root.children where child.local == "transition" {
      guard let source = parent else { throw CanvasSyntax.invalid("SCXML transition must belong to a state.") }
      let targets = child.attributes["target"]?.split(separator: " ").map(String.init) ?? [source]
      let label = [child.attributes["event"], child.attributes["cond"].map { "[\($0)]" }].compactMap { $0 }.joined(separator: " ")
      for target in targets { try builder.edge(source, target, label: label, role: "transition", details: child.literal) }
    }
    builder.document.metadata = .object(["profile": .string("scxml-static-1"), "rootAttributes": CanvasSyntax.strings(root.attributes)])
  }
}
