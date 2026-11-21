import ArchitectureCore
import Foundation

public enum SourcePositions {
  public static func lspPosition(_ bytes: Data, byteOffset: Int) throws -> JSONValue {
    guard byteOffset >= 0, byteOffset <= bytes.count,
      String(data: bytes.prefix(byteOffset), encoding: .utf8) != nil
    else {
      throw ArchitectureError("INVALID_SOURCE_RANGE", "Not a UTF-8 scalar boundary.", exitCode: 2)
    }
    let prefix = bytes.prefix(byteOffset)
    let line = prefix.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
    let start = prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0
    let column = String(decoding: bytes[start..<byteOffset], as: UTF8.self).utf16.count
    return .object(["line": .number(Double(line)), "character": .number(Double(column))])
  }
  public static func byteOffset(_ bytes: Data, line: Int, utf16Column: Int) throws -> Int {
    guard line >= 0, utf16Column >= 0 else {
      throw ArchitectureError("INVALID_SOURCE_RANGE", "Invalid LSP position.", exitCode: 2)
    }
    var currentLine = 0
    var start = 0
    for index in bytes.indices where bytes[index] == 10 {
      if currentLine == line { break }
      currentLine += 1
      start = index + 1
    }
    guard currentLine == line else {
      throw ArchitectureError("INVALID_SOURCE_RANGE", "LSP line outside input.", exitCode: 2)
    }
    var end = bytes[start...].firstIndex(of: 10) ?? bytes.endIndex
    if end > start, bytes[end - 1] == 13 { end -= 1 }
    guard let text = String(data: bytes[start..<end], encoding: .utf8),
      utf16Column <= text.utf16.count
    else {
      throw ArchitectureError("INVALID_SOURCE_RANGE", "LSP column outside input.", exitCode: 2)
    }
    let units = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Column)
    guard let index = String.Index(units, within: text) else {
      throw ArchitectureError(
        "INVALID_SOURCE_RANGE", "LSP position splits a Unicode scalar.", exitCode: 2)
    }
    return start + text[..<index].utf8.count
  }
}
