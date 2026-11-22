import ArchitectureCore
import ArchitectureExtensions
import Foundation

struct ExtensionState: Codable, Sendable {
  struct Grant: Codable, Sendable {
    let id: String
    let manifest: ExtensionManifest
    let binaryDigest: String
    let codeIdentity: String
    let executable: String
    let resumeCredential: String
    var permissions: [ExtensionPermission]
    var disabled = false
    var bundled: Bool?
  }
  struct Run: Codable, Sendable {
    let id: String
    let providerID: String
    let registrationID: String
    let slot: String
    let binding: ExtensionBinding
    let generation: Int
    let contributionKinds: [String]
    let viewIDs: [String]
    var publicationID: String
    var sessionID: String
    var expiresAt: Double
    var manifest: PublicationManifest?
    var contributions: [String: ExtensionContribution] = [:]
    var completion = "pending"
    var committed = false
    var manifestDigest: String?
    var providerVersion: String?
  }
  struct Dispatch: Codable, Sendable {
    let intent: ActionIntent
    var state = "queued"
    var receipt: ActionReceipt?
    var jobRevision = 0
    var runID: String?
    var lastObserved = "queued"
    var targetRequestID: String?
    var cancelRequested = false
    var observingSessionID: String?
  }
  var grants: [String: Grant] = [:]
  var runs: [String: Run] = [:]
  var heads: [String: String] = [:]
  var generations: [String: Int] = [:]
  var dispatches: [String: Dispatch] = [:]
  var revision = 0
  var originProviderID = "host"
  var causationID = ""
}
