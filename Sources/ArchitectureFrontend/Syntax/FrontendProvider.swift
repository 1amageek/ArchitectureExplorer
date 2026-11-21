import ArchitectureIR

public protocol FrontendProvider: Sendable {
  var identity: String { get }
  func capabilities() -> [Capability]
  func analyze(_ input: SourceInput) throws -> FrontendResult
}
