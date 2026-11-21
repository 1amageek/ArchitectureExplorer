import ArchitectureIR

public protocol GraphQuerying: Sendable {
  func view(_ query: GraphQuery, snapshot: Snapshot) throws -> GraphView
}
