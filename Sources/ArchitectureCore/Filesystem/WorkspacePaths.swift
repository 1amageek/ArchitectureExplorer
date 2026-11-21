import Foundation

public struct WorkspacePaths: Sendable {
  public static let architectureModelFilename = "ARCHITECTURE.dsl"
  public let root: URL
  public let workspaceID: String
  public let state: URL
  public init(_ path: String) throws {
    let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory),
      directory.boolValue
    else {
      throw ArchitectureError(
        "INVALID_WORKSPACE", "Workspace directory does not exist.", exitCode: 2)
    }
    self.root = root
    workspaceID = CanonicalJSON.identity(root.path)
    let home = FileManager.default.homeDirectoryForCurrentUser
    state = home.appendingPathComponent("Library/Caches/ArchitectureExplorer")
      .appendingPathComponent(workspaceID)
  }
  public func resolve(_ relative: String) throws -> URL {
    guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains("..") else {
      throw ArchitectureError(
        "ARTIFACT_OUTSIDE_ROOT", "Expected a workspace-relative path.", exitCode: 5)
    }
    let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(root.path + "/") else {
      throw ArchitectureError("ARTIFACT_OUTSIDE_ROOT", "Path escapes workspace.", exitCode: 5)
    }
    return url
  }
  public func prepareState() throws {
    try FileManager.default.createDirectory(
      at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: state.path)
  }
}
