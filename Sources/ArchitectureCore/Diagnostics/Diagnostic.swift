public struct Diagnostic: Codable, Sendable, Equatable {
  public let code: String
  public let severity: String
  public let phase: String
  public let scope: String
  public let message: String
  public let recovery: String
  public init(
    _ code: String, _ message: String, scope: String = "workspace", phase: String = "analysis",
    severity: String = "warning",
    recovery: String = "Inspect provider coverage and source evidence."
  ) {
    self.code = code
    self.message = message
    self.scope = scope
    self.phase = phase
    self.severity = severity
    self.recovery = recovery
  }
}
