import Foundation
import SwiftHTML

public enum ExplorerPage {
  public static func asset(_ name: String) throws -> String {
    let allowed: Set<String> = [
      "three-c4.min.js", "c4-layout.js", "c4-objects.js", "c4-map.js", "canvas-model.js", "canvas-ui.js", "shell.html", "explorer.css", "explorer.js", "extensions.js", "layout-worker.js", "layout-model.js", "cytoscape.min.js",
      "elk.bundled.js", "elk-worker.min.js", "highlight.min.js",
    ]
    guard allowed.contains(name), let root = Bundle.module.resourceURL else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return try String(
      contentsOf: root.appendingPathComponent("Assets").appendingPathComponent(name),
      encoding: .utf8)
  }
  public static func render(repositoryMode: Bool = false) throws -> String {
    let template = try asset("shell.html")
    let head = (repositoryMode ? #"<meta name="repository-map" content="1">"# : "") + template.components(separatedBy: "<head>")[1].components(separatedBy: "</head>")[0]
    let body = template.components(separatedBy: "<body>")[1].components(separatedBy: "</body>")[0]
    return ExplorerDocument(headSource: head, bodySource: body).render()
      .replacingOccurrences(
        of: "<!--STYLE-->", with: "<link rel=\"stylesheet\" href=\"/assets/explorer.css\">"
      )
      .replacingOccurrences(
        of: "<!--SCRIPTS-->",
        with:
          "<script src=\"/assets/three-c4.min.js\" defer></script><script src=\"/assets/c4-layout.js\" defer></script><script src=\"/assets/c4-objects.js\" defer></script><script src=\"/assets/c4-map.js\" defer></script><script src=\"/assets/cytoscape.min.js\" defer></script><script src=\"/assets/canvas-model.js\" defer></script><script src=\"/assets/canvas-ui.js\" defer></script><script src=\"/assets/layout-model.js\" defer></script><script src=\"/assets/highlight.min.js\" defer></script><script src=\"/assets/extensions.js\" defer></script><script src=\"/assets/explorer.js\" defer></script>"
      )
  }
}

private struct ExplorerDocument: HTMLDocument {
  let headSource: String
  let bodySource: String
  var head: some Component { rawHTML(headSource) }
  var body: some Component { rawHTML(bodySource) }
}
