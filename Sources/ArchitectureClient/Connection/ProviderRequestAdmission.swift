import ArchitectureCore
import Foundation

actor ProviderRequestAdmission {
  private var next = ContinuousClock.now
  private var pending = 0
  func acquire() async throws {
    guard pending < 64 else { throw ArchitectureError("RESOURCE_LIMIT", "Provider Client admission queue is full.", exitCode: 6) }
    let start = max(next, .now)
    next = start.advanced(by: .milliseconds(32))
    pending += 1; defer { pending -= 1 }
    try await Task.sleep(until: start, clock: .continuous)
  }
}
