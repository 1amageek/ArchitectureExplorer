import ArchitectureCore
import CArchitectureSyntax
import Foundation
import SwiftTreeSitter

public struct SyntaxParser: Sendable {
  public init() {}
  public func parse(_ input: SourceInput) throws -> SyntaxNode {
    let pointer: OpaquePointer?
    switch input.language {
    case "swift": pointer = tree_sitter_swift()
    case "rust": pointer = tree_sitter_rust()
    case "typescript": pointer = tree_sitter_tsx()
    default: throw ArchitectureError("UNSUPPORTED_LANGUAGE", input.language, exitCode: 3)
    }
    return try parse(input, grammar: pointer)
  }

  func parse(_ input: SourceInput, grammar pointer: OpaquePointer?) throws -> SyntaxNode {
    guard input.bytes.count <= 5 * 1024 * 1024,
      let source = String(data: input.bytes, encoding: .utf8)
    else {
      throw ArchitectureError("RESOURCE_LIMIT", "Source must be valid UTF-8 and at most 5 MiB.")
    }
    let parser = Parser()
    guard let pointer else {
      throw ArchitectureError("UNSUPPORTED_CAPABILITY", "Grammar unavailable.", exitCode: 3)
    }
    try parser.setLanguage(Language(pointer))
    parser.timeout = 2
    guard let tree = parser.parse(source), let root = tree.rootNode else {
      throw ArchitectureError("ANALYSIS_TIMEOUT", "Parser did not produce a tree.", exitCode: 6)
    }
    guard !root.hasError else {
      throw ArchitectureError(
        "SOURCE_PARSE_FAILED", "Invalid \(input.language) syntax in \(input.path).")
    }
    // The upstream String parser uses UTF-16. Map scalar boundaries once, preserving CRLF and Unicode bytes.
    var offsets = [Int](repeating: 0, count: source.utf16.count + 1)
    var unit = 0
    var byte = 0
    for scalar in source.unicodeScalars {
      offsets[unit] = byte
      let width = scalar.utf16.count
      if width == 2 { offsets[unit + 1] = byte }
      unit += width
      byte += scalar.utf8.count
      offsets[unit] = byte
    }
    var count = 0
    func capture(_ node: Node, field: String?, depth: Int) throws -> SyntaxNode {
      count += 1
      guard count <= 300_000, depth <= 512 else {
        throw ArchitectureError(
          "RESOURCE_LIMIT", "Syntax tree exceeds node or nesting budget.", exitCode: 6)
      }
      let lower = Int(node.byteRange.lowerBound) / 2
      let upper = Int(node.byteRange.upperBound) / 2
      guard lower <= upper, upper < offsets.count else {
        throw ArchitectureError("INVALID_SOURCE_RANGE", "Parser range outside immutable input.")
      }
      var children: [SyntaxNode] = []
      for index in 0..<node.childCount {
        if let child = node.child(at: index), !child.isExtra {
          children.append(
            try capture(child, field: node.fieldNameForChild(at: index), depth: depth + 1))
        }
      }
      return SyntaxNode(
        kind: node.nodeType ?? "unknown", field: field, start: offsets[lower], end: offsets[upper],
        named: node.isNamed, children: children)
    }
    return try capture(root, field: nil, depth: 0)
  }
}
