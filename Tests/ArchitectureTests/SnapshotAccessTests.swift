import ArchitectureCore
import ArchitectureIR
import ArchitectureStore
@testable import ArchitectureService
import Foundation
import Testing

struct SnapshotAccessTests {
  private func fixture(_ root: URL, bytes: Data) throws -> (WorkspacePaths, Snapshot) {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try bytes.write(to: root.appendingPathComponent("Source.swift"))
    let paths = try WorkspacePaths(root.path)
    let entities = ["a", "b"].map { Entity(id: $0, kind: "function", language: "swift", name: $0, identityKey: $0, entityRevision: "1") }
    let snapshot = Snapshot(id: "snapshot", workspaceID: paths.workspaceID, generation: 1, contextDigest: "context", inputs: ["Source.swift": CanonicalJSON.digest(bytes), "@toolchain": "test"], entities: entities,
      facts: [Fact(id: "edge", producer: "test", scope: "source", kind: "calls", source: "a", target: "b", revision: "1")], evidence: [], coverage: [])
    return (paths, snapshot)
  }
  @Test(.timeLimit(.minutes(1))) func originalBytesRemainPinnedAndFactsPageIndependently() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let bytes = Data(repeating: 65, count: 20000)
    let (paths, snapshot) = try fixture(root, bytes: bytes)
    let access = SnapshotAccess()
    let lease = try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 100000, ttl: 30)
    try Data("changed".utf8).write(to: root.appendingPathComponent("Source.swift"))
    let chunk = try await access.read(leaseID: lease.id, path: "Source.swift", offset: 0, count: 262144)
    #expect(chunk.data == bytes && chunk.eof)
    let first = try await access.page(snapshot: snapshot, leaseID: lease.id, collection: "entities", cursor: nil, limit: 1, maximumBytes: 100000)
    let second = try await access.page(snapshot: snapshot, leaseID: lease.id, collection: "entities", cursor: first.nextCursor, limit: 1, maximumBytes: 100000)
    #expect(first.records[0]["id"].string == "a" && second.records[0]["id"].string == "b")
    let edges = try await access.page(snapshot: snapshot, leaseID: lease.id, collection: "facts", cursor: nil, limit: 1, maximumBytes: 100000)
    #expect(edges.records[0]["source"].string == "a" && edges.records[0]["target"].string == "b")
    #expect(throws: ArchitectureError.self) { try SnapshotRecords.page(snapshot: snapshot, collection: "facts", cursor: first.nextCursor, limit: 1, maximumBytes: 100000, inputs: []) }
    #expect(await access.release(lease.id))
    await #expect(throws: ArchitectureError.self) { try await access.read(leaseID: lease.id, path: "Source.swift", offset: 0, count: 1) }
    await access.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func mismatchesLimitsAndSymlinksCannotBecomeCompleteInputs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let (paths, snapshot) = try fixture(root, bytes: Data("original".utf8))
    let access = SnapshotAccess()
    await #expect(throws: ArchitectureError.self) { try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 1, ttl: 30) }
    try Data("changed".utf8).write(to: root.appendingPathComponent("Source.swift"))
    await #expect(throws: ArchitectureError.self) { try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 30) }
    try FileManager.default.removeItem(at: root.appendingPathComponent("Source.swift"))
    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Source.swift").path, withDestinationPath: "/etc/hosts")
    await #expect(throws: ArchitectureError.self) { try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 30) }
    await access.shutdown()
    await #expect(throws: ArchitectureError.self) { try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 30) }
  }
  @Test(.timeLimit(.minutes(1))) func expiryQuotaAndShutdownHaveExplicitBoundaries() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let (paths, snapshot) = try fixture(root, bytes: Data("original".utf8))
    let access = SnapshotAccess()
    var ids: [String] = []
    for _ in 0..<4 { ids.append(try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 1).id) }
    await #expect(throws: ArchitectureError.self) { try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 1) }
    try await Task.sleep(for: .milliseconds(1100))
    await #expect(throws: ArchitectureError.self) { try await access.read(leaseID: ids[0], path: "Source.swift", offset: 0, count: 1) }
    let lease = try await access.acquire(snapshot: snapshot, paths: paths, maximumBytes: 10000, ttl: 30)
    await access.shutdown()
    await #expect(throws: ArchitectureError.self) { try await access.snapshot(for: lease.id) }
  }
  @Test(.timeLimit(.minutes(1))) func malformedRPCParametersCannotFallBackToCurrentInputs() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let (paths, _) = try fixture(root, bytes: Data("func calculate() {}".utf8))
    try paths.prepareState()
    let store = try SQLiteGraphStore(path: paths.state.appendingPathComponent("index.sqlite").path, workspaceID: paths.workspaceID)
    let service = ArchitectureService(paths: paths, store: store)
    for (method, parameters) in [
      ("inputs.acquire", JSONValue.object(["snapshotID": .number(1)])),
      ("graph.scan", JSONValue.object(["collection": .number(1)])),
      ("graph.scan", JSONValue.object(["unexpected": .bool(true)])),
      ("inputs.read", JSONValue.object(["leaseID": .string("none"), "path": .string("Source.swift"), "offset": .number(0.5)]))
    ] {
      do { _ = try await service.handle(method, params: parameters); Issue.record("Invalid parameters were accepted") }
      catch let error as ArchitectureError { #expect(error.code == "INVALID_ARGUMENT") }
    }
    await service.shutdown()
  }
}
