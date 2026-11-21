import ArchitectureCore
import ArchitectureIR
import Foundation

actor SnapshotAccess {
  private struct Lease: Sendable {
    let snapshot: Snapshot
    let capture: CapturedInputs
    let files: [CapturedInputFile]
    var descriptor: InputLease
    var deadline: ContinuousClock.Instant
    let maximumDeadline: ContinuousClock.Instant
  }
  private var leases: [String: Lease] = [:]
  private var captures: [String: Task<CapturedInputs, any Error>] = [:]
  private var reserved = 0
  private var stopped = false
  private func prune() { leases = leases.filter { $0.value.deadline > .now } }
  func acquire(snapshot: Snapshot, paths: WorkspacePaths, maximumBytes: Int, ttl: Int) async throws -> InputLease {
    prune()
    guard !stopped else { throw ArchitectureError("ANALYSIS_CANCELLED", "Snapshot access has shut down.", exitCode: 130) }
    let held = leases.values.reduce(0) { $0 + $1.capture.totalBytes }
    guard (1...256 * 1024 * 1024).contains(maximumBytes), (1...300).contains(ttl),
      leases.count + captures.count < 4, maximumBytes <= 256 * 1024 * 1024 - held - reserved else {
      throw ArchitectureError("RESOURCE_LIMIT", "Input lease count/content/TTL budget exceeded.", exitCode: 6)
    }
    let metadata = snapshot.inputs.filter { $0.key.hasPrefix("@") }
    guard try CanonicalJSON.encode(metadata).count <= 65536 else { throw ArchitectureError("RESOURCE_LIMIT", "Input metadata exceeds 64 KiB.", exitCode: 6) }
    let id = UUID().uuidString
    let task = Task.detached { try SnapshotFiles.capture(snapshot, paths: paths, maximumBytes: maximumBytes) }
    captures[id] = task; reserved += maximumBytes
    defer { captures[id] = nil; reserved -= maximumBytes }
    let capture = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    try Task.checkCancellation()
    guard !stopped else { throw ArchitectureError("ANALYSIS_CANCELLED", "Snapshot access stopped during capture.", exitCode: 130) }
    let descriptor = InputLease(id: id, workspaceID: snapshot.workspaceID, snapshotID: snapshot.id, contextDigest: snapshot.contextDigest,
      metadata: metadata, fileCount: capture.files.count, totalBytes: capture.totalBytes,
      expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(ttl))))
    let catalog = capture.files.keys.sorted().map { CapturedInputFile(path: $0, digest: snapshot.inputs[$0]!, byteCount: capture.files[$0]!.count) }
    leases[id] = Lease(snapshot: snapshot, capture: capture, files: catalog, descriptor: descriptor, deadline: .now.advanced(by: .seconds(ttl)), maximumDeadline: .now.advanced(by: .seconds(900)))
    return descriptor
  }
  private func lease(_ id: String) throws -> Lease {
    prune()
    guard let lease = leases[id] else { throw ArchitectureError("SNAPSHOT_EXPIRED", "Input lease expired or was released.", exitCode: 7) }
    return lease
  }
  func read(leaseID: String, path: String, offset: Int, count: Int) throws -> InputChunk {
    let value = try lease(leaseID)
    guard let bytes = value.capture.files[path], let digest = value.snapshot.inputs[path] else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Path is not in this input lease.", exitCode: 7) }
    guard (1...262144).contains(count), offset >= 0, offset <= bytes.count else { throw ArchitectureError("INVALID_ARGUMENT", "Invalid input chunk range.", exitCode: 2) }
    let end = offset + min(count, bytes.count - offset)
    return InputChunk(path: path, digest: digest, totalBytes: bytes.count, offset: offset, data: bytes.subdata(in: offset..<end), eof: end == bytes.count)
  }
  func page(snapshot: Snapshot, leaseID: String?, collection: String, cursor: String?, limit: Int, maximumBytes: Int) throws -> SnapshotPage {
    let original: Snapshot
    let files: [CapturedInputFile]
    if let leaseID {
      let value = try lease(leaseID)
      guard value.snapshot.id == snapshot.id else { throw ArchitectureError("SNAPSHOT_EXPIRED", "Lease belongs to another snapshot.", exitCode: 7) }
      original = value.snapshot
      files = collection == "inputs" ? value.files : []
    } else {
      original = snapshot
      files = collection == "inputs" ? snapshot.inputs.filter { !$0.key.hasPrefix("@") }.sorted { $0.key < $1.key }.map { CapturedInputFile(path: $0.key, digest: $0.value, byteCount: nil) } : []
    }
    return try SnapshotRecords.page(snapshot: original, collection: collection, cursor: cursor, limit: limit, maximumBytes: maximumBytes, inputs: files)
  }
  func propertyContext(leaseID: String, entityID: String) throws -> JSONValue {
    let value = try lease(leaseID)
    return try PropertyContext.build(value.snapshot, files: value.capture.files, entityID: entityID)
  }
  func renew(_ id: String, ttl: Int) throws -> JSONValue {
    var value = try lease(id)
    guard (1...300).contains(ttl), .now.advanced(by: .seconds(ttl)) <= value.maximumDeadline else { throw ArchitectureError("RESOURCE_LIMIT", "Lease renewal TTL must be 1...300 seconds.", exitCode: 6) }
    value.deadline = .now.advanced(by: .seconds(ttl))
    value.descriptor = InputLease(id: value.descriptor.id, workspaceID: value.descriptor.workspaceID, snapshotID: value.descriptor.snapshotID, contextDigest: value.descriptor.contextDigest, metadata: value.descriptor.metadata, fileCount: value.descriptor.fileCount, totalBytes: value.descriptor.totalBytes, expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(Double(ttl))))
    leases[id] = value
    return try JSONValue.encode(value.descriptor)
  }
  func snapshot(for id: String) throws -> Snapshot { try lease(id).snapshot }
  func release(_ id: String) -> Bool { leases.removeValue(forKey: id) != nil }
  func shutdown() async {
    stopped = true
    let pending = Array(captures.values)
    for task in pending { task.cancel() }
    for task in pending { _ = await task.result }
    leases.removeAll()
  }
}
