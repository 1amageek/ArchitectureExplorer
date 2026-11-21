public protocol CanvasFileReading: Sendable {
  func read(name: String, text: String, kind: String?) throws -> CanvasDocument
}
