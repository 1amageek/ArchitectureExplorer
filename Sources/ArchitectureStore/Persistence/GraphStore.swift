import ArchitectureCore
import ArchitectureIR
import Foundation

public protocol GraphStore: Sendable {
  func latest() async throws -> Snapshot?
  func load(_ id: String) async throws -> Snapshot
  func publish(_ snapshot: Snapshot) async throws
  func importSnapshot(_ snapshot: Snapshot) async throws
  func history() async throws -> [String]
  func extensionState() async throws -> JSONValue
  func replaceExtensionState(_ state: JSONValue) async throws
}
