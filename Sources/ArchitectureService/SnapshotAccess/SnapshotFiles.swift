import ArchitectureCore
import ArchitectureIR
import Darwin
import Foundation

enum SnapshotFiles {
  static func capture(_ snapshot: Snapshot, paths: WorkspacePaths, maximumBytes: Int) throws -> CapturedInputs {
    let inputs = snapshot.inputs.filter { !$0.key.hasPrefix("@") }
    guard inputs.count <= 10000 else { throw ArchitectureError("RESOURCE_LIMIT", "Input lease exceeds 10000 files.", exitCode: 6) }
    let root = open(paths.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard root >= 0 else { throw ArchitectureError("POLICY_DENIED", "Cannot open the workspace root safely.", exitCode: 5) }
    defer { close(root) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    var files: [String: Data] = [:], total = 0
    for (path, digest) in inputs.sorted(by: { $0.key < $1.key }) {
      try Task.checkCancellation()
      let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
      guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) }),
        digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else {
        throw ArchitectureError("SOURCE_UNAVAILABLE", "Invalid or unavailable original input: \(path).", exitCode: 7)
      }
      var parent = dup(root)
      guard parent >= 0 else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Cannot retain root descriptor.") }
      defer { close(parent) }
      for component in parts.dropLast() {
        let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw ArchitectureError("POLICY_DENIED", "Input traverses an unavailable or symlinked directory: \(path).", exitCode: 5) }
        close(parent); parent = next
      }
      let descriptor = openat(parent, parts.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
      guard descriptor >= 0 else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Original input is unavailable: \(path).", exitCode: 7) }
      defer { close(descriptor) }
      var info = stat()
      guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 5 * 1024 * 1024 else {
        throw ArchitectureError("RESOURCE_LIMIT", "Expected a regular input file within 5 MiB: \(path).", exitCode: 6)
      }
      // The descriptor chain owns every open exactly once; FileHandle borrows this
      // descriptor only in this scope. No symlink component or pointer can escape.
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
      var data = Data()
      while true {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ArchitectureError("ANALYSIS_TIMEOUT", "Input capture exceeded its deadline.", exitCode: 6) }
        let remaining = min(5 * 1024 * 1024 - data.count, maximumBytes - total - data.count)
        guard remaining >= 0 else { throw ArchitectureError("RESOURCE_LIMIT", "Input content exceeds the lease budget.", exitCode: 6) }
        let chunk = try handle.read(upToCount: min(65536, remaining + 1)) ?? Data()
        if chunk.isEmpty { break }
        guard chunk.count <= remaining else { throw ArchitectureError("RESOURCE_LIMIT", "Input content exceeds the lease budget.", exitCode: 6) }
        data.append(chunk)
      }
      guard CanonicalJSON.digest(data) == digest else {
        throw ArchitectureError("INPUT_CHANGED_DURING_ANALYSIS", "Input does not match the requested snapshot: \(path).", exitCode: 7)
      }
      total += data.count; files[path] = data
    }
    return CapturedInputs(files: files, totalBytes: total)
  }
}
