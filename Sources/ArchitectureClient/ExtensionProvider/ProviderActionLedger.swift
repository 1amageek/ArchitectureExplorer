import ArchitectureCore
import ArchitectureExtensions
import Darwin
import Foundation

/// One actor owns a locked on-disk ledger for the lifetime of a Provider process.
public actor ProviderActionLedger {
  public struct Reservation: Sendable { public let receipt: ActionReceipt; public let mayStart: Bool }
  private struct Entry: Codable, Sendable { let fingerprint: String; let receipt: ActionReceipt; let expiresAt: Double }
  private struct State: Codable, Sendable { let createdAt: Double; var entries: [String: Entry] = [:] }
  private let path: URL
  private var lock: Int32
  private var state: State
  private var stopped = false
  public init(path: URL) throws {
    self.path = path
    let lock = Darwin.open(path.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lock >= 0 else { throw ArchitectureError("LEDGER_UNAVAILABLE", "Cannot open Provider ledger lock.", exitCode: 6) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); throw ArchitectureError("RESOURCE_BUSY", "Provider ledger already has an owner.", exitCode: 6) }
    self.lock = lock
    do {
      if FileManager.default.fileExists(atPath: path.path) {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? Int ?? Int.max) <= 1024 * 1024 else { throw ArchitectureError("LEDGER_UNAVAILABLE", "Ledger must be a bounded regular file.", exitCode: 6) }
        state = try JSONDecoder().decode(State.self, from: Data(contentsOf: path))
      } else {
        state = State(createdAt: Date().timeIntervalSince1970)
        try CanonicalJSON.encode(state).write(to: path, options: [.atomic])
        guard chmod(path.path, 0o600) == 0 else { throw ArchitectureError("LEDGER_UNAVAILABLE", "Cannot protect Provider ledger.", exitCode: 6) }
      }
    } catch { flock(lock, LOCK_UN); Darwin.close(lock); throw error }
  }
  deinit { if lock >= 0 { flock(lock, LOCK_UN); Darwin.close(lock) } }
  /// Reconciliation never admits a missing request as new work.
  public func lookup(_ intent: ActionIntent, providerID: String, now: Double = Date().timeIntervalSince1970) throws -> ActionReceipt {
    guard state.entries[intent.idempotencyKey] != nil else { throw ArchitectureError("ACTION_OUTCOME_UNKNOWN", "No durable receipt exists for this uncertain delivery; do not start work.", exitCode: 7) }
    return try reserve(intent, providerID: providerID, now: now).receipt
  }
  /// Only mayStart=true authorizes the caller to begin its own external work.
  public func reserve(_ intent: ActionIntent, providerID: String, now: Double = Date().timeIntervalSince1970) throws -> Reservation {
    guard !stopped else { throw ArchitectureError("LEDGER_UNAVAILABLE", "Provider ledger is closed.", exitCode: 6) }
    guard intent.providerID == providerID, intent.requestFingerprint == (try intent.verifiedFingerprint()) else { throw ArchitectureError("IDEMPOTENCY_CONFLICT", "Action identity or fingerprint changed.", exitCode: 5) }
    guard now < intent.deadline + 3600 else { throw ArchitectureError("IDEMPOTENCY_KEY_EXPIRED", "Action ledger retention expired.", exitCode: 7) }
    if let entry = state.entries[intent.idempotencyKey] {
      guard entry.fingerprint == intent.requestFingerprint else { throw ArchitectureError("IDEMPOTENCY_CONFLICT", "Key already belongs to a different action.", exitCode: 5) }
      return Reservation(receipt: entry.receipt, mayStart: false)
    }
    guard intent.requestedAt >= state.createdAt else { throw ArchitectureError("ACTION_OUTCOME_UNKNOWN", "Ledger does not cover the request's admission time; do not restart work.", exitCode: 7) }
    guard now < intent.deadline else { throw ArchitectureError("IDEMPOTENCY_KEY_EXPIRED", "Initial acceptance deadline passed.", exitCode: 7) }
    var candidate = state
    candidate.entries = candidate.entries.filter { $0.value.expiresAt > now }
    guard candidate.entries.count < 512 else { throw ArchitectureError("RESOURCE_LIMIT", "Active deduplication ledger is full.", exitCode: 6) }
    let receipt = ActionReceipt(jobID: UUID().uuidString)
    candidate.entries[intent.idempotencyKey] = Entry(fingerprint: intent.requestFingerprint, receipt: receipt, expiresAt: intent.deadline + 3600)
    let bytes = try CanonicalJSON.encode(candidate)
    guard bytes.count <= 1024 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Provider ledger exceeds byte budget.", exitCode: 6) }
    try bytes.write(to: path, options: [.atomic])
    guard chmod(path.path, 0o600) == 0 else { throw ArchitectureError("LEDGER_UNAVAILABLE", "Cannot protect Provider ledger.", exitCode: 6) }
    state = candidate
    return Reservation(receipt: receipt, mayStart: true)
  }
  public func shutdown() {
    stopped = true
    if lock >= 0 {
      // Unlock the shared open-file description before closing inherited references.
      flock(lock, LOCK_UN); Darwin.close(lock); lock = -1
    }
  }
}
