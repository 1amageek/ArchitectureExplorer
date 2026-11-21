import ArchitectureCore
import Foundation

enum CanvasJSONReader {
  static func read(_ text: String, into builder: CanvasBuilder) throws {
    let value: JSONValue
    do { value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    catch { throw CanvasSyntax.invalid("Invalid JSON: \(error)") }
    var pending: [(JSONValue, Int)] = [(value, 0)], visited = 0
    while let (item, depth) = pending.popLast() {
      visited += 1; guard depth <= 64, visited <= 100000 else { throw CanvasSyntax.limit() }
      if case .array(let values) = item { pending.append(contentsOf: values.map { ($0, depth + 1) }) }
      else if case .object(let fields) = item { pending.append(contentsOf: fields.values.map { ($0, depth + 1) }) }
    }
    guard case .object = value else { throw CanvasSyntax.invalid("A Canvas JSON document must be an object.") }
    if let version = value["schemaVersion"].string, !["1", "1.0"].contains(version) { throw CanvasSyntax.unsupported("Unsupported Canvas/ArchitectureIR JSON version: \(version)") }
    let nodes = value["nodes"] == .null ? value["entities"] : value["nodes"], edges = value["edges"] == .null ? value["facts"] : value["edges"]
    guard case .array = nodes, case .array = edges else { throw CanvasSyntax.invalid("JSON requires nodes/edges or ArchitectureIR entities/facts arrays.") }
    builder.document.kind = (value["kind"].string == "graph" ? "relations" : value["kind"].string) ?? (nodes.array.contains { $0["kind"].string == "basicBlock" } ? "controlFlow" : "relations")
    builder.document.title = value["title"].string ?? builder.document.title
    let architectureIR = value["schemaVersion"].string == "1.0" && value["workspaceID"].string != nil && nodes.array.allSatisfy { $0["identityKey"].string != nil && $0["entityRevision"].string != nil && $0["kind"].string != nil }
    if value["schemaVersion"].string == "1.0" && !architectureIR { throw CanvasSyntax.invalid("ArchitectureIR 1.0 requires workspace and source entity identity fields.") }
    builder.document.metadata = architectureIR ? .object(["architectureIR": value]) : value["metadata"] == .null ? .object(["origin": value]) : value["metadata"]
    if let svg = value["svg"].string { try CanvasXMLReader.read(svg, format: "svg", into: builder) }
    guard nodes.array.count <= 500, edges.array.count <= 1500 else { throw CanvasSyntax.limit() }
    for node in nodes.array {
      guard let id = node["id"].string else { throw CanvasSyntax.invalid("JSON node is missing its string id.") }
      if let raw = node["order"].int { guard raw >= 0 else { throw CanvasSyntax.invalid("Negative event order.") } }
      let order: Double?
      if case .number(let number) = node["order"] { order = number } else if node["order"] == .null { order = nil } else { throw CanvasSyntax.invalid("Event order must be numeric.") }
      builder.document.nodes.append(CanvasNode(id: id, label: node["label"].string ?? node["name"].string, role: node["role"].string ?? node["kind"].string ?? "node", language: node["language"].string, parentID: node["parentID"].string, laneID: node["laneID"].string, order: order, details: node["details"] == .null ? node : node["details"], source: node["source"] == .null ? node["anchor"] : node["source"]))
    }
    for (i, edge) in edges.array.enumerated() {
      guard let source = edge["source"].string, let target = edge["target"].string else { throw CanvasSyntax.invalid("JSON edge requires string endpoints.") }
      let order: Double?; if case .number(let number) = edge["order"] { order = number } else { order = nil }
      builder.document.edges.append(CanvasEdge(id: edge["id"].string ?? "__edge_\(i)", source: source, target: target, label: edge["label"].string ?? edge["kind"].string ?? "", role: edge["role"].string ?? edge["kind"].string ?? "relation", directed: edge["directed"].bool ?? true, order: order, details: edge["details"] == .null ? edge : edge["details"]))
    }
    for lane in value["lanes"].array { guard let id = lane["id"].string else { throw CanvasSyntax.invalid("A lane requires an id.") }; builder.document.lanes.append(CanvasLane(id: id, label: lane["label"].string)) }
    // Recorded containment can be projected as frames without changing the source graph.
    if builder.document.kind == "hierarchy" || builder.document.kind == "relations" {
      for i in builder.document.nodes.indices where builder.document.nodes[i].parentID == nil {
        let owners = builder.document.edges.filter { $0.role == "contains" && $0.target == builder.document.nodes[i].id }.map(\.source)
        if Set(owners).count == 1 { builder.document.nodes[i].parentID = owners[0] }
      }
    }
  }
}
