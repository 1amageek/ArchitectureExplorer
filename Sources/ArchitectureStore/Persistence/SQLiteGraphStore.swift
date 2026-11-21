import ArchitectureCore
import ArchitectureIR
import Foundation

public actor SQLiteGraphStore: GraphStore {
  private let db: SQLiteConnection
  private let workspaceID: String
  private let retention: Int
  private var cachedLatest: Snapshot?
  public init(path: String, workspaceID: String, retention: Int = 16) throws {
    guard retention >= 2, retention <= 128 else {
      throw ArchitectureError(
        "INVALID_CONFIGURATION", "Snapshot retention must be 2...128.", exitCode: 2)
    }
    db = try SQLiteConnection(path)
    self.workspaceID = workspaceID
    self.retention = retention
    let metadata = try db.rows("SELECT name FROM sqlite_master WHERE type='table' AND name='metadata'")
    if !metadata.isEmpty {
      let version = try db.rows("SELECT value FROM metadata WHERE key='schema'")
      guard version == [["2.0"]] else { throw ArchitectureError("SCHEMA_MISMATCH", "Development cache format changed; archive this cache and rebuild it explicitly.", exitCode: 7) }
    }
    try db.execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;")
    try db.execute(
      "CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL); CREATE TABLE IF NOT EXISTS snapshots(id TEXT PRIMARY KEY, generation INTEGER NOT NULL, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS identities(key TEXT PRIMARY KEY, id TEXT NOT NULL); CREATE TABLE IF NOT EXISTS extension_state(id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL);"
    )
    try db.execute(
      "CREATE TABLE IF NOT EXISTS imported_snapshots(id TEXT PRIMARY KEY REFERENCES snapshots(id) ON DELETE CASCADE);"
    )
    for name in ["entities", "facts", "evidence", "coverage", "diagnostics"] {
      try db.execute(
        "CREATE TABLE IF NOT EXISTS \(name)(snapshot TEXT NOT NULL REFERENCES snapshots(id) ON DELETE CASCADE, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(snapshot,id));"
      )
    }
    let owner = try db.rows("SELECT value FROM metadata WHERE key='workspace'")
    guard owner.isEmpty || owner[0][0] == workspaceID else {
      throw ArchitectureError("INVALID_GRAPH", "Cache belongs to another workspace.", exitCode: 7)
    }
    try db.run("INSERT OR IGNORE INTO metadata VALUES('workspace',?)", [workspaceID])
    let check = try db.rows("PRAGMA quick_check")
    guard check == [["ok"]] else {
      throw ArchitectureError(
        "STORE_CORRUPT", "SQLite integrity check failed; preserve cache before rebuilding.",
        exitCode: 7)
    }
    try db.run("INSERT OR IGNORE INTO metadata VALUES('schema','2.0')", [])
  }
  public func latest() throws -> Snapshot? {
    if let cachedLatest { return cachedLatest }
    let rows = try db.rows(
      "SELECT payload FROM snapshots WHERE id NOT IN (SELECT id FROM imported_snapshots) ORDER BY generation DESC LIMIT 1"
    )
    guard let payload = rows.first?.first else { return nil }
    let snapshot = try decodeSnapshot(payload)
    cachedLatest = snapshot
    return snapshot
  }
  public func load(_ id: String) throws -> Snapshot {
    let rows = try db.rows("SELECT payload FROM snapshots WHERE id=?", [id])
    guard let payload = rows.first?.first else {
      throw ArchitectureError(
        "SNAPSHOT_EXPIRED", "Snapshot is no longer retained: \(id)", exitCode: 7)
    }
    return try decodeSnapshot(payload)
  }
  private func decodeSnapshot(_ text: String) throws -> Snapshot {
    let value = try JSONDecoder().decode(Snapshot.self, from: Data(text.utf8))
    guard value.workspaceID == workspaceID else {
      throw ArchitectureError("INVALID_GRAPH", "Cross-workspace cache data.", exitCode: 7)
    }
    try GraphValidation.validate(value)
    return value
  }
  public func publish(_ snapshot: Snapshot) throws {
    try persist(snapshot, imported: false)
  }
  public func importSnapshot(_ snapshot: Snapshot) throws {
    try persist(snapshot, imported: true)
  }
  private func persist(_ snapshot: Snapshot, imported: Bool) throws {
    guard snapshot.workspaceID == workspaceID else {
      throw ArchitectureError("INVALID_GRAPH", "Cross-workspace publication.", exitCode: 7)
    }
    try GraphValidation.validate(snapshot)
    let data = try CanonicalJSON.encode(snapshot)
    guard data.count <= 128 * 1024 * 1024 else {
      throw ArchitectureError(
        "RESOURCE_LIMIT", "Snapshot exceeds 128 MiB cache transaction budget.", exitCode: 6)
    }
    if !imported {
      let current = try latest()
      guard current == nil || snapshot.generation > current!.generation else {
        throw ArchitectureError(
          "INPUT_CHANGED_DURING_ANALYSIS",
          "An older generation cannot replace the current snapshot.",
          exitCode: 7)
      }
    }
    try db.execute("BEGIN IMMEDIATE")
    do {
      try db.run(
        "INSERT INTO snapshots VALUES(?,?,?)",
        [snapshot.id, String(snapshot.generation), String(decoding: data, as: UTF8.self)])
      if imported {
        try db.run("INSERT INTO imported_snapshots VALUES(?)", [snapshot.id])
      }
      let payload = String(decoding: data, as: UTF8.self)
      let conflicts = try db.rows(
        "SELECT count(*) FROM identities i JOIN json_each(?, '$.entities') e ON i.key=json_extract(e.value, '$.identityKey') WHERE i.id<>json_extract(e.value, '$.id')",
        [payload])
      guard conflicts.first?.first == "0" else {
        throw ArchitectureError("INVALID_GRAPH", "Identity registry conflict.", exitCode: 7)
      }
      try db.run(
        "INSERT OR IGNORE INTO identities SELECT json_extract(value,'$.identityKey'),json_extract(value,'$.id') FROM json_each(?,'$.entities')",
        [payload])
      // Reuse the already serialized immutable snapshot. SQLite JSON1 builds normalized indices
      // inside the same transaction without re-encoding every Swift transfer value.
      for table in ["entities", "facts", "evidence"] {
        try db.run(
          "INSERT INTO \(table) SELECT ?,json_extract(value,'$.id'),value FROM json_each(?,'$.\(table)')",
          [snapshot.id, payload])
      }
      for table in ["coverage", "diagnostics"] {
        try db.run(
          "INSERT INTO \(table) SELECT ?,CAST(key AS TEXT),value FROM json_each(?,'$.\(table)')",
          [snapshot.id, payload])
      }
      try db.execute(
        "DELETE FROM snapshots WHERE id NOT IN (SELECT id FROM imported_snapshots) AND id NOT IN (SELECT id FROM snapshots WHERE id NOT IN (SELECT id FROM imported_snapshots) ORDER BY generation DESC LIMIT \(retention))"
      )
      try db.execute(
        "DELETE FROM snapshots WHERE id IN (SELECT id FROM imported_snapshots) AND rowid NOT IN (SELECT s.rowid FROM snapshots s JOIN imported_snapshots i ON s.id=i.id ORDER BY s.rowid DESC LIMIT \(retention))"
      )
      try db.execute("COMMIT")
      if !imported { cachedLatest = snapshot }
    } catch {
      do { try db.execute("ROLLBACK") } catch let rollbackError {
        throw ArchitectureError(
          "STORE_ROLLBACK_FAILED", "\(error); rollback: \(rollbackError)", exitCode: 7)
      }
      throw error
    }
  }
  public func history() throws -> [String] {
    try db.rows(
      "SELECT id FROM snapshots WHERE id NOT IN (SELECT id FROM imported_snapshots) ORDER BY generation DESC"
    ).map { $0[0] }
  }
  public func extensionState() throws -> JSONValue {
    let value = try db.rows("SELECT payload FROM extension_state WHERE id=1")
    guard let text = value.first?.first else { return .object([:]) }
    return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }
  public func replaceExtensionState(_ state: JSONValue) throws {
    let bytes = try CanonicalJSON.encode(state)
    guard bytes.count <= 16 * 1024 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Extension durable state exceeds 16 MiB.", exitCode: 6) }
    try db.run("INSERT INTO extension_state VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [String(decoding: bytes, as: UTF8.self)])
  }
}
