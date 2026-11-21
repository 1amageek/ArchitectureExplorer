import ArchitectureCore
import ArchitectureIR

extension ExtensionRuntime {
  func contributions(kind: String, snapshot: Snapshot, cursor: String?) async throws -> JSONValue {
    let page = try await visible(snapshot: snapshot, cursor: cursor)
    let items = page["publications"].array.flatMap { publication in
      publication["contributions"].array.filter { $0["kind"].string == kind }.map { contribution in
        JSONValue.object(["providerID": publication["providerID"], "runID": publication["runID"], "publicationID": publication["publicationID"], "applicability": publication["applicability"], "contribution": contribution])
      }
    }
    return .object(["items": .array(items), "snapshotID": .string(snapshot.id), "nextCursor": page["nextCursor"], "truncated": page["truncated"]])
  }
}
