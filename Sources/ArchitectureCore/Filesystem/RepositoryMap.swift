import Darwin
import Foundation

/// A user-selected collection manifest. Source contents are read only on explicit navigation.
public struct RepositoryMap: Sendable {
  private let root: URL
  private let title: String
  private let nodes: [JSONValue]
  private let edges: [JSONValue]
  private let checkouts: [String: String]
  private static let excluded = Set(["node_modules", "vendor", "target", "DerivedData", "Pods", "dist", "build", "__pycache__"])
  private static let sourceExtensions = Set(["swift", "rs", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "go", "kt", "java", "c", "h", "cpp", "hpp", "tf", "sql", "proto", "tla", "lean", "json", "yaml", "yml", "toml", "md"])
  private static func valid(_ component: String) -> Bool {
    !component.isEmpty && !component.hasPrefix(".") && !component.contains("/") &&
      !component.utf8.contains(0) && !excluded.contains(component)
  }
  private static func failure(_ message: String) -> ArchitectureError {
    ArchitectureError("SCOPE_UNAVAILABLE", message, exitCode: 4)
  }

  public init(root: URL, manifest: URL) throws {
    let handle = try FileHandle(forReadingFrom: manifest)
    defer {
      do { try handle.close() } catch { FileHandle.standardError.write(Data("Repository map close failed: \(error)\n".utf8)) }
    }
    let bytes = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
    guard bytes.count <= 1024 * 1024 else { throw Self.failure("Repository map exceeds 1 MiB.") }
    let value = try JSONDecoder().decode(JSONValue.self, from: bytes)
    guard case let .array(nodes) = value["nodes"], case let .array(edges) = value["edges"],
          nodes.count <= 500, edges.count <= 1500 else { throw Self.failure("Invalid repository map or map budget exceeded.") }
    var checkouts: [String: String] = [:]
    for node in nodes {
      guard let id = node["id"].string, checkouts[id] == nil,
            let name = node["details"]["checkouts"].array.first?.string, Self.valid(name) else {
        throw Self.failure("Each repository needs a unique ID and a direct checkout name.")
      }
      checkouts[id] = name
    }
    self.root = root
    self.title = value["title"].string ?? root.lastPathComponent
    self.nodes = nodes
    self.edges = edges
    self.checkouts = checkouts
  }

  public func browse(_ params: JSONValue) throws -> JSONValue {
    let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard rootFD >= 0 else { throw Self.failure("Collection root is unavailable.") }
    defer { close(rootFD) }
    guard let repo = params["repo"].string else {
      let present = try nodes.filter { node in
        guard let name = checkouts[node["id"].string ?? ""] else { return false }
        var info = stat()
        if fstatat(rootFD, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
          if errno == ENOENT { return false }
          throw Self.failure("Cannot inspect checkout: \(name)")
        }
        return info.st_mode & S_IFMT == S_IFDIR
      }
      let ids = Set(present.compactMap { $0["id"].string })
      return .object(["title": .string(title), "nodes": .array(present), "edges": .array(edges.filter {
        ids.contains($0["source"].string ?? "") && ids.contains($0["target"].string ?? "")
      })])
    }
    if params["path"] != .null {
      guard case .array = params["path"] else { throw Self.failure("Path must be an array of components.") }
    }
    let parts = params["path"].array.compactMap(\.string)
    guard let checkout = checkouts[repo], parts.count == params["path"].array.count, parts.count <= 40,
          parts.allSatisfy(Self.valid) else { throw Self.failure("Invalid repository scope.") }
    // Each successful open retains a descriptor for the next component. Never follow a symlink,
    // including during a concurrent rename. FileHandle below only borrows the final descriptor.
    var fd = openat(rootFD, checkout, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Self.failure("Checkout was removed or moved.") }
    defer { close(fd) }
    for (index, part) in parts.enumerated() {
      let directoryFlag = index + 1 == parts.count ? 0 : O_DIRECTORY
      var info = stat()
      guard fstatat(fd, part, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
        if errno == ENOENT { throw ArchitectureError("ENTRY_MISSING", "Input unavailable: " + part) }
        throw Self.failure("Cannot inspect input.")
      }
      guard [S_IFDIR, S_IFREG].contains(info.st_mode & S_IFMT) else { throw Self.failure("Entry unavailable or unsupported.") }
      let next = openat(fd, part, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | directoryFlag)
      guard next >= 0 else { throw Self.failure("Entry moved or is unreadable.") }
      close(fd)
      fd = next
    }
    var info = stat()
    guard fstat(fd, &info) == 0 else { throw Self.failure("Entry is unreadable.") }
    let title = ([checkout] + parts).joined(separator: "/")
    if info.st_mode & S_IFMT == S_IFDIR {
      return .object(["title": .string(title), "directory": .bool(true), "repo": .string(repo), "checkout": .string(checkout)])
    }
    guard let name = parts.last, info.st_mode & S_IFMT == S_IFREG, Self.canPreview(name) else {
      throw Self.failure("Preview is available for source and project text files only.")
    }
    let limit = 16384
    let bytes = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: limit + 1) ?? Data()
    guard !bytes.contains(0) else { throw Self.failure("Binary file has no text preview.") }
    guard let preview = bytes.count > limit ? String(decoding: bytes.prefix(limit), as: UTF8.self) : String(data: bytes, encoding: .utf8) else {
      throw Self.failure("Cannot preview a non-UTF-8 source.")
    }
    return .object(["title": .string(title), "text": .string(preview),
                    "truncated": .bool(bytes.count > limit)])
  }

  private static func canPreview(_ name: String) -> Bool {
    sourceExtensions.contains((name as NSString).pathExtension.lowercased()) || ["Dockerfile", "Makefile"].contains(name)
  }

  public func input(repo: String, path: [String]) throws -> JSONValue? {
    do {
      let value = try browse(.object(["repo": .string(repo), "path": .array(path.map(JSONValue.string))]))
      guard value["text"].string != nil else { throw Self.failure("Expected a source file.") }
      return value
    } catch let error as ArchitectureError where error.code == "ENTRY_MISSING" { return nil }
  }
}
