import ArchitectureCore
import Foundation

public struct ExtensionRun: Codable, Sendable, Equatable {
  public let id: String
  public let providerID: String
  public let registrationID: String
  public let slot: String
  public let binding: ExtensionBinding
  public let generation: Int
  public let contributionKinds: [String]
  public let viewIDs: [String]
  public let publicationID: String
  public let sessionID: String
  public let expiresAt: Double
  public let committed: Bool
  public let completion: String
}
