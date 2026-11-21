import ArchitectureCore

public protocol CanvasSessionManaging: Sendable {
  func handle(_ method: String, parameters: JSONValue) async throws -> JSONValue
  func shutdown() async
}
