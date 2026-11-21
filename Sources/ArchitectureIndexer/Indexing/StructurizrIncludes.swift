import ArchitectureCore
import ArchitectureFrontend
import Foundation

/// Expands captured local files in DSL order, preserving each original source range.
enum StructurizrIncludes {
  static let byteLimit = 512 * 1024

  static func walk(_ root: SourceInput, load: (String, Int) throws -> SourceInput,
    visit: (SourceInput, Int, Int, Substring) throws -> Void) throws {
    var visited = Set<String>()
    var remaining = byteLimit
    func expand(_ input: SourceInput, depth: Int) throws {
      guard visited.insert(input.path).inserted else {
        throw ArchitectureError("C4_DSL_INVALID", "Repeated or cyclic include: " + input.path)
      }
      guard input.bytes.count <= remaining, String(data: input.bytes, encoding: .utf8) != nil else {
        throw ArchitectureError("C4_DSL_INVALID", "Invalid UTF-8 or Map capture exceeds 512 KiB: " + input.path)
      }
      remaining -= input.bytes.count
      var offset = 0
      for (index, bytes) in input.bytes.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
        try Task.checkCancellation()
        let line = Substring(String(decoding: bytes, as: UTF8.self))
        defer { offset += bytes.count + 1 }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!include") else { try visit(input, index, offset, line); continue }
        let location = "\(input.path):\(index + 1)"
        guard let match = trimmed.wholeMatch(of: #/!include[ \t]+(?:"([^"]+)"|([^\s"]+))(?:[ \t]+(?://|#).*)?/#) else {
          throw ArchitectureError("C4_DSL_INVALID", location + ": Expected a relative DSL file.")
        }
        let raw = String(match.1 ?? match.2!)
        guard !raw.hasPrefix("/"), !raw.contains(":"), !raw.contains("\\"), raw.hasSuffix(".dsl") else {
          throw ArchitectureError("C4_DSL_INVALID", location + ": Unsupported include path " + raw)
        }
        var parts = input.path.split(separator: "/").dropLast().map(String.init)
        for part in raw.split(separator: "/") {
          if part == ".." {
            guard parts.popLast() != nil else { throw ArchitectureError("C4_DSL_INVALID", location + ": Include escapes workspace.") }
          } else if part != "." { parts.append(String(part)) }
        }
        let path = parts.joined(separator: "/")
        guard depth < 32, visited.count < 256, !visited.contains(path) else {
          throw ArchitectureError("C4_DSL_INVALID", location + ": Repeated, cyclic or over-limit include: " + path)
        }
        let child = try load(path, remaining)
        try expand(child, depth: depth + 1)
      }
    }
    try expand(root, depth: 1)
  }
}
