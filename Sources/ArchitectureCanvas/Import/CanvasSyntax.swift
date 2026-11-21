import ArchitectureCore
import Foundation

enum CanvasSyntax {
  static func invalid(_ message: String) -> ArchitectureError { ArchitectureError("INVALID_CANVAS", message, exitCode: 2) }
  static func unsupported(_ message: String) -> ArchitectureError { ArchitectureError("UNSUPPORTED_SYNTAX", message, exitCode: 3) }
  static func limit() -> ArchitectureError { ArchitectureError("RESOURCE_LIMIT", "Canvas import budget exceeded.", exitCode: 6) }
  static func match(_ pattern: String, _ text: String) -> [String]? {
    // Patterns are constant host-owned grammar fragments, never supplied by the file.
    let expression: NSRegularExpression
    do { expression = try NSRegularExpression(pattern: pattern) } catch { preconditionFailure("Invalid host grammar: \(error)") }
    guard let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<result.numberOfRanges).map { index in Range(result.range(at: index), in: text).map { String(text[$0]) } ?? "" }
  }
  static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
  static func unquote(_ text: String) -> String {
    let value = clean(text)
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n") }
    return value
  }
  static func strings(_ values: [String: String]) -> JSONValue { .object(values.mapValues(JSONValue.string)) }
}
