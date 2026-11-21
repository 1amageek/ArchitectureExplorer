import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionBinding: Codable, Sendable, Equatable {
  public let workspaceID: String
  public let snapshotID: String
  public let inputManifestDigest: String
  public let entityIDs: [String]
  public let factIDs: [String]
  public init(workspaceID: String, snapshotID: String, inputManifestDigest: String, entityIDs: [String] = [], factIDs: [String] = []) {
    self.workspaceID = workspaceID; self.snapshotID = snapshotID; self.inputManifestDigest = inputManifestDigest; self.entityIDs = entityIDs.sorted(); self.factIDs = factIDs.sorted()
  }
}
