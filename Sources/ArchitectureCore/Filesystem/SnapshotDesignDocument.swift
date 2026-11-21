public enum SnapshotDesignDocument {
  public static func matches(_ path: String) -> Bool {
    let parts = path.lowercased().split(separator: "/")
    guard let name = parts.last, name.hasSuffix(".md") else { return false }
    return ["readme.md", "design.md"].contains(name)
      || parts.dropLast().contains { ["documentation", "docs", "adr", "adrs"].contains($0) }
  }
}
