import ArchitectureCore
import Foundation

public actor CanvasSessions: CanvasSessionManaging {
  private struct Session: Sendable {
    var document: CanvasDocument
    var revision = 1
    var state: JSONValue = .object(["selection": .array([]), "collapsed": .array([]), "filter": .object([:]), "layout": .string("auto"), "camera": .null, "geometry": .array([]), "focus": .array([]), "focusNonce": .number(0)])
    func value(_ id: String) throws -> JSONValue { .object(["viewSessionID": .string(id), "revision": .number(Double(revision)), "document": try JSONValue.encode(document), "state": state]) }
  }
  private let reader: any CanvasFileReading
  private var sessions: [String: Session] = [:]
  private var closed = false
  public init(reader: any CanvasFileReading = CanvasFileReader()) { self.reader = reader }
  public func shutdown() { sessions.removeAll(); closed = true }
  public func handle(_ method: String, parameters p: JSONValue) async throws -> JSONValue {
    guard !closed else { throw ArchitectureError("SESSION_EXPIRED", "Canvas owner is shut down.", exitCode: 5) }
    try Task.checkCancellation()
    if method == "canvas.list" {
      return .object(["sessions": .array(sessions.keys.sorted().map { id in let s = sessions[id]!; return .object(["viewSessionID": .string(id), "revision": .number(Double(s.revision)), "title": .string(s.document.title), "format": .string(s.document.format), "kind": .string(s.document.kind)]) })])
    }
    if method == "canvas.open" {
      guard let name = p["name"].string, let text = p["text"].string else { throw CanvasSyntax.invalid("canvas.open requires name and text.") }
      let document = try reader.read(name: name, text: text, kind: p["kind"].string)
      try Task.checkCancellation()
      let id = p["viewSessionID"].string ?? UUID().uuidString
      if let current = sessions[id] { try compare(p, revision: current.revision) }
      else if p["viewSessionID"].string != nil { throw missing() }
      guard sessions[id] != nil || sessions.count < 32 else { throw CanvasSyntax.limit() }
      let candidate = Session(document: document, revision: (sessions[id]?.revision ?? 0) + 1)
      try admit(candidate, id: id); sessions[id] = candidate; return try candidate.value(id)
    }
    guard let id = p["viewSessionID"].string, var session = sessions[id] else { throw missing() }
    if method == "canvas.get" {
      if let collection = p["collection"].string {
        if collection == "state" {
          var state = session.state.object; state.removeValue(forKey: "geometry")
          return .object(["viewSessionID": .string(id), "revision": .number(Double(session.revision)), "state": .object(state)])
        }
        guard ["nodes", "edges", "lanes"].contains(collection) else { throw CanvasSyntax.invalid("Unknown Canvas collection.") }
        let documentValue = try JSONValue.encode(session.document), values = documentValue[collection].array
        let prefix = session.document.sourceDigest + ":" + collection + ":", offset: Int
        if let cursor = p["cursor"].string { guard cursor.hasPrefix(prefix), let n = Int(cursor.dropFirst(prefix.count)), n >= 0, n <= values.count else { throw ArchitectureError("CURSOR_EXPIRED", "Canvas document changed or cursor is invalid.", exitCode: 7) }; offset = n } else { offset = 0 }
        let limit = p["limit"].int ?? 20; guard (1...100).contains(limit) else { throw CanvasSyntax.limit() }
        let end = min(values.count, offset + limit)
        return .object(["viewSessionID": .string(id), "revision": .number(Double(session.revision)), "kind": .string(session.document.kind), "title": .string(session.document.title), "collection": .string(collection), "items": .array(Array(values[offset..<end])), "truncated": .bool(end < values.count), "nextCursor": end < values.count ? .string(prefix + String(end)) : .null])
      }
      return try session.value(id)
    }
    if method == "canvas.export" {
      let format = p["format"].string ?? "json", result: String
      switch format {
      case "json": var document = session.document; var metadata = document.metadata.object; metadata["viewState"] = session.state; document.metadata = .object(metadata); let encoded = try CanonicalJSON.encode(document); result = String(decoding: encoded, as: UTF8.self)
      case "svg": result = try CanvasSVGExport.render(session.document, state: session.state)
      default: throw CanvasSyntax.unsupported("Canvas exports support json and svg.")
      }
      return .object(["viewSessionID": .string(id), "revision": .number(Double(session.revision)), "format": .string(format), "text": .string(result)])
    }
    try compare(p, revision: session.revision)
    if method == "canvas.close" { sessions[id] = nil; return .object(["closed": .bool(true), "viewSessionID": .string(id)]) }
    var state = session.state.object
    let laneIDs = Set(session.document.lanes.map { "__lane:" + $0.id }), fragments = Set(session.document.metadata["fragments"].array.indices.map { "__fragment:" + String($0) })
    let nodeIDs = Set(session.document.nodes.map(\.id)).union(session.document.svg == nil ? [] : ["__svg"]).union(laneIDs).union(fragments), allIDs = nodeIDs.union(session.document.edges.map(\.id))
    func ids(_ key: String, allowed: Set<String>) throws -> [String] {
      guard case .array = p[key], p[key].array.allSatisfy({ $0.string != nil }), p[key].array.count <= 1500 else { throw CanvasSyntax.invalid("\(key) requires a bounded string array.") }
      let values = p[key].array.compactMap(\.string); guard Set(values).isSubset(of: allowed) else { throw CanvasSyntax.invalid("Unknown Canvas identity.") }; return Array(Set(values)).sorted()
    }
    switch method {
    case "canvas.select": state["selection"] = .array(try ids("ids", allowed: allIDs).map(JSONValue.string))
    case "canvas.focus":
      let focus = try ids("ids", allowed: allIDs)
      state["focus"] = .array(focus.map(JSONValue.string)); state["focusNonce"] = .number(Double((state["focusNonce"]?.int ?? 0) + 1))
      let parents = Dictionary(uniqueKeysWithValues: session.document.nodes.compactMap { n in n.parentID.map { (n.id, $0) } })
      var expanded = Set<String>()
      for identity in focus {
        let endpoints = nodeIDs.contains(identity) ? [identity] : session.document.edges.filter { $0.id == identity }.flatMap { [$0.source, $0.target] }
        for endpoint in endpoints { var parent = parents[endpoint]; while let id = parent { expanded.insert(id); parent = parents[id] } }
      }
      let previous = Set(state["collapsed"]?.array.compactMap(\.string) ?? [])
      if !expanded.isDisjoint(with: previous) || !(state["filter"]?.object.isEmpty ?? true) { state["geometry"] = .array([]) }
      state["collapsed"] = .array(previous.subtracting(expanded).sorted().map(JSONValue.string)); state["filter"] = .object([:])
    case "canvas.expand", "canvas.collapse":
      let groupIDs = Set(session.document.nodes.compactMap(\.parentID))
      let changed = Set(try ids("ids", allowed: groupIDs)), current = Set(state["collapsed"]?.array.compactMap(\.string) ?? [])
      state["collapsed"] = .array((method == "canvas.expand" ? current.subtracting(changed) : current.union(changed)).sorted().map(JSONValue.string)); state["geometry"] = .array([])
    case "canvas.setFilter":
      if p["filter"]["roles"] != .null { guard case .array = p["filter"]["roles"], p["filter"]["roles"].array.allSatisfy({ $0.string != nil }) else { throw CanvasSyntax.invalid("Canvas roles require a string array.") } }
      guard case .object = p["filter"], p["filter"].object.keys.allSatisfy({ ["text", "roles"].contains($0) }), p["filter"]["text"] == .null || p["filter"]["text"].string != nil else { throw CanvasSyntax.invalid("Canvas filter supports text and roles.") }
      state["filter"] = p["filter"]; state["geometry"] = .array([])
    case "canvas.setLayout":
      guard let layout = p["layout"].string, ["auto", "layered", "grid", "sequence"].contains(layout), layout != "sequence" || session.document.kind == "sequence" else { throw CanvasSyntax.unsupported("Unsupported Canvas layout.") }
      if let kind = p["kind"].string { session.document.kind = kind; try session.document.validate() }
      state["layout"] = .string(layout); state["geometry"] = .array([])
    case "canvas.setCamera":
      guard case .number(let zoom) = p["camera"]["zoom"], zoom.isFinite, zoom >= 0.12, zoom <= 3, case .number(let x) = p["camera"]["pan"]["x"], case .number(let y) = p["camera"]["pan"]["y"], x.isFinite, y.isFinite, abs(x) <= 10000000, abs(y) <= 10000000 else { throw CanvasSyntax.invalid("Invalid bounded Canvas camera.") }
      state["camera"] = p["camera"]
    case "canvas.setGeometry":
      guard case .array = p["geometry"], p["geometry"].array.count <= 756 else { throw CanvasSyntax.limit() }
      let allowed = nodeIDs
      var seen = Set<String>()
      for box in p["geometry"].array {
        guard let boxID = box["id"].string, allowed.contains(boxID), seen.insert(boxID).inserted else { throw CanvasSyntax.invalid("Unknown/duplicate geometry identity.") }
        for key in ["x", "y", "width", "height"] { guard case .number(let n) = box[key], n.isFinite, abs(n) <= 1000000, !["width", "height"].contains(key) || n > 0 else { throw CanvasSyntax.invalid("Invalid Canvas geometry.") } }
      }
      state["geometry"] = p["geometry"]
    default: throw CanvasSyntax.unsupported("Unknown Canvas operation: \(method)")
    }
    session.state = .object(state); session.revision += 1; try admit(session, id: id); sessions[id] = session; return try session.value(id)
  }
  private func missing() -> ArchitectureError { ArchitectureError("VIEW_SESSION_NOT_FOUND", "Canvas session is closed, unknown or belongs to an earlier daemon.", exitCode: 2) }
  private func compare(_ p: JSONValue, revision: Int) throws { if p["expectedRevision"] != .null { guard p["expectedRevision"].int == revision else { throw ArchitectureError("REVISION_CONFLICT", "Canvas session changed; read the latest revision before retrying.", exitCode: 7) } } }
  private func admit(_ candidate: Session, id: String) throws {
    var bytes = try CanonicalJSON.encode(candidate.value(id)).count
    guard bytes <= 3 * 1024 * 1024 else { throw CanvasSyntax.limit() }
    for (key, session) in sessions where key != id { bytes += try CanonicalJSON.encode(session.value(key)).count }
    guard bytes <= 16 * 1024 * 1024 else { throw CanvasSyntax.limit() }
  }
}
