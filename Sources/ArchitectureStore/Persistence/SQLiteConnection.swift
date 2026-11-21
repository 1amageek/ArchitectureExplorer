import ArchitectureCore
import CSQLite
import Foundation

/// Confined to SQLiteGraphStore's actor; never transferred or exposed.
final class SQLiteConnection {
  let handle: OpaquePointer
  init(_ path: String) throws {
    var pointer: OpaquePointer?
    let result = sqlite3_open_v2(
      path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK, let pointer else {
      if let pointer { sqlite3_close(pointer) }
      throw ArchitectureError("STORE_OPEN_FAILED", "Cannot open private SQLite cache.")
    }
    handle = pointer
    sqlite3_busy_timeout(pointer, 5000)
  }
  deinit { sqlite3_close(handle) }
  func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
  }
  func error() -> ArchitectureError {
    ArchitectureError("STORE_TRANSACTION_FAILED", String(cString: sqlite3_errmsg(handle)))
  }
  func statement(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw error()
    }
    return statement
  }
  func bind(_ value: String, _ index: Int32, _ statement: OpaquePointer) throws {
    // SQLITE_TRANSIENT copies within this bounded C call; SQLite owns the copy after return.
    let result = value.withCString {
      sqlite3_bind_text(
        statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    guard result == SQLITE_OK else { throw error() }
  }
  func run(_ sql: String, _ values: [String]) throws {
    let statement = try statement(sql)
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() { try bind(value, Int32(index + 1), statement) }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
  }
  func rows(_ sql: String, _ values: [String] = []) throws -> [[String]] {
    let statement = try statement(sql)
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() { try bind(value, Int32(index + 1), statement) }
    var rows: [[String]] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw error() }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          guard let text = sqlite3_column_text(statement, column) else { return "" }
          return String(cString: text)
        })
    }
  }
}
