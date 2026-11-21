import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionManifest: Codable, Sendable, Equatable {
  public let schemaVersion: String
  public let extensionID: String
  public let displayName: String
  public let version: String
  public struct API: Codable, Sendable, Equatable {
    public let major: Int
    public let minimumMinor: Int
    public init(major: Int = 1, minimumMinor: Int = 0) { self.major = major; self.minimumMinor = minimumMinor }
  }
  public let extensionAPI: API
  public let specificationProfiles: [String]
  public let architectureIRMajors: [Int]
  public let requestedPermissions: [ExtensionPermission]
  public let views: [ExtensionViewDefinition]
  public let actions: [ExtensionActionDefinition]
  public init(extensionID: String, displayName: String, version: String = "0.1.0", extensionAPI: API = API(), specificationProfiles: [String] = ["aex-1.3"], architectureIRMajors: [Int] = [1], requestedPermissions: [ExtensionPermission], views: [ExtensionViewDefinition] = [], actions: [ExtensionActionDefinition] = []) {
    self.schemaVersion = "1.0"; self.extensionID = extensionID; self.displayName = displayName; self.version = version
    self.extensionAPI = extensionAPI; self.specificationProfiles = specificationProfiles; self.architectureIRMajors = architectureIRMajors; self.requestedPermissions = requestedPermissions; self.views = views; self.actions = actions
  }
}
