import ArchitectureCore
import Foundation

enum CanvasSVGExport {
  static func render(_ document: CanvasDocument, state: JSONValue) throws -> String {
    if let svg = document.svg { return svg }
    let boxes = state["geometry"].array
    guard !boxes.isEmpty else { throw ArchitectureError("CANVAS_NOT_RENDERED", "SVG export requires acknowledged Canvas geometry; open this session in Explorer first.", exitCode: 3) }
    let map = Dictionary(uniqueKeysWithValues: boxes.map { ($0["id"].string!, $0) }), byID = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.id, $0) })
    func number(_ value: JSONValue) -> Double { if case .number(let n) = value { return n }; return 0 }
    func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    let left = boxes.map { number($0["x"]) }.min()! - 24, top = boxes.map { number($0["y"]) }.min()! - 24
    let right = boxes.map { number($0["x"]) + number($0["width"]) }.max()! + 24, bottom = boxes.map { number($0["y"]) + number($0["height"]) }.max()! + 24
    var content = "<rect x=\"\(left)\" y=\"\(top)\" width=\"\(right-left)\" height=\"\(bottom-top)\" fill=\"#fff\"/><title>\(escape(document.title))</title><defs><marker id=\"arrow\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"6\" markerHeight=\"6\" orient=\"auto-start-reverse\"><path d=\"M0 0L10 5L0 10Z\" fill=\"#777\"/></marker></defs>"
    for (index, fragment) in document.metadata["fragments"].array.enumerated() {
      if let box = map["__fragment:" + String(index)] { content += "<rect x=\"\(number(box["x"]))\" y=\"\(number(box["y"]))\" width=\"\(number(box["width"]))\" height=\"\(number(box["height"]))\" fill=\"none\" stroke=\"#888\" stroke-dasharray=\"5 4\"/><text x=\"\(number(box["x"]) + 8)\" y=\"\(number(box["y"]) + 14)\" font-size=\"11\">\(escape((fragment["kind"].string ?? "") + " " + (fragment["label"].string ?? "")))</text>" }
    }
    for lane in document.lanes {
      if let box = map["__lane:" + lane.id] { let x = number(box["x"]), y = number(box["y"]), w = number(box["width"]), h = number(box["height"]); content += "<g data-lane-id=\"\(escape(lane.id))\"><rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"48\" fill=\"#eee\" stroke=\"#888\"/><text x=\"\(x + w / 2)\" y=\"\(y + 28)\" font-size=\"12\" text-anchor=\"middle\">\(escape(lane.label))</text><path d=\"M\(x + w / 2) \(y + 48)V\(y + h)\" stroke=\"#888\" stroke-dasharray=\"4 4\"/></g>" }
    }
    func boundary(_ box: JSONValue, toward x: Double, _ y: Double) -> (Double, Double) {
      let cx = number(box["x"]) + number(box["width"]) / 2, cy = number(box["y"]) + number(box["height"]) / 2
      let dx = x - cx, dy = y - cy, sx = dx == 0 ? Double.infinity : number(box["width"]) / (2 * abs(dx)), sy = dy == 0 ? Double.infinity : number(box["height"]) / (2 * abs(dy)), scale = min(sx, sy)
      return (cx + dx * scale, cy + dy * scale)
    }
    let collapsed = Set(state["collapsed"].array.compactMap(\.string))
    func endpoint(_ id: String) -> String {
      var current = id, parent = byID[id]?.parentID
      while let identity = parent { if collapsed.contains(identity) { current = identity }; parent = byID[identity]?.parentID }
      return current
    }
    for edge in document.edges {
      if edge.role == "contains", byID[edge.target]?.parentID == edge.source { continue }
      let source = endpoint(edge.source), target = endpoint(edge.target)
      if source == target && edge.source != edge.target { continue }
      guard let a = map[source], let b = map[target] else { continue }
      let ax = number(a["x"]) + number(a["width"]) / 2, ay = number(a["y"]) + number(a["height"]) / 2, bx = number(b["x"]) + number(b["width"]) / 2, by = number(b["y"]) + number(b["height"]) / 2
      let path: String
      if ax == bx && ay == by || edge.source == edge.target || document.kind == "sequence" && byID[edge.source]?.laneID == byID[edge.target]?.laneID {
        let x = number(a["x"]) + number(a["width"]), endX = number(b["x"]) + number(b["width"]), endY = ay == by ? by + min(24, number(b["height"]) / 3) : by
        path = "M\(x) \(ay)C\(x + 90) \(ay - 40) \(endX + 90) \(endY + 40) \(endX) \(endY)"
      } else { let start = boundary(a, toward: bx, by), end = boundary(b, toward: ax, ay); path = "M\(start.0) \(start.1)L\(end.0) \(end.1)" }
      content += "<g data-edge-id=\"\(escape(edge.id))\"><path d=\"\(path)\" fill=\"none\" stroke=\"#777\"\(edge.directed ? " marker-end=\"url(#arrow)\"" : "")/><text x=\"\((ax + bx) / 2)\" y=\"\((ay + by) / 2 - 6)\" text-anchor=\"middle\" font-size=\"11\">\(escape(edge.label))</text></g>"
    }
    for node in document.nodes {
      guard let box = map[node.id] else { continue }; let x = number(box["x"]), y = number(box["y"]), width = number(box["width"]), height = number(box["height"])
      let group = document.nodes.contains { $0.parentID == node.id }, event = document.kind == "sequence" && node.laneID != nil
      let circle = event || ["initial", "final", "pseudostate"].contains(node.role)
      let shape: String
      if circle { shape = "<ellipse cx=\"\(x + width / 2)\" cy=\"\(y + height / 2)\" rx=\"\(width / 2)\" ry=\"\(height / 2)\" fill=\"#444\"/>" }
      else if node.role == "condition" { shape = "<path d=\"M\(x + width / 2) \(y)L\(x + width) \(y + height / 2)L\(x + width / 2) \(y + height)L\(x) \(y + height / 2)Z\" fill=\"#eee\" stroke=\"#888\"/>" }
      else { shape = "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"5\" fill=\"\(group ? "none" : "#eee")\" stroke=\"#888\"/>" }
      content += "<g data-node-id=\"\(escape(node.id))\"><title>\(escape(node.label))</title>\(shape)\(circle ? "" : "<text x=\"\(x + 8)\" y=\"\(y + min(height - 3, 22))\" font-size=\"12\">\(escape(String(node.label.prefix(60))))</text>")</g>"
    }
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(left) \(top) \(right-left) \(bottom-top)\" role=\"img\">\(content)</svg>"
  }
}
