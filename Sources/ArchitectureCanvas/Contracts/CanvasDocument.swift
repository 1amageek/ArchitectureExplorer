import ArchitectureCore
import Foundation

public struct CanvasDocument: Codable, Sendable, Equatable {
  public var schemaVersion = "1"
  public var kind: String
  public var title: String
  public var format: String
  public var sourceName: String
  public var sourceDigest: String
  public var nodes: [CanvasNode]
  public var edges: [CanvasEdge]
  public var lanes: [CanvasLane]
  public var metadata: JSONValue
  public var svg: String?
  public static let kinds: Set<String> = ["hierarchy", "relations", "controlFlow", "dataFlow", "stateTransition", "sequence", "proofDependencies"]
  public init(kind: String = "relations", title: String, format: String, sourceName: String, sourceDigest: String, nodes: [CanvasNode] = [], edges: [CanvasEdge] = [], lanes: [CanvasLane] = [], metadata: JSONValue = .object([:]), svg: String? = nil) {
    self.kind = kind; self.title = title; self.format = format; self.sourceName = sourceName; self.sourceDigest = sourceDigest; self.nodes = nodes; self.edges = edges; self.lanes = lanes; self.metadata = metadata; self.svg = svg
  }
  public func validate() throws {
    guard schemaVersion == "1", Self.kinds.contains(kind), nodes.count <= 500, edges.count <= 1500, lanes.count <= 128, metadata["fragments"].array.count <= 128 else { throw ArchitectureError("INVALID_CANVAS", "Unsupported document version/kind or graph budget.", exitCode: 2) }
    let ids = Set(nodes.map(\.id)), edgeIDs = Set(edges.map(\.id)), laneIDs = Set(lanes.map(\.id))
    guard ids.count == nodes.count, edgeIDs.count == edges.count, laneIDs.count == lanes.count, ids.isDisjoint(with: edgeIDs), !ids.contains(""), !edgeIDs.contains(""), !laneIDs.contains(""), !ids.union(edgeIDs).contains(where: { $0 == "__svg" || $0.hasPrefix("__lane:") || $0.hasPrefix("__fragment:") || $0.hasPrefix("__lane-contains:") || $0.hasPrefix("__contains:") }) else { throw ArchitectureError("INVALID_CANVAS", "Duplicate, reserved or empty Canvas identity.", exitCode: 2) }
    guard svg == nil || nodes.isEmpty && edges.isEmpty && lanes.isEmpty else { throw ArchitectureError("INVALID_CANVAS", "Static SVG cannot also declare semantic graph elements.", exitCode: 2) }
    guard edges.allSatisfy({ ids.contains($0.source) && ids.contains($0.target) }), nodes.allSatisfy({ ($0.parentID == nil || ids.contains($0.parentID!)) && ($0.laneID == nil || laneIDs.contains($0.laneID!)) && ($0.order == nil || $0.order!.isFinite) }) else { throw ArchitectureError("INVALID_CANVAS", "Dangling Canvas endpoint, hierarchy or lane.", exitCode: 2) }
    let parents = Dictionary(uniqueKeysWithValues: nodes.compactMap { n in n.parentID.map { (n.id, $0) } })
    for node in nodes {
      var seen = Set([node.id]), parent = node.parentID
      while let id = parent { guard seen.insert(id).inserted, seen.count <= 64 else { throw ArchitectureError("INVALID_CANVAS", "Cyclic or over-depth Canvas hierarchy.", exitCode: 2) }; parent = parents[id] }
    }
    if kind == "sequence" { guard !lanes.isEmpty, nodes.allSatisfy({ $0.laneID != nil && $0.order != nil }) else { throw ArchitectureError("INVALID_CANVAS", "Sequence events require explicit lanes and order.", exitCode: 2) } }
    guard svg != nil || !nodes.isEmpty || kind == "sequence" && !lanes.isEmpty else { throw ArchitectureError("INVALID_CANVAS", "The imported document has no drawable elements.", exitCode: 2) }
  }
}
