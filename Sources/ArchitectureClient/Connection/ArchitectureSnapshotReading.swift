import ArchitectureIR

public protocol ArchitectureSnapshotReading: Sendable {
  func acquireInputs(snapshotID: String?, maximumBytes: Int, ttl: Int) async throws -> InputLease
  func scanSnapshot(snapshotID: String, leaseID: String?, collection: String, cursor: String?, limit: Int) async throws -> SnapshotPage
  func readInput(leaseID: String, path: String, offset: Int, count: Int) async throws -> InputChunk
  func releaseInputs(leaseID: String) async throws
}
