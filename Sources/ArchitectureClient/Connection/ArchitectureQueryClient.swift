import ArchitectureCore
import ArchitectureIR

public protocol ArchitectureQueryClient: Sendable {
  func call(_ method: String, parameters: JSONValue) async throws -> JSONValue
}
