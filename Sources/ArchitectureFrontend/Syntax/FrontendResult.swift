import ArchitectureIR

public struct FrontendResult: Sendable {
  public let entities: [Entity]
  public let facts: [Fact]
  public let evidence: [Evidence]
  public let coverage: Coverage
  public init(entities: [Entity], facts: [Fact], evidence: [Evidence], coverage: Coverage) {
    self.entities = entities
    self.facts = facts
    self.evidence = evidence
    self.coverage = coverage
  }
}
