import ArchitectureCore
import Foundation

enum CanvasSVGReader {
  static func sanitize(_ root: CanvasXMLTree.Element) throws -> String {
    guard root.local == "svg" else { throw CanvasSyntax.invalid("Expected SVG root.") }
    if let namespace = root.attributes["xmlns"], namespace != "http://www.w3.org/2000/svg" { throw CanvasSyntax.invalid("Invalid SVG namespace.") }
    let allowed: Set<String> = ["svg", "g", "defs", "symbol", "use", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon", "text", "tspan", "title", "desc", "metadata", "linearGradient", "radialGradient", "stop", "clipPath", "mask", "pattern", "style", "marker"]
    func escape(_ value: String) -> String { value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    func safeStyle(_ value: String) throws {
      let lower = value.lowercased()
      guard !["@import", "expression", "javascript:", "http:", "https:", "data:", "-moz-binding", "@font-face"].contains(where: lower.contains) else { throw CanvasSyntax.unsupported("SVG external/executable styles are not imported.") }
      var remaining = value
      while let start = remaining.range(of: "url(", options: .caseInsensitive) {
        guard let end = remaining[start.upperBound...].firstIndex(of: ")") else { throw CanvasSyntax.invalid("Unclosed SVG CSS URL.") }
        let url = CanvasSyntax.clean(String(remaining[start.upperBound..<end])).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard url.hasPrefix("#"), !url.contains("\\") else { throw CanvasSyntax.unsupported("Only local SVG fragment references are supported.") }; remaining = String(remaining[remaining.index(after: end)...])
      }
      guard !value.contains("\\") else { throw CanvasSyntax.unsupported("Escaped SVG CSS is outside the static profile.") }
    }
    func render(_ element: CanvasXMLTree.Element) throws -> String {
      guard allowed.contains(element.local) else { throw CanvasSyntax.unsupported("Unsupported static SVG element: \(element.local)") }
      if element.local == "metadata" { let data = try CanonicalJSON.encode(element.literal); return "<metadata>" + escape(String(decoding: data, as: UTF8.self)) + "</metadata>" }
      if element.local == "style" { try safeStyle(element.content) }
      var attributes: [String] = element === root && root.name == "svg" && root.attributes["xmlns"] == nil ? ["xmlns=\"http://www.w3.org/2000/svg\""] : []
      for (key, value) in element.attributes.sorted(by: { $0.key < $1.key }) {
        let local = key.split(separator: ":").last?.lowercased() ?? key.lowercased()
        guard !local.hasPrefix("on"), local != "base" else { throw CanvasSyntax.unsupported("SVG event handlers are not imported.") }
        if local == "href" { guard value.hasPrefix("#") else { throw CanvasSyntax.unsupported("SVG external resources are not imported.") } }
        if !key.hasPrefix("xmlns") { try safeStyle(value) }
        attributes.append("\(key)=\"\(escape(value))\"")
      }
      let children = try element.parts.map { part in switch part { case .text(let value): return escape(value); case .element(let child): return try render(child) } }.joined()
      return "<\(element.name) \(attributes.joined(separator: " "))>\(children)</\(element.name)>"
    }
    return try render(root)
  }
}
