import ArchitectureCore
import ArchitectureIR
import Foundation

public struct InputManifest: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let workspaceID: String
  public let snapshotID: String
  public let scope: [String]
  public let files: [String: String]
  public let context: [String: String]
  public let contextDigest: String
  public let dependencyStatus: String
  public let coverage: [Coverage]
  public init(snapshot: Snapshot, scope: [String] = ["."]) {
    schemaVersion = "1.0"; workspaceID = snapshot.workspaceID; snapshotID = snapshot.id; self.scope = scope.sorted(); files = snapshot.inputs.filter { !$0.key.hasPrefix("@") }; context = snapshot.inputs.filter { $0.key.hasPrefix("@") }; contextDigest = snapshot.contextDigest; coverage = snapshot.coverage; dependencyStatus = "unknown"
  }
  public var digest: String { get throws { CanonicalJSON.digest(try CanonicalJSON.encode(self)) } }
}
