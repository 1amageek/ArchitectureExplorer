import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation

/// A session-bound client. Reconnection returns a new value and never transfers old leases.
public struct ExtensionProviderClient: ArchitectureExtensionProviding, Sendable {
  public let client: ArchitectureClient
  public let registration: ExtensionRegistration
  public let manifest: ExtensionManifest
  public static func register(workspace: String, manifest: ExtensionManifest, resumeCredential: String? = nil) async throws -> ExtensionProviderClient {
    let bootstrap = try ArchitectureClient(workspace: workspace)
    var params: [String: JSONValue] = ["manifest": try JSONValue.encode(manifest)]
    if let resumeCredential { params["resumeCredential"] = .string(resumeCredential) }
    let response = try await bootstrap.call("extensions.register", parameters: .object(params))
    let registration = try response.decode(ExtensionRegistration.self)
    guard registration.providerID == manifest.extensionID else { throw ArchitectureError("PROTOCOL_MISMATCH", "Registration changed Provider identity.", exitCode: 7) }
    return ExtensionProviderClient(client: try ArchitectureClient(workspace: workspace, extensionCredential: registration.credential), registration: registration, manifest: manifest)
  }
  public func heartbeat() async throws { _ = try await client.call("extensions.heartbeat") }
  public func disconnect() async throws { _ = try await client.call("extensions.disconnect") }
  public func inputManifest(snapshotID: String) async throws -> InputManifest {
    let result = try await client.call("inputs.manifest", parameters: .object(["snapshotID": .string(snapshotID)]))
    let manifest = try result["manifest"].decode(InputManifest.self)
    guard manifest.workspaceID == client.paths.workspaceID, manifest.snapshotID == snapshotID, try manifest.digest == result["inputManifestDigest"].string else { throw ArchitectureError("INPUT_CHANGED", "Input manifest identity/digest mismatch.", exitCode: 7) }
    return manifest
  }
  public func begin(runID: String, scope: String, contributionSetID: String, binding: ExtensionBinding, kinds: [String], viewIDs: [String] = []) async throws -> ExtensionRun {
    let value = try await client.call("runs.begin", parameters: .object(["runID": .string(runID), "scope": .string(scope), "contributionSetID": .string(contributionSetID), "binding": try JSONValue.encode(binding), "contributionKinds": try JSONValue.encode(kinds), "viewIDs": try JSONValue.encode(viewIDs)]))
    let run = try value.decode(ExtensionRun.self)
    guard run.binding == binding, run.providerID == registration.providerID, run.sessionID == registration.sessionID || run.committed else { throw ArchitectureError("PROTOCOL_MISMATCH", "Run changed the admitted identity.", exitCode: 7) }
    return run
  }
  private func parameters(_ run: ExtensionRun) -> [String: JSONValue] { ["runID": .string(run.id), "publicationID": .string(run.publicationID)] }
  public func prepare(_ run: ExtensionRun, manifest: PublicationManifest) async throws {
    var params = parameters(run); params["manifest"] = try JSONValue.encode(manifest)
    _ = try await client.call("runs.prepare", parameters: .object(params))
  }
  public func stage(_ run: ExtensionRun, contributions: [ExtensionContribution]) async throws {
    for (kind, method) in [("annotation", "annotations.replaceBatch"), ("graph", "extensionGraphs.replace"), ("view", "views.replace")] {
      let group = contributions.filter { $0.kind == kind }
      if group.isEmpty { continue }
      var params = parameters(run); params["contributions"] = try JSONValue.encode(group)
      _ = try await client.call(method, parameters: .object(params))
    }
    guard contributions.allSatisfy({ ["annotation", "graph", "view"].contains($0.kind) }) else { throw ArchitectureError("INVALID_PUBLICATION", "Unknown contribution kind.", exitCode: 2) }
  }
  public func commit(_ run: ExtensionRun, manifest: PublicationManifest, completion: String = "complete") async throws {
    var params = parameters(run); params["manifestDigest"] = .string(CanonicalJSON.digest(try CanonicalJSON.encode(manifest))); params["completion"] = .string(completion)
    _ = try await client.call("runs.commit", parameters: .object(params))
  }
  public func abort(_ run: ExtensionRun) async throws { _ = try await client.call("runs.abort", parameters: .object(parameters(run))) }
  public func nextAction() async throws -> ActionIntent? {
    let result = try await client.call("actions.next")
    guard result != .null else { return nil }
    let intent = try result.decode(ActionIntent.self)
    guard intent.registrationID == registration.id, intent.sessionID == registration.sessionID, intent.providerID == registration.providerID, intent.requestFingerprint == (try intent.verifiedFingerprint()) else { throw ArchitectureError("PROTOCOL_MISMATCH", "Action recipient/fingerprint mismatch.", exitCode: 7) }
    guard intent.binding.workspaceID == client.paths.workspaceID, let definition = manifest.actions.first(where: { $0.id == intent.actionID }), intent.effect == "externalExecution", intent.effect == definition.effect, intent.inputSchemaID == definition.inputSchemaID, intent.actionDefinitionDigest == CanonicalJSON.digest(try CanonicalJSON.encode(definition)) else { throw ArchitectureError("PROTOCOL_MISMATCH", "Action differs from the registered operation.", exitCode: 7) }
    try ExtensionRules.schema(definition.inputSchema, value: intent.arguments)
    return intent
  }
  public func receipt(for intent: ActionIntent, receipt: ActionReceipt) async throws {
    _ = try await client.call("actions.receipt", parameters: .object(["idempotencyKey": .string(intent.idempotencyKey), "requestFingerprint": .string(intent.requestFingerprint), "receipt": try JSONValue.encode(receipt)]))
  }
  public func report(requestID: String, jobID: String, runID: String, revision: Int, state: String) async throws {
    _ = try await client.call("actions.state", parameters: .object(["requestID": .string(requestID), "jobID": .string(jobID), "runID": .string(runID), "revision": .number(Double(revision)), "state": .string(state)]))
  }
  public func reconcile() async throws -> JSONValue { try await client.call("actions.reconcile") }
  /// Copy exact original bytes, verifying each file separately from the manifest digest.
  public func verifiedInputs(_ manifest: InputManifest, maximumBytes: Int = 64 * 1024 * 1024) async throws -> [String: Data] {
    let lease = try await client.acquireInputs(snapshotID: manifest.snapshotID, maximumBytes: maximumBytes)
    do {
      guard lease.workspaceID == manifest.workspaceID, lease.contextDigest == manifest.contextDigest, lease.metadata == manifest.context, lease.fileCount == manifest.files.count else { throw ArchitectureError("INPUT_CHANGED", "Lease and manifest contexts differ.", exitCode: 7) }
      var result: [String: Data] = [:]
      var total = 0
      for (path, digest) in manifest.files.sorted(by: { $0.key < $1.key }) {
        var bytes = Data(), offset = 0
        while true {
          let chunk = try await client.readInput(leaseID: lease.id, path: path, offset: offset)
          guard chunk.digest == digest, !chunk.data.isEmpty || chunk.eof, chunk.totalBytes <= maximumBytes - total else { throw ArchitectureError("INPUT_CHANGED", "Captured file digest/range/budget mismatch.", exitCode: 7) }
          bytes.append(chunk.data); offset += chunk.data.count
          if chunk.eof { break }
        }
        guard CanonicalJSON.digest(bytes) == digest else { throw ArchitectureError("INPUT_CHANGED", "Copied source digest mismatch.", exitCode: 7) }
        total += bytes.count; result[path] = bytes
      }
      guard total == lease.totalBytes, result.count == lease.fileCount else { throw ArchitectureError("INPUT_CHANGED", "Copied input totals differ from the lease.", exitCode: 7) }
      try await client.releaseInputs(leaseID: lease.id)
      return result
    } catch {
      let original = error
      do { try await client.releaseInputs(leaseID: lease.id) }
      catch { throw ArchitectureError("INPUT_RELEASE_FAILED", "Input copy failed (\(original)); lease release also failed (\(error)).", exitCode: 7) }
      throw original
    }
  }
}
