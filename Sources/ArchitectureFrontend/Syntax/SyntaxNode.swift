import Foundation

public struct SyntaxNode: Sendable {
  public let kind: String
  public let field: String?
  public let start: Int
  public let end: Int
  public let named: Bool
  public let children: [SyntaxNode]
  public func child(_ field: String) -> SyntaxNode? { children.first { $0.field == field } }
  public var namedChildren: [SyntaxNode] { children.filter(\.named) }
  public func descendants(_ kinds: Set<String>) -> [SyntaxNode] {
    (kinds.contains(kind) ? [self] : []) + children.flatMap { $0.descendants(kinds) }
  }
}
