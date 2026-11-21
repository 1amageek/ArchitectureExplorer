@testable import ArchitectureCore
import ArchitectureExtensions
import ArchitectureService
import ArchitectureStore
import Foundation
import Testing

struct ExtensionEventTests {
  @Test(.timeLimit(.minutes(1))) func providerResultsCannotMaskARealInputChange() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("Flow.swift")
    try Data("func value() -> Int { 1 }".utf8).write(to: source)
    let paths = try WorkspacePaths(root.path)
    let store = try SQLiteGraphStore(path: root.appendingPathComponent("store.sqlite").path, workspaceID: paths.workspaceID)
    let service = ArchitectureService(paths: paths, store: store)
    await service.refresh()
    let initial = try await service.handle("events.poll", params: .object([:]))
    let peer = ConnectionPeer(processID: 101, auditIdentity: "events-peer", executable: "/provider", codeIdentity: "code", binaryDigest: "hash")
    let manifest = ExtensionManifest(extensionID: "event.provider", displayName: "Event test", requestedPermissions: [.graphRead, .runsWrite, .eventsSubscribe])
    let registration: JSONValue = .object(["manifest": try JSONValue.encode(manifest)])
    do { _ = try await service.handle("extensions.register", params: registration, peer: peer); Issue.record("Approval bypass") }
    catch let error as ArchitectureError { #expect(error.code == "APPROVAL_REQUIRED") }
    let pending = try await service.handle("extensions.pending", params: .object([:]))
    _ = try await service.handle("extensions.approve", params: .object(["id": pending.array[0]["id"], "permissions": try JSONValue.encode(manifest.requestedPermissions)]))
    let session = try await service.handle("extensions.register", params: registration, peer: peer)
    let credential = try #require(session["credential"].string)
    let inputs = try await service.handle("inputs.manifest", params: .object(["snapshotID": initial["snapshotID"]]))
    let binding = ExtensionBinding(workspaceID: paths.workspaceID, snapshotID: initial["snapshotID"].string!, inputManifestDigest: inputs["inputManifestDigest"].string!)
    _ = try await service.handle("runs.begin", params: .object(["runID": .string("event-run"), "scope": .string("workspace"), "contributionSetID": .string("event-set"), "binding": try JSONValue.encode(binding), "contributionKinds": .array([]), "viewIDs": .array([])]), peer: peer, credential: credential)
    let external = try await service.handle("events.poll", params: initial)
    #expect(external["category"].string == "extensions" && external["originProviderID"].string == "event.provider")
    #expect(external["extensionResyncRequired"].bool == true)
    try Data("func value() -> Int { 2 }".utf8).write(to: source)
    await service.refresh()
    let changed = try await service.handle("events.poll", params: external)
    #expect(changed["snapshotID"] != initial["snapshotID"])
    #expect(changed["category"].string == "structure" && changed["originProviderID"].string == "host")
    #expect(changed["extensionEvent"]["originProviderID"].string == "event.provider")
    await service.shutdown()
    try FileManager.default.removeItem(at: root)
  }
}
