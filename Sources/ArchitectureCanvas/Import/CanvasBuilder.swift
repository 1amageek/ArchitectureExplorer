import ArchitectureCore
import Foundation

final class CanvasBuilder {
  var document: CanvasDocument
  var nodeIndex: [String: Int] = [:]
  var edgeIndex = 0
  init(name: String, text: String, format: String, kind: String = "relations") {
    document = CanvasDocument(kind: kind, title: URL(fileURLWithPath: name).lastPathComponent, format: format, sourceName: name, sourceDigest: CanonicalJSON.digest(text))
  }
  @discardableResult func node(_ id: String, label: String? = nil, role: String = "node", parent: String? = nil, details: JSONValue = .object([:])) throws -> String {
    guard !id.isEmpty else { throw CanvasSyntax.invalid("An element identity is empty.") }
    if let i = nodeIndex[id] {
      if let label { document.nodes[i].label = label }
      if role != "node" { document.nodes[i].role = role }
      if let parent { document.nodes[i].parentID = parent }
      document.nodes[i].details = .object(document.nodes[i].details.object.merging(details.object) { _, b in b })
    } else {
      guard document.nodes.count < 500 else { throw CanvasSyntax.limit() }
      nodeIndex[id] = document.nodes.count; document.nodes.append(CanvasNode(id: id, label: label, role: role, parentID: parent, details: details))
    }
    return id
  }
  func edge(_ source: String, _ target: String, label: String = "", role: String = "relation", directed: Bool = true, order: Double? = nil, details: JSONValue = .object([:])) throws {
    guard document.edges.count < 1500 else { throw CanvasSyntax.limit() }
    var id: String
    repeat { edgeIndex += 1; id = "__edge_\(edgeIndex)" } while nodeIndex[id] != nil || document.edges.contains(where: { $0.id == id })
    document.edges.append(CanvasEdge(id: id, source: source, target: target, label: label, role: role, directed: directed, order: order, details: details))
  }
  func lane(_ id: String, label: String? = nil) throws {
    if let index = document.lanes.firstIndex(where: { $0.id == id }) { if let label { document.lanes[index].label = label }; return }
    guard document.lanes.count < 128 else { throw CanvasSyntax.limit() }; document.lanes.append(CanvasLane(id: id, label: label))
  }
  func message(_ from: String, _ to: String, label: String, role: String = "message") throws {
    try lane(from); try lane(to)
    let order = Double(document.edges.count)
    let a = "__event_\(document.edges.count)_send", b = "__event_\(document.edges.count)_receive"
    document.nodes.append(CanvasNode(id: a, label: label, role: "send", laneID: from, order: order))
    document.nodes.append(CanvasNode(id: b, label: label, role: "receive", laneID: to, order: order))
    try edge(a, b, label: label, role: role, order: order)
  }
}
