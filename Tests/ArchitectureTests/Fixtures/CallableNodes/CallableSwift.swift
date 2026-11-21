public func callableSwift<T>(_ value: T) -> T { value }

public struct CallableWorker {
  public init() {}

  @MainActor
  public mutating func update<T>(_ value: inout T, transform: (T) -> T) async throws -> T where T: Equatable {
    return callableSwift(transform(value))
  }

  public static func make(_ value: Int = 10) -> Int { callableSwift(value) }
}
