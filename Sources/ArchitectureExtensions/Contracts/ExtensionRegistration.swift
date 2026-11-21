import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionRegistration: Codable, Sendable, Equatable {
  public let id: String
  public let providerID: String
  public let sessionID: String
  public let credential: String
  public let resumeCredential: String
  public let grantedPermissions: [ExtensionPermission]
  public let expiresAt: Double
  public let limits: [String: Int]
  public init(id: String, providerID: String, sessionID: String, credential: String, resumeCredential: String, grantedPermissions: [ExtensionPermission], expiresAt: Double) {
    self.id = id; self.providerID = providerID; self.sessionID = sessionID; self.credential = credential; self.resumeCredential = resumeCredential; self.grantedPermissions = grantedPermissions; self.expiresAt = expiresAt
    self.limits = ["requestsPerSecond": 64, "dispatchRecords": 512, "dispatchRetentionSeconds": 3600, "runRecords": 128, "publicationBytes": 2 * 1024 * 1024]
  }
}
