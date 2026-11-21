import ArchitectureCore
import Foundation

final class CanvasXMLTree: NSObject, XMLParserDelegate {
  final class Element {
    let name: String
    let attributes: [String: String]
    enum Part { case text(String), element(Element) }
    var parts: [Part] = []
    var children: [Element] = []
    var text = ""
    init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    var local: String { String(name.split(separator: ":").last ?? Substring(name)) }
    func attribute(_ name: String) -> String? { attributes[name] ?? attributes.first { $0.key.split(separator: ":").last == Substring(name) }?.value }
    var content: String { parts.map { part in switch part { case .text(let text): return text; case .element(let child): return child.content } }.joined() }
    func append(_ value: String) { text += value; parts.append(.text(value)) }
    func descendants(_ name: String) -> [Element] { children.flatMap { ($0.local == name ? [$0] : []) + $0.descendants(name) } }
    var literal: JSONValue { .object(["element": .string(name), "attributes": CanvasSyntax.strings(attributes), "text": .string(text), "children": .array(children.map(\.literal))]) }
  }
  private var stack: [Element] = []
  private var count = 0
  private var root: Element?
  private var failure: ArchitectureError?
  static func parse(_ text: String) throws -> Element {
    let lower = text.lowercased()
    guard !lower.contains("<!doctype"), !lower.contains("<!entity") else { throw CanvasSyntax.unsupported("XML DTDs and entities are not imported.") }
    let delegate = CanvasXMLTree(), parser = XMLParser(data: Data(text.utf8)); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
    let success = parser.parse()
    if let failure = delegate.failure { throw failure }
    guard success, let root = delegate.root else { throw CanvasSyntax.invalid("Malformed XML: \(parser.parserError?.localizedDescription ?? "missing root")") }; return root
  }
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
    count += 1
    guard count <= 20000, stack.count < 64 else { failure = CanvasSyntax.limit(); parser.abortParsing(); return }
    let element = Element(elementName, attributeDict)
    if let parent = stack.last { parent.children.append(element); parent.parts.append(.element(element)) } else if root == nil { root = element } else { failure = CanvasSyntax.invalid("Multiple XML roots."); parser.abortParsing(); return }
    stack.append(element)
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.append(string) }
  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { stack.last?.append(String(decoding: CDATABlock, as: UTF8.self)) }
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
  func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { failure = CanvasSyntax.unsupported("XML entities are not imported."); parser.abortParsing() }
  func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { failure = CanvasSyntax.unsupported("External XML resources are not imported."); parser.abortParsing(); return nil }
}
