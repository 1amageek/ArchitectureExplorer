import ArchitectureCore
import ArchitectureIR
import Foundation

public struct PublicationManifest: Codable, Sendable, Equatable {
  public let entries: [String: String]
  public let attemptDiagnostic: String?
  public init(contributions: [ExtensionContribution], attemptDiagnostic: String? = nil) throws {
    self.attemptDiagnostic = attemptDiagnostic
    guard Set(contributions.map(\.id)).count == contributions.count else { throw ArchitectureError("INVALID_PUBLICATION", "Duplicate contribution identity.", exitCode: 2) }
    var values: [String: String] = [:]
    for contribution in contributions { values[contribution.id] = try contribution.digest }
    entries = values
  }
}
