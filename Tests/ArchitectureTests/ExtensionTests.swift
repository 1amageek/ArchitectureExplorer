@testable import ArchitectureCore
import ArchitectureClient
import ArchitectureExtensions
import ArchitectureIR
import ArchitectureStore
@testable import ArchitectureService
import Foundation
import Darwin
import Synchronization
import Testing

struct ExtensionTests {
  final class Clock: Sendable {
    let value = Mutex(1_800_000_000.0)
    func now() -> Double { value.withLock { $0 } }
    func advance(_ seconds: Double) { value.withLock { $0 += seconds } }
  }
  struct Fixture {
    let root: URL
    let store: SQLiteGraphStore
    let runtime: ExtensionRuntime
    let snapshot: Snapshot
    let clock: Clock
    let peer = ConnectionPeer(processID: 100, auditIdentity: "peer-a", executable: "/provider-a", codeIdentity: "code-a", binaryDigest: "binary-a")
    init(bundledProvider: BundledProvider? = nil) throws {
      root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      store = try SQLiteGraphStore(path: root.appendingPathComponent("state.sqlite").path, workspaceID: "workspace")
      clock = Clock()
      let clock = clock
      runtime = ExtensionRuntime(workspaceID: "workspace", store: store, hostDigests: [],
                                 bundledProvider: bundledProvider, now: { clock.now() })
      snapshot = Snapshot(id: "snapshot", workspaceID: "workspace", generation: 1, contextDigest: "context", inputs: ["A.swift": CanonicalJSON.digest("func a() {}")], entities: [Entity(id: "a", kind: "function", language: "swift", name: "a", identityKey: "a", entityRevision: "1")], facts: [], evidence: [], coverage: [])
    }
    func cleanup() async throws { await runtime.shutdown(); try FileManager.default.removeItem(at: root) }
    func binding() throws -> ExtensionBinding { ExtensionBinding(workspaceID: "workspace", snapshotID: "snapshot", inputManifestDigest: try InputManifest(snapshot: snapshot).digest, entityIDs: ["a"]) }
    func manifest(id: String = "test.provider") -> ExtensionManifest {
      let empty: JSONValue = .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)])
      let cancel: JSONValue = .object(["type": .string("object"), "properties": .object(Dictionary(uniqueKeysWithValues: ["requestID", "jobID", "runID"].map { ($0, JSONValue.object(["type": .string("string")])) })), "required": .array(["requestID", "jobID", "runID"].map(JSONValue.string)), "additionalProperties": .bool(false)])
      return ExtensionManifest(extensionID: id, displayName: "Test Provider", requestedPermissions: ExtensionPermission.allCases, views: [ExtensionViewDefinition(id: "results", kind: "table", title: "Results")], actions: [ExtensionActionDefinition(id: "check", title: "Check", requiresConfirmation: false, inputSchemaID: "check.v1", inputSchema: empty), ExtensionActionDefinition(id: "cancel", title: "Cancel", operation: "cancel", inputSchemaID: "cancel.v1", inputSchema: cancel)])
    }
    func register(_ manifest: ExtensionManifest? = nil, permissions: [ExtensionPermission]? = nil, peer other: ConnectionPeer? = nil) async throws -> ExtensionRegistration {
      let manifest = manifest ?? self.manifest(), peer = other ?? self.peer
      let params: JSONValue = .object(["manifest": try JSONValue.encode(manifest)])
      do { _ = try await runtime.registry("extensions.register", params: params, peer: peer, credential: nil); Issue.record("Registration skipped approval") }
      catch let error as ArchitectureError { #expect(error.code == "APPROVAL_REQUIRED") }
      let queue = try await runtime.registry("extensions.pending", params: .object([:]), peer: nil, credential: nil)
      let id = try #require(queue.array.first { $0["manifest"]["extensionID"].string == manifest.extensionID }?["id"].string)
      _ = try await runtime.registry("extensions.approve", params: .object(["id": .string(id), "permissions": try JSONValue.encode(permissions ?? manifest.requestedPermissions)]), peer: nil, credential: nil)
      let value = try await runtime.registry("extensions.register", params: params, peer: peer, credential: nil)
      return try value.decode(ExtensionRegistration.self)
    }
    func run(_ id: String, registration: ExtensionRegistration) async throws -> JSONValue {
      try await runtime.publication("runs.begin", params: .object(["runID": .string(id), "scope": .string("selection"), "contributionSetID": .string("results"), "binding": try JSONValue.encode(binding()), "contributionKinds": .array([.string("annotation"), .string("graph"), .string("view")]), "viewIDs": .array([.string("results")])]), peer: peer, credential: registration.credential, snapshot: snapshot)
    }
    func publish(_ run: JSONValue, registration: ExtensionRegistration, contributions: [ExtensionContribution], completion: String = "complete", diagnostic: String? = nil) async throws {
      let manifest = try PublicationManifest(contributions: contributions, attemptDiagnostic: diagnostic)
      var params = ["runID": run["id"], "publicationID": run["publicationID"], "manifest": try JSONValue.encode(manifest)]
      _ = try await runtime.publication("runs.prepare", params: .object(params), peer: peer, credential: registration.credential, snapshot: nil)
      for (kind, method) in [("annotation", "annotations.replaceBatch"), ("graph", "extensionGraphs.replace"), ("view", "views.replace")] {
        params["contributions"] = try JSONValue.encode(contributions.filter { $0.kind == kind })
        _ = try await runtime.publication(method, params: .object(params), peer: peer, credential: registration.credential, snapshot: nil)
      }
      params["manifestDigest"] = .string(CanonicalJSON.digest(try CanonicalJSON.encode(manifest))); params["completion"] = .string(completion)
      _ = try await runtime.publication("runs.commit", params: .object(params), peer: peer, credential: registration.credential, snapshot: nil)
    }
    func prepare(_ registration: ExtensionRegistration, action: String = "check", arguments: JSONValue = .object([:])) async throws -> ActionIntent {
      let value = try await runtime.action("actions.prepare", params: .object(["registrationID": .string(registration.id), "actionID": .string(action), "binding": try JSONValue.encode(binding()), "arguments": arguments]), peer: nil, credential: nil, snapshot: snapshot)
      #expect(value["requiresConfirmation"].bool == true)
      return try value["intent"].decode(ActionIntent.self)
    }
    func confirm(_ intent: ActionIntent) async throws {
      _ = try await runtime.action("actions.confirm", params: .object(["token": .string(intent.authorizationToken), "requestFingerprint": .string(intent.requestFingerprint)]), peer: nil, credential: nil, snapshot: snapshot)
    }
    func receipt(_ intent: ActionIntent, registration: ExtensionRegistration, job: String = "job") async throws {
      _ = try await runtime.action("actions.receipt", params: .object(["idempotencyKey": .string(intent.idempotencyKey), "requestFingerprint": .string(intent.requestFingerprint), "receipt": try JSONValue.encode(ActionReceipt(jobID: job))]), peer: peer, credential: registration.credential, snapshot: nil)
    }
    func report(_ intent: ActionIntent, registration: ExtensionRegistration, run: JSONValue, revision: Int, state: String) async throws -> JSONValue {
      try await runtime.action("actions.state", params: .object(["requestID": .string(intent.requestID), "jobID": .string("job"), "runID": run["id"], "revision": .number(Double(revision)), "state": .string(state)]), peer: peer, credential: registration.credential, snapshot: nil)
    }
  }

  @Test(.timeLimit(.minutes(1))) func bundledProviderUpdatesWithNoNewGrantForUnpairedPeers() async throws {
    let installed = BundledProvider(executable: "/provider-a", digest: "binary-a",
      extensionID: "invar", permissions: [.graphRead, .runsWrite])
    let fixture = try Fixture(bundledProvider: installed)
    let context: JSONValue = .object([:])
    let initial = ExtensionManifest(extensionID: "invar", displayName: "Invar", version: "2.0.0",
                                     requestedPermissions: [.graphRead, .runsWrite])
    let parameters: JSONValue = .object(["manifest": try JSONValue.encode(initial)])
    let registration = try await fixture.runtime.registry("extensions.register", params: parameters,
      peer: fixture.peer, credential: nil).decode(ExtensionRegistration.self)
    #expect(Set(registration.grantedPermissions) == [.graphRead, .runsWrite])
    let copy = ConnectionPeer(processID: 102, auditIdentity: "copy", executable: "/copy",
                              codeIdentity: "code-a", binaryDigest: "binary-a")
    do {
      let resume: JSONValue = .object(["manifest": parameters["manifest"], "resumeCredential": .string(registration.resumeCredential)])
      _ = try await fixture.runtime.registry("extensions.register", params: resume, peer: copy, credential: nil)
      Issue.record("An executable outside the bundle resumed a bundled grant")
    } catch let error as ArchitectureError { #expect(error.code == "APPROVAL_REQUIRED") }
    do {
      _ = try await fixture.runtime.registry("extensions.pending", params: context, peer: fixture.peer, credential: registration.credential)
      Issue.record("The bundled Provider received host administration")
    } catch let error as ArchitectureError { #expect(error.code == "POLICY_DENIED") }
    let broader = ExtensionManifest(extensionID: "invar", displayName: "Invar", version: "2.0.0",
                                     requestedPermissions: [.graphRead, .runsWrite, .canvasControl])
    do {
      _ = try await fixture.runtime.registry("extensions.register",
        params: .object(["manifest": try JSONValue.encode(broader)]), peer: fixture.peer, credential: nil)
      Issue.record("The bundled Provider exceeded the distribution permission ceiling")
    } catch let error as ArchitectureError { #expect(error.code == "APPROVAL_REQUIRED") }
    _ = try await fixture.runtime.registry("extensions.permissions",
      params: .object(["id": .string(registration.id), "permissions": .array([.string("graph.read")])]),
      peer: nil, credential: nil)
    await fixture.runtime.shutdown()

    let updated = BundledProvider(executable: "/provider-b", digest: "binary-b",
      extensionID: "invar", permissions: [.graphRead, .runsWrite])
    let replacement = ExtensionRuntime(workspaceID: "workspace", store: fixture.store, hostDigests: [], bundledProvider: updated)
    let currentPeer = ConnectionPeer(processID: 103, auditIdentity: "peer-b", executable: updated.executable,
                                     codeIdentity: "code-b", binaryDigest: updated.digest)
    let manifest = ExtensionManifest(extensionID: "invar", displayName: "Invar", version: "2.0.1",
      requestedPermissions: [.graphRead, .runsWrite])
    let current = try await replacement.registry("extensions.register",
      params: .object(["manifest": try JSONValue.encode(manifest)]), peer: currentPeer, credential: nil)
      .decode(ExtensionRegistration.self)
    #expect(current.id == registration.id && current.resumeCredential != registration.resumeCredential)
    #expect(current.grantedPermissions == [.graphRead])
    #expect(try await replacement.registry("extensions.pending", params: context, peer: nil, credential: nil).array.isEmpty)
    _ = try await replacement.registry("extensions.unregister",
      params: .object(["id": .string(current.id)]), peer: nil, credential: nil)
    do {
      _ = try await replacement.registry("extensions.register",
        params: .object(["manifest": try JSONValue.encode(manifest)]), peer: currentPeer, credential: nil)
      Issue.record("The bundled Provider was automatically restored after revocation")
    } catch let error as ArchitectureError { #expect(error.code == "APPROVAL_REQUIRED") }
    await replacement.shutdown()
    try await fixture.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func manifestSchemaAndPeerPermissionsRejectBeforeEffects() async throws {
    let f = try Fixture(), manifest = f.manifest()
    var invalid = try JSONValue.encode(manifest).object; invalid["extensionAPI"] = .object(["major": .number(2), "minimumMinor": .number(0)])
    #expect(throws: ArchitectureError.self) { try ExtensionRules.manifest(.object(invalid)) }
    let r = try await f.register(permissions: [.graphRead])
    #expect(try await f.runtime.authorize("graph.overview", peer: f.peer, credential: r.credential) == r.sessionID)
    for method in ["source.read", "inputs.read", "annotations.upsert", "events.poll", "workspace.import", "canvas.list", "canvas.select"] {
      await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize(method, peer: f.peer, credential: r.credential) }
    }
    let impostor = ConnectionPeer(processID: 101, auditIdentity: "peer-b", executable: "/provider-b", codeIdentity: "code-b", binaryDigest: "binary-b")
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("graph.overview", peer: impostor, credential: r.credential) }
    await #expect(throws: ArchitectureError.self) { try await f.runtime.registry("extensions.approve", params: .object([:]), peer: f.peer, credential: r.credential) }
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func canvasReadAndControlPermissionsAreIndependentAndRevocable() async throws {
    let f = try Fixture(), r = try await f.register(permissions: [.canvasRead])
    #expect(try await f.runtime.authorize("canvas.get", peer: f.peer, credential: r.credential) == r.sessionID)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("canvas.select", peer: f.peer, credential: r.credential) }
    _ = try await f.runtime.registry("extensions.permissions", params: .object(["id": .string(r.id), "permissions": .array([])]), peer: nil, credential: nil)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("canvas.get", peer: f.peer, credential: r.credential) }
    try await f.cleanup()
    let controller = try Fixture(), control = try await controller.register(permissions: [.canvasControl])
    await #expect(throws: ArchitectureError.self) { try await controller.runtime.authorize("canvas.select", peer: controller.peer, credential: control.credential) }
    await #expect(throws: ArchitectureError.self) { try await controller.runtime.authorize("canvas.get", peer: controller.peer, credential: control.credential) }
    try await controller.cleanup()
    let combined = try Fixture(), both = try await combined.register(permissions: [.canvasRead, .canvasControl])
    #expect(try await combined.runtime.authorize("canvas.select", peer: combined.peer, credential: both.credential) == both.sessionID)
    try await combined.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func publicationStagesAtomicallyAndHeadNeverRollsBack() async throws {
    let f = try Fixture(), r = try await f.register()
    let old = try await f.run("old", registration: r), newer = try await f.run("new", registration: r)
    let contribution = ExtensionContribution(id: "test.provider:results", kind: "view", binding: try f.binding(), data: .object(["kind": .string("table"), "columns": .array([.string("Report")]), "rows": .array([.array([.string("<script>not executable</script>")])])]))
    let manifest = try PublicationManifest(contributions: [contribution])
    _ = try await f.runtime.publication("runs.prepare", params: .object(["runID": newer["id"], "publicationID": newer["publicationID"], "manifest": try JSONValue.encode(manifest)]), peer: f.peer, credential: r.credential, snapshot: nil)
    let before = try await f.runtime.visible(snapshot: f.snapshot)
    #expect(before["publications"].array.isEmpty)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.publication("runs.commit", params: .object(["runID": newer["id"], "publicationID": newer["publicationID"], "manifestDigest": .string(CanonicalJSON.digest(try CanonicalJSON.encode(manifest))), "completion": .string("complete")]), peer: f.peer, credential: r.credential, snapshot: nil) }
    try await f.publish(newer, registration: r, contributions: [contribution])
    await #expect(throws: ArchitectureError.self) { try await f.publish(old, registration: r, contributions: []) }
    let failed = try await f.run("failed", registration: r)
    try await f.publish(failed, registration: r, contributions: [], completion: "failed", diagnostic: "Unsupported source at line 5")
    let after = try await f.runtime.visible(snapshot: f.snapshot)
    #expect(after["attempts"].array.first { $0["runID"] == failed["id"] }?["diagnostic"].string == "Unsupported source at line 5")
    #expect(after["publications"].array.first?["runID"] == newer["id"])
    #expect(after["publications"].array.first?["applicability"].string == "unknown")
    let empty = try await f.run("empty", registration: r)
    try await f.publish(empty, registration: r, contributions: [])
    let final = try await f.runtime.visible(snapshot: f.snapshot)
    #expect(final["publications"].array.first?["contributions"].array.isEmpty == true)
    let stored = try await f.store.extensionState()
    #expect(stored["heads"].object.values.first == empty["id"])
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func sessionsLeasesTokensAndStagingDoNotTransferOnReconnect() async throws {
    let f = try Fixture(), r = try await f.register()
    let run = try await f.run("pending", registration: r), intent = try await f.prepare(r)
    await f.runtime.ownLease("lease", session: r.sessionID)
    _ = try await f.runtime.registry("extensions.disconnect", params: .object([:]), peer: f.peer, credential: r.credential)
    let response = try await f.runtime.registry("extensions.register", params: .object(["manifest": try JSONValue.encode(f.manifest()), "resumeCredential": .string(r.resumeCredential)]), peer: f.peer, credential: nil)
    let next = try response.decode(ExtensionRegistration.self)
    #expect(next.sessionID != r.sessionID)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("graph.overview", peer: f.peer, credential: r.credential) }
    await #expect(throws: ArchitectureError.self) { try await f.runtime.checkLease("lease", owner: next.sessionID) }
    await #expect(throws: ArchitectureError.self) { try await f.confirm(intent) }
    await #expect(throws: ArchitectureError.self) { try await f.runtime.publication("runs.abort", params: .object(["runID": run["id"], "publicationID": run["publicationID"]]), peer: f.peer, credential: next.credential, snapshot: nil) }
    let resumed = try await f.run("pending", registration: next)
    #expect(resumed["generation"] == run["generation"] && resumed["publicationID"] != run["publicationID"])
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func actionIsDeliveredOnceAndCancellationWaitsForTerminalReport() async throws {
    let f = try Fixture(), r = try await f.register(), run = try await f.run("action", registration: r)
    let intent = try await f.prepare(r)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.action("actions.confirm", params: .object(["token": .string(intent.authorizationToken), "requestFingerprint": .string("forged")]), peer: nil, credential: nil, snapshot: f.snapshot) }
    try await f.confirm(intent)
    let delivered = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    #expect(delivered["requestID"].string == intent.requestID)
    #expect(try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil) == .null)
    try await f.receipt(intent, registration: r)
    _ = try await f.report(intent, registration: r, run: run, revision: 1, state: "running")
    let cancel = try await f.prepare(r, action: "cancel", arguments: .object(["requestID": .string(intent.requestID), "jobID": .string("job"), "runID": run["id"]]))
    try await f.confirm(cancel)
    _ = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    try await f.receipt(cancel, registration: r, job: "cancel-job")
    #expect(try await f.report(intent, registration: r, run: run, revision: 2, state: "running")["state"].string == "cancelling")
    #expect(try await f.report(intent, registration: r, run: run, revision: 3, state: "cancelled")["state"].string == "cancelled")
    #expect(try await f.report(intent, registration: r, run: run, revision: 2, state: "running")["state"].string == "cancelled")
    await #expect(throws: ArchitectureError.self) { try await f.report(intent, registration: r, run: run, revision: 4, state: "completed") }
    try await f.receipt(intent, registration: r)
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func actionDeadlinesAndPermissionRevocationRemainEnforced() async throws {
    let f = try Fixture(), r = try await f.register(), intent = try await f.prepare(r)
    f.clock.advance(301)
    await #expect(throws: ArchitectureError.self) { try await f.confirm(intent) }
    _ = try await f.runtime.registry("extensions.permissions", params: .object(["id": .string(r.id), "permissions": .array([])]), peer: nil, credential: nil)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("graph.overview", peer: f.peer, credential: r.credential) }
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func providerLedgerSurvivesLostAckRestartConflictAndLoss() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let path = root.appendingPathComponent("ledger.json"), ledger = try ProviderActionLedger(path: path)
    let now = Date().timeIntervalSince1970 + 1
    let binding = ExtensionBinding(workspaceID: "w", snapshotID: "s", inputManifestDigest: "digest")
    func action(arguments: JSONValue = .object([:])) throws -> ActionIntent { try ActionIntent(requestID: "request", registrationID: "registration", sessionID: "session", providerID: "p", actionID: "check", actionDefinitionDigest: "definition", inputSchemaID: "schema", effect: "externalExecution", binding: binding, arguments: arguments, requestedAt: now, deadline: now + 300, idempotencyKey: "key") }
    let intent = try action()
    do { _ = try await ledger.lookup(intent, providerID: "p", now: now); Issue.record("Uncertain delivery invented a receipt") }
    catch let error as ArchitectureError { #expect(error.code == "ACTION_OUTCOME_UNKNOWN") }
    let first = try await ledger.reserve(intent, providerID: "p", now: now)
    #expect(first.mayStart)
    let duplicate = try await ledger.reserve(intent, providerID: "p", now: now)
    #expect(!duplicate.mayStart && duplicate.receipt == first.receipt)
    await #expect(throws: ArchitectureError.self) { try await ledger.reserve(action(arguments: .string("changed")), providerID: "p", now: now) }
    await ledger.shutdown()
    let restarted = try ProviderActionLedger(path: path)
    let recovered = try await restarted.reserve(intent, providerID: "p", now: now)
    #expect(!recovered.mayStart && recovered.receipt == first.receipt)
    await #expect(throws: ArchitectureError.self) { try await restarted.reserve(intent, providerID: "p", now: now + 3901) }
    await restarted.shutdown()
    try FileManager.default.removeItem(at: path)
    let lost = try ProviderActionLedger(path: path)
    let ancient = try ActionIntent(requestID: "ancient", registrationID: "r", sessionID: "s", providerID: "p", actionID: "a", actionDefinitionDigest: "d", inputSchemaID: "i", effect: "externalExecution", binding: binding, arguments: .null, requestedAt: now - 100, deadline: now + 300, idempotencyKey: "ancient")
    do { _ = try await lost.reserve(ancient, providerID: "p", now: now); Issue.record("Lost ledger restarted work") }
    catch let error as ArchitectureError { #expect(error.code == "ACTION_OUTCOME_UNKNOWN") }
    await lost.shutdown(); try FileManager.default.removeItem(at: root)
  }
  @Test(.timeLimit(.minutes(1))) func cancellationCannotOverwriteCompletionBetweenPrepareAndConfirm() async throws {
    let f = try Fixture(), r = try await f.register(), run = try await f.run("race", registration: r), intent = try await f.prepare(r)
    try await f.confirm(intent)
    _ = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    try await f.receipt(intent, registration: r)
    _ = try await f.report(intent, registration: r, run: run, revision: 1, state: "running")
    let cancel = try await f.prepare(r, action: "cancel", arguments: .object(["requestID": .string(intent.requestID), "jobID": .string("job"), "runID": run["id"]]))
    _ = try await f.report(intent, registration: r, run: run, revision: 2, state: "completed")
    await #expect(throws: ArchitectureError.self) { try await f.confirm(cancel) }
    let result = try await f.runtime.visible(snapshot: f.snapshot)
    #expect(result["actions"].array.first { $0["requestID"].string == intent.requestID }?["state"].string == "completed")
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func hostRestartNeverRedeliversUnknownRequestAndRetainsHeads() async throws {
    let f = try Fixture(), r = try await f.register(), run = try await f.run("retained", registration: r), intent = try await f.prepare(r)
    try await f.publish(run, registration: r, contributions: [])
    try await f.confirm(intent)
    _ = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    await f.runtime.shutdown()
    let restarted = ExtensionRuntime(workspaceID: "workspace", store: f.store, hostDigests: [], now: { f.clock.now() })
    let response = try await restarted.registry("extensions.register", params: .object(["manifest": try JSONValue.encode(f.manifest()), "resumeCredential": .string(r.resumeCredential)]), peer: f.peer, credential: nil)
    let next = try response.decode(ExtensionRegistration.self)
    #expect(try await restarted.action("actions.next", params: .object([:]), peer: f.peer, credential: next.credential, snapshot: nil) == .null)
    let visible = try await restarted.visible(snapshot: f.snapshot)
    #expect(visible["actions"].array.first?["state"].string == "unknown")
    #expect(visible["publications"].array.first?["runID"] == run["id"])
    await restarted.shutdown(); try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func namespacesProfilesAndRateLimitsAreEnforced() async throws {
    let f = try Fixture(), r = try await f.register(), run = try await f.run("namespace", registration: r)
    let bad = ExtensionContribution(id: "other.provider:results", kind: "view", binding: try f.binding(), data: .object(["kind": .string("table")]))
    await #expect(throws: ArchitectureError.self) { try await f.publish(run, registration: r, contributions: [bad]) }
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("annotations.remove", peer: f.peer, credential: r.credential) }
    for _ in 0..<64 { do { _ = try await f.runtime.authorize("graph.overview", peer: f.peer, credential: r.credential) } catch let error as ArchitectureError { #expect(error.code == "RESOURCE_LIMIT") } }
    await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize("graph.overview", peer: f.peer, credential: r.credential) }
    #expect(try await f.runtime.authorize("workspace.status", peer: nil, credential: nil) == nil)
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func removedProfilesAndMutationNamesAreRejected() async throws {
    let f = try Fixture()
    var manifest = try JSONValue.encode(f.manifest()).object
    manifest["specificationProfiles"] = .array([.string("legacy-provider-write")])
    #expect(throws: ArchitectureError.self) { try ExtensionRules.manifest(.object(manifest)) }
    let r = try await f.register()
    for method in ["annotations.upsert", "annotations.remove", "extensionGraphs.upsert", "snapshots.acquire", "snapshots.renew", "snapshots.release"] {
      await #expect(throws: ArchitectureError.self) { try await f.runtime.authorize(method, peer: f.peer, credential: r.credential) }
    }
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func corruptExtensionStateFailsExplicitlyWithoutBreakingCoreReads() async throws {
    let f = try Fixture()
    try await f.store.importSnapshot(f.snapshot)
    try await f.store.replaceExtensionState(.string("corrupt document"))
    await #expect(throws: ArchitectureError.self) { try await f.runtime.visible(snapshot: f.snapshot) }
    #expect(try await f.store.load(f.snapshot.id).entities.first?.id == "a")
    #expect(try await f.runtime.authorize("graph.overview", peer: nil, credential: nil) == nil)
    #expect(try await f.store.extensionState() == .string("corrupt document"))
    try await f.cleanup()
  }
  @Test(.timeLimit(.minutes(1))) func publicPagesStayBoundedAndRequireResyncAfterPublication() async throws {
    let f = try Fixture(), r = try await f.register(), binding = try f.binding()
    let contribution = ExtensionContribution(id: "test.provider:large", kind: "graph", binding: binding, data: .object(["nodes": .array([.object(["id": .string("test.provider:node"), "label": .string(String(repeating: "x", count: 700000))])]), "edges": .array([])]))
    for index in 0..<5 {
      f.clock.advance(1)
      let run = try await f.runtime.publication("runs.begin", params: .object(["runID": .string("page-\(index)"), "scope": .string("scope-\(index)"), "contributionSetID": .string("results"), "binding": try JSONValue.encode(binding), "contributionKinds": .array([.string("graph")]), "viewIDs": .array([])]), peer: f.peer, credential: r.credential, snapshot: f.snapshot)
      try await f.publish(run, registration: r, contributions: [contribution])
    }
    let first = try await f.runtime.visible(snapshot: f.snapshot)
    let cursor = try #require(first["nextCursor"].string)
    #expect(try CanonicalJSON.encode(first).count < 4 * 1024 * 1024)
    let second = try await f.runtime.visible(snapshot: f.snapshot, cursor: cursor)
    #expect(first["publications"].array.count + second["publications"].array.count == 5)
    f.clock.advance(1)
    _ = try await f.run("invalidates-page", registration: r)
    await #expect(throws: ArchitectureError.self) { try await f.runtime.visible(snapshot: f.snapshot, cursor: cursor) }
    try await f.cleanup()
  }

  @Test(.timeLimit(.minutes(1))) func concurrentFirstReadsShareInitializationInsteadOfReportingBusy() async throws {
    let f = try Fixture()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<12 {
        group.addTask {
          if index.isMultiple(of: 2) { _ = try await f.runtime.visible(snapshot: f.snapshot) }
          else { _ = try await f.runtime.registry("extensions.pending", params: .object([:]), peer: nil, credential: nil) }
        }
      }
      try await group.waitForAll()
    }
    try await f.cleanup()
  }

  @Test(.timeLimit(.minutes(1))) func disconnectedCancellationRecoversWithoutRedeliveryAndNormalCompletionWins() async throws {
    let f = try Fixture(), r = try await f.register(), run = try await f.run("disconnect-cancel", registration: r), intent = try await f.prepare(r)
    try await f.confirm(intent)
    _ = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    try await f.receipt(intent, registration: r)
    _ = try await f.report(intent, registration: r, run: run, revision: 1, state: "running")
    let cancel = try await f.prepare(r, action: "cancel", arguments: .object(["requestID": .string(intent.requestID), "jobID": .string("job"), "runID": run["id"]]))
    try await f.confirm(cancel)
    _ = try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: r.credential, snapshot: nil)
    try await f.receipt(cancel, registration: r, job: "cancel-job")
    _ = try await f.runtime.registry("extensions.disconnect", params: .object([:]), peer: f.peer, credential: r.credential)
    let disconnected = try await f.runtime.visible(snapshot: f.snapshot)
    let parent = try #require(disconnected["actions"].array.first { $0["requestID"].string == intent.requestID })
    #expect(parent["state"].string == "unknown" && parent["lastObserved"].string == "cancelling")
    let response = try await f.runtime.registry("extensions.register", params: .object(["manifest": try JSONValue.encode(f.manifest()), "resumeCredential": .string(r.resumeCredential)]), peer: f.peer, credential: nil)
    let next = try response.decode(ExtensionRegistration.self)
    #expect(try await f.runtime.action("actions.next", params: .object([:]), peer: f.peer, credential: next.credential, snapshot: nil) == .null)
    #expect(try await f.report(intent, registration: next, run: run, revision: 2, state: "running")["state"].string == "cancelling")
    #expect(try await f.report(intent, registration: next, run: run, revision: 3, state: "completed")["state"].string == "completed")
    await #expect(throws: ArchitectureError.self) { try await f.report(intent, registration: next, run: run, revision: 4, state: "cancelled") }
    try await f.cleanup()
  }

  @Test(.timeLimit(.minutes(1))) func shutdownUnlocksTheLedgerEvenWithAnInheritedDescriptor() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let path = root.appendingPathComponent("ledger.json")
    let ledger = try ProviderActionLedger(path: path)
    let lockPath = URL(fileURLWithPath: path.path + ".lock").resolvingSymlinksInPath().path
    var inherited: Int32?
    for name in try FileManager.default.contentsOfDirectory(atPath: "/dev/fd") {
      guard let descriptor = Int32(name) else { continue }
      var bytes = [CChar](repeating: 0, count: Int(MAXPATHLEN))
      // fcntl borrows this bounded buffer only for the synchronous kernel call.
      let status = bytes.withUnsafeMutableBufferPointer { buffer -> Int32 in
        guard let base = buffer.baseAddress else { return -1 }
        return fcntl(descriptor, F_GETPATH, UnsafeMutableRawPointer(base))
      }
      guard status == 0 else { continue }
      let actual = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      if URL(fileURLWithPath: actual).resolvingSymlinksInPath().path == lockPath { inherited = dup(descriptor); break }
    }
    let duplicate = try #require(inherited)
    #expect(duplicate >= 0)
    defer { Darwin.close(duplicate) }
    await ledger.shutdown()
    let successor = try ProviderActionLedger(path: path)
    await successor.shutdown()
    try FileManager.default.removeItem(at: root)
  }

}
