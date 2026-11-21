import ArchitectureCore
import ArchitectureIR
import Foundation

enum SnapshotRecords {
  static func page(snapshot: Snapshot, collection: String, cursor: String?, limit: Int, maximumBytes: Int, inputs: [CapturedInputFile]) throws -> SnapshotPage {
    guard (1...500).contains(limit), (1024...2 * 1024 * 1024).contains(maximumBytes) else {
      throw ArchitectureError("RESOURCE_LIMIT", "Raw pages require 1...500 records and 1024...2097152 bytes.", exitCode: 6)
    }
    var offset = 0
    if let cursor {
      guard cursor.utf8.count <= 2048, let data = Data(base64Encoded: cursor) else { throw ArchitectureError("INVALID_CURSOR", "Invalid raw cursor.", exitCode: 2) }
      let value = try JSONDecoder().decode(JSONValue.self, from: data)
      guard value["snapshot"].string == snapshot.id, value["collection"].string == collection, let index = value["offset"].int, index >= 0 else {
        throw ArchitectureError("SNAPSHOT_EXPIRED", "Raw cursor does not match the pinned snapshot/collection.", exitCode: 7)
      }
      offset = index
    }
    func encode<T: Encodable>(_ values: [T]) throws -> SnapshotPage {
      guard offset <= values.count else { throw ArchitectureError("INVALID_CURSOR", "Raw cursor offset is outside the collection.", exitCode: 2) }
      var records: [JSONValue] = [], bytes = 512
      var end = offset
      while end < values.count && records.count < limit {
        let record = try JSONValue.encode(values[end])
        let size = try CanonicalJSON.encode(record).count + 1
        guard size <= maximumBytes - 512 else { throw ArchitectureError("RESOURCE_LIMIT", "A raw record exceeds the page byte budget.", exitCode: 6) }
        if bytes + size > maximumBytes { break }
        records.append(record); bytes += size; end += 1
      }
      let next: String?
      if end < values.count {
        next = try CanonicalJSON.encode(JSONValue.object(["snapshot": .string(snapshot.id), "collection": .string(collection), "offset": .number(Double(end))])).base64EncodedString()
      } else { next = nil }
      return SnapshotPage(workspaceID: snapshot.workspaceID, snapshotID: snapshot.id, collection: collection, records: records, total: values.count, nextCursor: next)
    }
    switch collection {
    case "entities": return try encode(snapshot.entities)
    case "facts": return try encode(snapshot.facts)
    case "evidence": return try encode(snapshot.evidence)
    case "coverage": return try encode(snapshot.coverage)
    case "diagnostics": return try encode(snapshot.diagnostics)
    case "inputs": return try encode(inputs)
    default: throw ArchitectureError("INVALID_ARGUMENT", "Unknown raw snapshot collection.", exitCode: 2)
    }
  }
}
