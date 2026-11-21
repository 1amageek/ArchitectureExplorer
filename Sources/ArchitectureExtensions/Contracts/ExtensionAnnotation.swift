import ArchitectureCore

/// A Provider report; identity, ownership and inputs belong to its contribution envelope.
public struct ExtensionAnnotation: Codable, Sendable, Equatable {
  public let reportedStatus: String
  public let claim: String
  public let scope: String
  public let assumptions: [String]
  public let evidence: [JSONValue]
  public let translationStatus: String
  public let attributes: [String: JSONValue]
  public init(reportedStatus: String, claim: String, scope: String, assumptions: [String] = [], evidence: [JSONValue] = [], translationStatus: String = "unknown", attributes: [String: JSONValue] = [:]) {
    self.reportedStatus = reportedStatus; self.claim = claim; self.scope = scope; self.assumptions = assumptions; self.evidence = evidence; self.translationStatus = translationStatus; self.attributes = attributes
  }
}
