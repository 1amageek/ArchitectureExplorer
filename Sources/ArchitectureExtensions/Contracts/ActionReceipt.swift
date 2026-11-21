import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ActionReceipt: Codable, Sendable, Equatable {
  public let accepted: Bool
  public let jobID: String?
  public let reason: String?
  public init(jobID: String) { accepted = true; self.jobID = jobID; reason = nil }
  public init(rejected reason: String) { accepted = false; jobID = nil; self.reason = reason }
}
