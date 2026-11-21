import ArchitectureCore
import ArchitectureIR
import Foundation

public enum GraphExporter {
  public static func text(_ view: GraphView, format: String) throws -> String {
    switch format {
    case "json":
      let data = try CanonicalJSON.encode(view)
      return String(decoding: data, as: UTF8.self)
    case "mermaid":
      let ids = Dictionary(
        uniqueKeysWithValues: view.nodes.enumerated().map { ($0.element.id, "n\($0.offset)") })
      func label(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
          scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == " "
            ? String(scalar) : "#\(scalar.value);"
        }.joined()
      }
      return "flowchart LR\n"
        + view.nodes.map {
          "  \(ids[$0.id]!) [\"\(label($0.name))\"]\n  %% \(ids[$0.id]!) = \(label($0.id))"
        }.joined(separator: "\n") + "\n"
        + view.edges.map { "  \(ids[$0.source]!) -->|\(label($0.kind))| \(ids[$0.target]!)" }
        .joined(separator: "\n")
        + "\n%% snapshot: \(label(view.snapshotID)); completeness: \(label(view.completeness))\n"
    case "svg":
      let positions = Dictionary(
        uniqueKeysWithValues: view.nodes.enumerated().map {
          ($0.element.id, (24 + ($0.offset % 4) * 250, 40 + ($0.offset / 4) * 95))
        })
      let height = max(180, ((view.nodes.count + 3) / 4) * 95 + 80)
      let lines = view.edges.compactMap { edge -> String? in
        guard let (x, y) = positions[edge.source], let (a, b) = positions[edge.target] else {
          return nil
        }
        return
          "<path d=\"M\(x+110),\(y+22) L\(a+110),\(b+22)\" stroke=\"#748582\" fill=\"none\"><title>\(escape(edge.kind)) / \(escape(edge.id))</title></path>"
      }.joined()
      let nodes = view.nodes.map { node in
        let (x, y) = positions[node.id]!
        return
          "<g data-entity-id=\"\(escape(node.id))\"><title>\(escape(node.name)) / \(escape(node.anchor?.path ?? "no source anchor"))</title><rect x=\"\(x)\" y=\"\(y)\" width=\"220\" height=\"46\" rx=\"5\" fill=\"#e9f0ed\" stroke=\"#94aaa2\"/><text x=\"\(x+10)\" y=\"\(y+28)\" font-size=\"12\" font-family=\"monospace\">\(escape(String(node.name.prefix(26))))</text></g>"
      }.joined()
      return
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1030\" height=\"\(height)\" viewBox=\"0 0 1030 \(height)\" role=\"img\"><title>Saved architecture snapshot \(escape(view.snapshotID))</title><metadata>\(escape(String(decoding: try CanonicalJSON.encode(view), as: UTF8.self)))</metadata>\(lines)\(nodes)</svg>"
    case "html":
      guard let root = Bundle.module.resourceURL else { throw CocoaError(.fileReadNoSuchFile) }
      let base = [root.appendingPathComponent("Resources"), root].first {
        FileManager.default.fileExists(atPath: $0.appendingPathComponent("shell.html").path)
      }
      guard let base else { throw CocoaError(.fileReadNoSuchFile) }
      let css = try String(contentsOf: base.appendingPathComponent("explorer.css"), encoding: .utf8)
      let script = try String(
        contentsOf: base.appendingPathComponent("explorer.js"), encoding: .utf8)
      let cytoscape = try String(
        contentsOf: base.appendingPathComponent("cytoscape.min.js"), encoding: .utf8)
      let mapScripts = try ["three-c4.min.js", "c4-layout.js", "c4-objects.js", "c4-map.js"].map { name in
        let source = try String(contentsOf: base.appendingPathComponent(name), encoding: .utf8)
        return "<script>" + source + "</script>"
      }.joined()
      let canvasModel = try String(contentsOf: base.appendingPathComponent("canvas-model.js"), encoding: .utf8)
      let canvasUI = try String(contentsOf: base.appendingPathComponent("canvas-ui.js"), encoding: .utf8)
      let layout = try String(contentsOf: base.appendingPathComponent("layout-model.js"), encoding: .utf8)
      let elk = try String(contentsOf: base.appendingPathComponent("elk.bundled.js"), encoding: .utf8)
      let syntax = try String(contentsOf: base.appendingPathComponent("highlight.min.js"), encoding: .utf8)
      let external = try String(contentsOf: base.appendingPathComponent("extensions.js"), encoding: .utf8)
      let shell = try String(contentsOf: base.appendingPathComponent("shell.html"), encoding: .utf8)
      let payload = try CanonicalJSON.encode(view).base64EncodedString()
      return shell.replacingOccurrences(of: "<!--STYLE-->", with: "<style>\(css)</style>")
        .replacingOccurrences(
          of: "<!--SCRIPTS-->",
          with:
            "\(mapScripts)<script>\(cytoscape)</script><script>\(elk)</script><script>\(canvasModel)</script><script>\(canvasUI)</script><script>\(layout)</script><script>\(syntax)</script><script>window.ARCHITECTURE_SAVED='\(payload)';</script><script>\(external)</script><script>\(script)</script>"
        )
    default:
      throw ArchitectureError(
        "UNSUPPORTED_CAPABILITY", "Unknown export format: \(format)", exitCode: 3)
    }
  }
  public static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
  public static func write(_ text: String, to path: String, force: Bool) throws {
    let url = URL(fileURLWithPath: path)
    guard force || !FileManager.default.fileExists(atPath: url.path) else {
      throw ArchitectureError(
        "OUTPUT_EXISTS", "Use --force to replace the existing export.", exitCode: 2)
    }
    try Data(text.utf8).write(to: url, options: force ? [.atomic] : [.withoutOverwriting])
  }
}
