import ArchitectureCore
import ArchitectureCanvas
import ArchitectureExtensions
import ArchitectureFrontend
import ArchitectureGraph
import ArchitectureIR
import ArchitectureIndexer
import ArchitectureStore
import Darwin
import Foundation

public actor ArchitectureService {
  public let paths: WorkspacePaths
  private let store: any GraphStore
  private let snapshotAccess = SnapshotAccess()
  private let canvas: any CanvasSessionManaging = CanvasSessions()
  private let extensions: ExtensionRuntime
  private let indexer: WorkspaceIndexer
  private let epoch = UUID().uuidString
  private var stopping = false
  private var lastError: Diagnostic?
  private var historyIDs: [String] = []
  private var indexJobID: String?
  private var indexJobResults: [String: JSONValue] = [:]
  private var indexTask: Task<Void, Never>?
  private var viewCache: [String: (value: JSONValue, bytes: Int)] = [:]
  private var viewCacheOrder: [String] = []
  private var viewCacheBytes = 0
  public init(
    paths: WorkspacePaths, store: any GraphStore,
    provider: any FrontendProvider = SkeletonFrontend(), trustedHostDigests: Set<String> = []
  ) {
    self.paths = paths
    self.store = store
    extensions = ExtensionRuntime(workspaceID: paths.workspaceID, store: store, hostDigests: trustedHostDigests)
    indexer = WorkspaceIndexer(paths: paths, store: store, provider: provider)
  }
  public func shouldStop() -> Bool { stopping }
  func acknowledgeStop() { stopping = true }
  public func shutdown() async {
    indexTask?.cancel()
    if let indexTask { await indexTask.value }
    indexTask = nil
    await snapshotAccess.shutdown()
    await canvas.shutdown()
    await extensions.shutdown()
  }
  public func refresh() async {
    do {
      let snapshot = try await indexer.reconcile()
      historyIDs = ([snapshot.id] + historyIDs.filter { $0 != snapshot.id }).prefix(16).map { $0 }
      lastError = nil
    } catch let error as ArchitectureError {
      lastError = Diagnostic(error.code, error.message, phase: "index")
    } catch { lastError = Diagnostic("INDEX_FAILED", String(describing: error), phase: "index") }
  }
  public func handle(_ method: String, params: JSONValue, peer: ConnectionPeer? = nil, credential: String? = nil) async throws -> JSONValue {
    if method.hasPrefix("canvas.") {
      _ = try await extensions.authorize(method, peer: peer, credential: credential)
      return try await canvas.handle(method, parameters: params)
    }
    if method == "daemon.hello" { return try await route(method, params: params) }
    if method.hasPrefix("extensions.") && !["extensions.view"].contains(method) { return try await extensions.registry(method, params: params, peer: peer, credential: credential) }
    if method == "extensions.view" {
      try Self.snapshotParameters(params, strings: ["snapshotID", "cursor"], integers: [])
      _ = try await extensions.authorize("graph.overview", peer: peer, credential: credential)
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      _ = try await extensions.authorize("graph.overview", peer: peer, credential: credential, admit: false)
      return try await extensions.visible(snapshot: snapshot, cursor: params["cursor"].string)
    }
    if method.hasPrefix("runs.") || ["annotations.replaceBatch", "extensionGraphs.replace", "views.replace"].contains(method) {
      let snapshot = method == "runs.begin" ? try await indexer.snapshot(params["binding"]["snapshotID"].string) : nil
      return try await extensions.publication(method, params: params, peer: peer, credential: credential, snapshot: snapshot)
    }
    if method.hasPrefix("actions.") {
      let snapshot: Snapshot?
      if method == "actions.prepare" {
        if try await extensions.isCancellation(params, peer: peer) { snapshot = nil }
        else { snapshot = try await indexer.snapshot(params["binding"]["snapshotID"].string) }
      }
      else if method == "actions.confirm" { snapshot = try await indexer.snapshot() }
      else { snapshot = nil }
      return try await extensions.action(method, params: params, peer: peer, credential: credential, snapshot: snapshot)
    }
    let owner = try await extensions.authorize(method, peer: peer, credential: credential)
    if ["inputs.read", "inputs.release", "inputs.renew", "graph.scan", "inputs.manifest"].contains(method), let id = params["leaseID"].string { try await extensions.checkLease(id, owner: owner) }
    if method == "inputs.manifest" {
      try Self.snapshotParameters(params, strings: ["snapshotID", "leaseID"], integers: [])
      let snapshot: Snapshot
      if let id = params["leaseID"].string { snapshot = try await snapshotAccess.snapshot(for: id) }
      else { snapshot = try await indexer.snapshot(params["snapshotID"].string) }
      if let expected = params["snapshotID"].string, expected != snapshot.id { throw ArchitectureError("INPUT_CHANGED", "Manifest snapshot differs from lease.", exitCode: 7) }
      let manifest = InputManifest(snapshot: snapshot)
      _ = try await extensions.authorize(method, peer: peer, credential: credential, admit: false)
      return .object(["manifest": try JSONValue.encode(manifest), "inputManifestDigest": .string(try manifest.digest)])
    }
    if method == "inputs.renew" {
      try Self.snapshotParameters(params, strings: ["leaseID"], integers: ["ttl"])
      let result = try await snapshotAccess.renew(params["leaseID"].string ?? "", ttl: Self.integer(params, "ttl", default: 60))
      _ = try await extensions.authorize(method, peer: peer, credential: credential, admit: false)
      if let owner, let id = result["id"].string, let expires = result["expiresAt"].string, let date = ISO8601DateFormatter().date(from: expires) { await extensions.ownLease(id, session: owner, expiresAt: date.timeIntervalSince1970) }
      return result
    }
    var result = try await route(method, params: params)
    if method == "inputs.acquire", let id = result["id"].string, let owner { await extensions.ownLease(id, session: owner) }
    if method == "inputs.release", let id = params["leaseID"].string { await extensions.releaseLease(id) }
    if method == "events.poll" {
      let event: JSONValue
      do { event = try await extensions.event() }
      catch {
        if owner != nil { throw error }
        var envelope = result.object
        envelope["extensionError"] = .string(String(describing: error))
        return .object(envelope)
      }
      var envelope = result.object
      for (key, value) in event.object { envelope[key] = value }
      let changed = params["extensionSequence"] != event["extensionSequence"] || params["sessionRevision"] != event["sessionRevision"]
      envelope["extensionChanged"] = .bool(changed)
      envelope["extensionResyncRequired"] = .bool(changed)
      envelope["extensionEvent"] = event
      if result["type"].string != "unchanged" {
        envelope["category"] = .string(result["type"].string == "viewInvalidated" ? "structure" : "analysis")
        envelope["originProviderID"] = .string("host")
        envelope["causationID"] = result["snapshotID"]
      }
      result = .object(envelope)
    }
    if owner != nil { _ = try await extensions.authorize(method, peer: peer, credential: credential, admit: false) }
    return result
  }
  private func route(_ method: String, params: JSONValue) async throws -> JSONValue {
    switch method {
    case "daemon.hello":
      return .object([
        "capabilities": .array([.string("snapshot.scan.v1"), .string("inputs.lease.v1"), .string("extensions.aex-1.3")]),
        "protocolVersion": .string("1.0"), "workspaceID": .string(paths.workspaceID),
        "pid": .number(Double(getpid())), "processIdentity": .string(epoch),
      ])
    case "daemon.stop":
      return .object(["stopping": .bool(true), "workspaceID": .string(paths.workspaceID)])
    case "workspace.status":
      let snapshot = await indexer.publishedSnapshot()
      var status = await indexer.status().object
      status["schemaVersion"] = .string("1.0")
      status["history"] = .array(historyIDs.map(JSONValue.string))
      status["coverage"] = try JSONValue.encode(snapshot?.coverage ?? [])
      status["diagnostics"] = try JSONValue.encode(
        (snapshot?.diagnostics ?? []) + (lastError.map { [$0] } ?? []))
      status["streamEpoch"] = .string(epoch)
      status["entityCount"] = .number(Double(snapshot?.entities.count ?? 0))
      status["edgeCount"] = .number(Double(snapshot?.facts.count ?? 0))
      return .object(status)
    case "workspace.index":
      if let indexJobID, indexJobResults[indexJobID] == nil {
        return .object(["jobID": .string(indexJobID), "state": .string("running")])
      }
      let id = UUID().uuidString
      indexJobID = id
      if indexJobResults.count >= 16 { indexJobResults.removeAll() }
      indexTask = Task {
        do {
          let snapshot = try await indexer.reconcile()
          let result: JSONValue = .object([
            "schemaVersion": .string(snapshot.schemaVersion),
            "workspaceID": .string(snapshot.workspaceID), "snapshotID": .string(snapshot.id),
            "generation": .number(Double(snapshot.generation)),
            "entityCount": .number(Double(snapshot.entities.count)),
            "edgeCount": .number(Double(snapshot.facts.count)),
            "coverage": try JSONValue.encode(snapshot.coverage),
            "diagnostics": try JSONValue.encode(snapshot.diagnostics),
          ])
          historyIDs = ([snapshot.id] + historyIDs.filter { $0 != snapshot.id }).prefix(16).map {
            $0
          }
          indexJobResults[id] = .object(["state": .string("completed"), "result": result])
        } catch {
          let typed =
            error as? ArchitectureError
            ?? ArchitectureError("INDEX_FAILED", String(describing: error))
          indexJobResults[id] = .object([
            "state": .string("failed"),
            "error": .object([
              "code": .string(typed.code), "message": .string(typed.message),
              "exitCode": .number(Double(typed.exitCode)),
            ]),
          ])
        }
      }
      return .object(["jobID": .string(id), "state": .string("running")])
    case "workspace.index.result":
      guard let id = params["jobID"].string else {
        throw ArchitectureError("INVALID_ARGUMENT", "Index job ID is required.", exitCode: 2)
      }
      if let result = indexJobResults[id] { return result }
      guard id == indexJobID else {
        throw ArchitectureError(
          "SNAPSHOT_EXPIRED", "Index job is no longer retained; obtain workspace.status.",
          exitCode: 7)
      }
      let progress = await indexer.status()
      return .object(["state": .string("running"), "progress": progress])
    case "workspace.project":
      let base = try await indexer.snapshot()
      let result = try await ProjectMetadataProvider().analyze(
        paths: paths, snapshot: base, trusted: params["trusted"].bool == true)
      let next = try await indexer.publishSupplement(result, base: base)
      return .object([
        "snapshotID": .string(next.id), "coverage": try JSONValue.encode(result.coverage),
      ])
    case "graph.semantic":
      guard let id = params["focus"].string, let executable = params["provider"].string else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Semantic query requires focus and explicit provider executable.",
          exitCode: 2)
      }
      let snapshot = try await indexer.snapshot()
      guard let entity = snapshot.entities.first(where: { $0.id == id }), let anchor = entity.anchor
      else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Semantic query requires a source entity.", exitCode: 2)
      }
      let bytes = try Data(contentsOf: paths.resolve(anchor.path))
      guard CanonicalJSON.digest(bytes) == anchor.digest else {
        throw ArchitectureError("STALE_ANALYSIS", "Selected source changed.", exitCode: 7)
      }
      let input = SourceInput(
        workspaceID: paths.workspaceID, path: anchor.path, language: entity.language, bytes: bytes,
        contextDigest: snapshot.contextDigest, generation: snapshot.generation)
      var offset = anchor.startByte
      let source = String(decoding: bytes[anchor.startByte..<anchor.endByte], as: UTF8.self)
      if let nameRange = source.range(of: entity.name) {
        offset += source[..<nameRange.lowerBound].utf8.count
      }
      let response = try await SemanticProvider().query(
        input: input, workspace: paths.root, executable: executable,
        operation: params["operation"].string ?? "definition", byteOffset: offset,
        trusted: params["trusted"].bool == true)
      let supplement = try SemanticGraphAdapter().facts(
        response, snapshot: snapshot, subject: entity, paths: paths)
      let published = try await indexer.publishSupplement(supplement, base: snapshot)
      var value = response.object
      value["snapshotID"] = .string(published.id)
      value["relationsCommitted"] = .number(Double(supplement.facts.count))
      return .object(value)
    case "workspace.import":
      let snapshot = try params["snapshot"].decode(Snapshot.self)
      guard snapshot.workspaceID == paths.workspaceID else {
        throw ArchitectureError("INVALID_GRAPH", "Import workspace mismatch.", exitCode: 7)
      }
      try await store.importSnapshot(snapshot)
      return .object(["snapshotID": .string(snapshot.id)])
    case "graph.capabilities":
      let caps =
        SkeletonFrontend().capabilities()
        + ["swift", "rust"].map {
          Capability(
            language: $0, producer: $0 == "swift" ? "sourcekit-lsp" : "rust-analyzer",
            feature: "semantic", supported: false,
            scope: "explicit local provider and trusted project preparation",
            reason: "No semantic process has been explicitly configured for this workspace.")
        }
      return try JSONValue.encode(caps)
    case "events.poll":
      guard let snapshot = await indexer.publishedSnapshot() else {
        return .object([
          "type": .string("analysisStatusChanged"), "streamEpoch": .string(epoch),
          "snapshotID": .null, "progress": await indexer.status(),
        ])
      }
      let previous = params["snapshotID"].string
      let progress = await indexer.status()
      if progress["pending"].bool == true, previous == snapshot.id {
        return .object([
          "type": .string("analysisStatusChanged"), "streamEpoch": .string(epoch),
          "snapshotID": .string(snapshot.id), "progress": progress,
        ])
      }
      let resync = params["streamEpoch"].string != epoch || previous != snapshot.id
      return .object([
        "type": .string(resync ? "viewInvalidated" : "unchanged"), "streamEpoch": .string(epoch),
        "sequence": .number(Double(snapshot.generation)), "snapshotID": .string(snapshot.id),
        "resyncRequired": .bool(resync),
      ])
    case "graph.diff":
      guard let from = params["from"].string, let to = params["to"].string else {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Diff requires from and to snapshots.", exitCode: 2)
      }
      let a = try await store.load(from)
      let b = try await store.load(to)
      return try GraphEngine().diff(a, b)
    case "graph.annotations", "extensionGraphs.list":
      try Self.snapshotParameters(params, strings: ["snapshotID", "cursor"], integers: [])
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      return try await extensions.contributions(kind: method == "graph.annotations" ? "annotation" : "graph", snapshot: snapshot, cursor: params["cursor"].string)
    case "properties.context":
      try Self.snapshotParameters(params, strings: ["snapshotID", "entityID"], integers: [])
      guard let snapshotID = params["snapshotID"].string, let entityID = params["entityID"].string else {
        throw ArchitectureError("INVALID_ARGUMENT", "A pinned snapshot and node are required.")
      }
      let snapshot = try await indexer.snapshot(snapshotID)
      let lease = try await snapshotAccess.acquire(snapshot: snapshot, paths: paths, maximumBytes: 24 * 1024 * 1024, ttl: 60)
      do {
        let context = try await snapshotAccess.propertyContext(leaseID: lease.id, entityID: entityID)
        _ = await snapshotAccess.release(lease.id)
        return context
      } catch {
        _ = await snapshotAccess.release(lease.id)
        throw error
      }
    case "inputs.acquire":
      try Self.snapshotParameters(params, strings: ["snapshotID"], integers: ["maximumBytes", "ttl"])
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      let value = try await snapshotAccess.acquire(snapshot: snapshot, paths: paths,
        maximumBytes: Self.integer(params, "maximumBytes", default: 64 * 1024 * 1024), ttl: Self.integer(params, "ttl", default: 60))
      return try JSONValue.encode(value)
    case "inputs.read":
      try Self.snapshotParameters(params, strings: ["leaseID", "path"], integers: ["offset", "count"])
      guard let id = params["leaseID"].string, let path = params["path"].string else { throw ArchitectureError("INVALID_ARGUMENT", "Input lease and path required.", exitCode: 2) }
      let value = try await snapshotAccess.read(leaseID: id, path: path, offset: Self.integer(params, "offset", default: 0), count: Self.integer(params, "count", default: 262144))
      return try JSONValue.encode(value)
    case "inputs.release":
      try Self.snapshotParameters(params, strings: ["leaseID"], integers: [])
      guard let id = params["leaseID"].string else { throw ArchitectureError("INVALID_ARGUMENT", "Input lease required.", exitCode: 2) }
      return .object(["released": .bool(await snapshotAccess.release(id))])
    case "graph.scan":
      try Self.snapshotParameters(params, strings: ["snapshotID", "leaseID", "collection", "cursor"], integers: ["limit", "maximumBytes"])
      let snapshot: Snapshot
      if let id = params["leaseID"].string { snapshot = try await snapshotAccess.snapshot(for: id) }
      else { snapshot = try await indexer.snapshot(params["snapshotID"].string) }
      if let expected = params["snapshotID"].string, expected != snapshot.id { throw ArchitectureError("SNAPSHOT_EXPIRED", "Scan snapshot differs from lease.", exitCode: 7) }
      let value = try await snapshotAccess.page(snapshot: snapshot, leaseID: params["leaseID"].string,
        collection: params["collection"].string ?? "entities", cursor: params["cursor"].string,
        limit: Self.integer(params, "limit", default: 100), maximumBytes: Self.integer(params, "maximumBytes", default: 1024 * 1024))
      return try JSONValue.encode(value)
    case "workspace.sequences":
      try Self.snapshotParameters(params, strings: ["snapshotID", "subjectID"], integers: [])
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      return try SequenceQueries.list(in: snapshot, subjectID: params["subjectID"].string)
    case "workspace.sequence":
      try Self.snapshotParameters(params, strings: ["snapshotID", "key"], integers: [])
      guard let snapshotID = params["snapshotID"].string, let key = params["key"].string else {
        throw ArchitectureError("INVALID_ARGUMENT", "A pinned snapshot and scenario key are required.", exitCode: 2)
      }
      let snapshot = try await indexer.snapshot(snapshotID)
      return try SequenceQueries.document(in: snapshot, key: key)
    case "workspace.specification":
      try Self.snapshotParameters(params, strings: ["snapshotID"], integers: [])
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      let path = "SPEC.md"
      guard let digest = snapshot.inputs[path] else {
        return .object(["status": .string("missing"), "snapshotID": .string(snapshot.id)])
      }
      let file = try paths.resolve(path)
      let handle = try FileHandle(forReadingFrom: file)
      defer { handle.closeFile() }
      let bytes = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
      guard bytes.count <= 256 * 1024, let text = String(data: bytes, encoding: .utf8) else {
        throw ArchitectureError("SOURCE_UNAVAILABLE", "Specification must be UTF-8 and at most 256 KiB.", exitCode: 3)
      }
      guard CanonicalJSON.digest(bytes) == digest else {
        throw ArchitectureError("STALE_ANALYSIS", "The specification on disk differs from this snapshot.", exitCode: 7)
      }
      return .object(["status": .string("available"), "path": .string(path), "digest": .string(digest), "snapshotID": .string(snapshot.id), "text": .string(text)])
    case "source.read":
      guard let entityID = params["entityID"].string else {
        throw ArchitectureError("INVALID_ARGUMENT", "Entity ID required.", exitCode: 2)
      }
      let snapshot = try await indexer.snapshot(params["snapshotID"].string)
      guard let node = snapshot.entities.first(where: { $0.id == entityID }),
        let anchor = node.anchor
      else {
        throw ArchitectureError("SOURCE_UNAVAILABLE", "Entity has no source anchor.", exitCode: 3)
      }
      let bytes = try Data(contentsOf: paths.resolve(anchor.path))
      guard CanonicalJSON.digest(bytes) == anchor.digest else {
        throw ArchitectureError(
          "STALE_ANALYSIS", "The historical source body is not retained; disk input differs.",
          exitCode: 7)
      }
      guard anchor.endByte <= bytes.count, anchor.startByte <= anchor.endByte else {
        throw ArchitectureError("INVALID_GRAPH", "Source anchor outside file.", exitCode: 7)
      }
      let hasStart = params["startByte"] != .null, hasEnd = params["endByte"] != .null
      guard hasStart == hasEnd else { throw ArchitectureError("INVALID_ARGUMENT", "Source ranges require both bounds.", exitCode: 2) }
      let start = try Self.integer(params, "startByte", default: anchor.startByte)
      let requestedEnd = try Self.integer(params, "endByte", default: anchor.endByte)
      guard start >= anchor.startByte, requestedEnd <= anchor.endByte, start <= requestedEnd else {
        throw ArchitectureError("INVALID_ARGUMENT", "Source range must be inside the entity.", exitCode: 2)
      }
      let end = start + min(requestedEnd - start, 16384)
      let selectedAnchor = SourceAnchor(path: anchor.path, digest: anchor.digest, startByte: start, endByte: requestedEnd)
      return .object([
        "anchor": try JSONValue.encode(selectedAnchor),
        "text": .string(String(decoding: bytes[start..<end], as: UTF8.self)),
        "truncated": .bool(end < requestedEnd), "snapshotID": .string(snapshot.id),
        "encoding": .string("utf-8"),
      ])
    case "graph.export":
      let query = try Self.query(
        params["query"], method: params["query"]["method"].string ?? "graph.overview")
      let snapshot = try await resolveSnapshot(for: query)
      let base = try GraphEngine().view(query, snapshot: snapshot)
      let external = try await extensions.visible(snapshot: snapshot)
      var envelope = try JSONValue.encode(base).object
      var exportedExtensions = base.extensions ?? [:]
      exportedExtensions["aex-1.3"] = external
      envelope["extensions"] = .object(exportedExtensions)
      let view = try JSONValue.object(envelope).decode(GraphView.self)
      let text = try GraphExporter.text(view, format: params["format"].string ?? "json")
      return .object(["text": .string(text), "snapshotID": .string(snapshot.id)])
    default:
      guard method.hasPrefix("graph.") else {
        throw ArchitectureError(
          "UNSUPPORTED_CAPABILITY", "Unknown RPC method: \(method)", exitCode: 3)
      }
      let query = try Self.query(params, method: method)
      let snapshot = try await resolveSnapshot(for: query)
      let cacheKey = snapshot.id + ":" + CanonicalJSON.digest(try CanonicalJSON.encode(query))
      if let cached = viewCache[cacheKey], method != "graph.explain" {
        return await liveEnvelope(cached.value, query: query)
      }
      let view = try GraphEngine().view(query, snapshot: snapshot)
      if method == "graph.explain" {
        guard let node = view.nodes.first else {
          throw ArchitectureError("ENTITY_NOT_FOUND", "No matching node.", exitCode: 2)
        }
        return .object([
          "view": try JSONValue.encode(view),
          "explanation": .string(
            "\(node.kind) \(node.name) is recorded by \(view.evidence.map(\.producer).sorted().joined(separator:", ")). Source identity and declared coverage are attached; no unrecorded responsibility is inferred."
          ),
        ])
      }
      let value = try JSONValue.encode(view)
      let bytes = try CanonicalJSON.encode(value).count
      if bytes <= 16 * 1024 * 1024 {
        while viewCache.count >= 64 || viewCacheBytes + bytes > 16 * 1024 * 1024 {
          guard !viewCacheOrder.isEmpty else { break }
          let removed = viewCacheOrder.removeFirst()
          if let old = viewCache.removeValue(forKey: removed) { viewCacheBytes -= old.bytes }
        }
        viewCache[cacheKey] = (value, bytes)
        viewCacheOrder.append(cacheKey)
        viewCacheBytes += bytes
      }
      return await liveEnvelope(value, query: query)
    }
  }
  private func resolveSnapshot(for query: GraphQuery) async throws -> Snapshot {
    guard query.method == "graph.cfg" else { return try await indexer.snapshot(query.snapshotID) }
    guard let focus = query.focus else {
      throw ArchitectureError("INVALID_ARGUMENT", "CFG requires focus.", exitCode: 2)
    }
    if let id = query.snapshotID {
      let snapshot = try await indexer.snapshot(id)
      guard ControlFlowProvider().hasSupportedGraph(for: focus, in: snapshot) else {
        throw ArchitectureError(
          "CFG_UNAVAILABLE",
          "The pinned snapshot has no supported recorded CFG; generate one with an unpinned request.",
          exitCode: 3)
      }
      return snapshot
    }
    return try await indexer.cfg(focus)
  }
  private func liveEnvelope(_ response: JSONValue, query: GraphQuery) async -> JSONValue {
    guard query.snapshotID == nil else { return response }
    var value = response.object
    let status = await indexer.status()
    if status["pending"].bool == true {
      value["freshness"] = .string("pending")
    } else if status["diskReconciled"].bool != true {
      value["freshness"] = .string("stale")
    }
    return .object(value)
  }

  private static func snapshotParameters(_ params: JSONValue, strings: Set<String>, integers: Set<String>) throws {
    guard case .object(let values) = params, Set(values.keys).isSubset(of: strings.union(integers)) else { throw ArchitectureError("INVALID_ARGUMENT", "Unknown snapshot parameter or non-object input.", exitCode: 2) }
    for (key, value) in values where value != .null {
      guard strings.contains(key) ? value.string != nil : value.int != nil else { throw ArchitectureError("INVALID_ARGUMENT", "Snapshot parameter has an invalid type.", exitCode: 2) }
    }
  }
  private static func integer(_ value: JSONValue, _ key: String, default fallback: Int) throws -> Int {
    if value[key] == .null { return fallback }
    guard let number = value[key].int else { throw ArchitectureError("INVALID_ARGUMENT", "Expected integer for \(key).", exitCode: 2) }
    return number
  }
  private static func query(_ params: JSONValue, method: String) throws -> GraphQuery {
    guard case .object(let values) = params else {
      throw ArchitectureError(
        "INVALID_ARGUMENT", "Graph parameters must be an object.", exitCode: 2)
    }
    let strings: Set<String> = [
      "method", "snapshotID", "focus", "text", "direction", "cursor", "level", "target",
    ]
    let integers: Set<String> = ["depth", "limit", "edgeLimit"]
    let arrays: Set<String> = ["kinds", "languages"]
    guard Set(values.keys).isSubset(of: strings.union(integers).union(arrays)) else {
      throw ArchitectureError("INVALID_ARGUMENT", "Unknown graph parameter.", exitCode: 2)
    }
    for (key, value) in values where value != .null {
      if strings.contains(key), value.string == nil {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Graph parameter \(key) must be a string.", exitCode: 2)
      }
      if integers.contains(key), value.int == nil {
        throw ArchitectureError(
          "INVALID_ARGUMENT", "Graph parameter \(key) must be an integer.", exitCode: 2)
      }
      if arrays.contains(key) {
        guard case .array(let elements) = value, elements.allSatisfy({ $0.string != nil }) else {
          throw ArchitectureError(
            "INVALID_ARGUMENT", "Graph parameter \(key) must contain strings.", exitCode: 2)
        }
      }
    }
    if let declared = values["method"]?.string, declared != method {
      throw ArchitectureError(
        "INVALID_ARGUMENT", "Conflicting graph method identities.", exitCode: 2)
    }
    return GraphQuery(
      method: method, snapshotID: params["snapshotID"].string, focus: params["focus"].string,
      text: params["text"].string ?? "", kinds: params["kinds"].array.compactMap(\.string),
      languages: params["languages"].array.compactMap(\.string),
      direction: params["direction"].string ?? "outgoing", depth: params["depth"].int ?? 2,
      limit: params["limit"].int ?? (method == "graph.search" ? 50 : 500),
      edgeLimit: params["edgeLimit"].int ?? 1500, cursor: params["cursor"].string,
      level: params["level"].string ?? "module", target: params["target"].string)
  }
}
