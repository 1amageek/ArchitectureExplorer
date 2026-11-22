import ArchitectureCore
import ArchitectureExtensions

/// A companion selected by the host composition root from its installed distribution.
public struct BundledProvider: Sendable {
  public let executable: String
  public let digest: String
  public var identity: String { CanonicalJSON.identity(executable + ":" + digest) }
  let extensionID: String
  let permissions: Set<ExtensionPermission>

  public init(executable: String, digest: String, extensionID: String, permissions: Set<ExtensionPermission>) {
    self.executable = executable
    self.digest = digest
    self.extensionID = extensionID
    self.permissions = permissions
  }

  func matches(_ peer: ConnectionPeer, manifest: ExtensionManifest) -> Bool {
    peer.executable == executable && peer.binaryDigest == digest
      && manifest.extensionID == extensionID && Set(manifest.requestedPermissions).isSubset(of: permissions)
  }
}
