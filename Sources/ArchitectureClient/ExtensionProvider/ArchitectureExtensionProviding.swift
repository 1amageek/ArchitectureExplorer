import ArchitectureCore
import ArchitectureExtensions

public protocol ArchitectureExtensionProviding: Sendable {
  func heartbeat() async throws
  func inputManifest(snapshotID: String) async throws -> InputManifest
  func begin(runID: String, scope: String, contributionSetID: String, binding: ExtensionBinding, kinds: [String], viewIDs: [String]) async throws -> ExtensionRun
  func prepare(_ run: ExtensionRun, manifest: PublicationManifest) async throws
  func stage(_ run: ExtensionRun, contributions: [ExtensionContribution]) async throws
  func commit(_ run: ExtensionRun, manifest: PublicationManifest, completion: String) async throws
  func nextAction() async throws -> ActionIntent?
  func receipt(for intent: ActionIntent, receipt: ActionReceipt) async throws
}
