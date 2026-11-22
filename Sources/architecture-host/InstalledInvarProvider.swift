import ArchitectureCore
import ArchitectureExtensions
import ArchitectureService
import Darwin
import Foundation

enum InstalledInvarProvider {
  static func identify(host: URL) throws -> BundledProvider? {
    let resources = host.resolvingSymlinksInPath().deletingLastPathComponent()
    let contents = resources.deletingLastPathComponent()
    let bundle = contents.deletingLastPathComponent()
    guard resources.lastPathComponent == "Resources", contents.lastPathComponent == "Contents",
          bundle.lastPathComponent == "Invar_invar.bundle" else { return nil }
    let executable = bundle.deletingLastPathComponent().appendingPathComponent("invar")
    var info = stat()
    guard lstat(executable.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
          info.st_uid == getuid() || info.st_uid == 0, info.st_mode & 0o022 == 0,
          info.st_size > 0 && info.st_size <= 128 * 1024 * 1024,
          FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw ArchitectureError("COMPANION_UNAVAILABLE", "The installed Invar executable could not be paired with Explorer.", exitCode: 3)
    }
    let bytes = try Data(contentsOf: executable, options: .mappedIfSafe)
    return BundledProvider(executable: executable.path, digest: CanonicalJSON.digest(bytes), extensionID: "invar",
      permissions: [.graphRead, .inputsRead, .eventsSubscribe, .graphsWrite, .viewsWrite, .annotationsWrite, .runsWrite, .actionsReceive])
  }
}
