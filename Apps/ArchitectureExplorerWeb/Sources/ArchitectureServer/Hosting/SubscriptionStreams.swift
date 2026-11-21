import Foundation

/// The helper owns subscription tasks independently of channel close callbacks.
actor SubscriptionStreams {
  private var tasks: [UUID: Task<Void, Never>] = [:]

  func start(_ operation: @escaping @Sendable () async -> Void) -> UUID {
    let id = UUID()
    tasks[id] = Task {
      await operation()
      finished(id)
    }
    return id
  }

  func cancel(_ id: UUID) { tasks[id]?.cancel() }

  private func finished(_ id: UUID) { tasks.removeValue(forKey: id) }

  func shutdown() async {
    let owned = Array(tasks.values)
    for task in owned { task.cancel() }
    for task in owned { await task.value }
    tasks.removeAll()
  }
}
