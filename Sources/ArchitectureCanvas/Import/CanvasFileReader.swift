import ArchitectureCore
import Foundation

public struct CanvasFileReader: CanvasFileReading {
  public init() {}
  public func read(name: String, text: String, kind: String? = nil) throws -> CanvasDocument {
    guard text.utf8.count <= 1024 * 1024, !text.contains("\0") else { throw CanvasSyntax.limit() }
    let format = URL(fileURLWithPath: name).pathExtension.lowercased()
    let builder = CanvasBuilder(name: name, text: text, format: format)
    let input = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    switch format {
    case "json": try CanvasJSONReader.read(input, into: builder)
    case "dot", "gv": try CanvasDOTReader(text: input, builder: builder).read()
    case "mmd", "mermaid": try CanvasTextReader.read(input, plant: false, into: builder)
    case "puml", "plantuml": try CanvasTextReader.read(input, plant: true, into: builder)
    case "graphml", "scxml", "xmi", "svg": try CanvasXMLReader.read(input, format: format, into: builder)
    default: throw CanvasSyntax.unsupported("Unsupported diagram extension: \(format). TLC/Lean conversion is external.")
    }
    if let kind { builder.document.kind = kind }
    try builder.document.validate()
    return builder.document
  }
}
