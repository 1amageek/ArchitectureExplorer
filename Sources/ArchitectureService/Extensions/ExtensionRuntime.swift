import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import ArchitectureStore
import Foundation

actor ExtensionRuntime {
  struct Session: Sendable {
    let id: String
    let grantID: String
    let peer: String
    var expiresAt: Double
    var window: Double
    var requests = 0
  }
  struct Pending: Sendable {
    let peer: ConnectionPeer
    let manifest: ExtensionManifest
    let expiresAt: Double
  }
  let workspaceID: String
  let store: any GraphStore
  let hostDigests: Set<String>
  let epoch = UUID().uuidString
  let now: @Sendable () -> Double
  var state: ExtensionState?
  var writing = false
  var sessions: [String: Session] = [:]
  var pending: [String: Pending] = [:]
  var prepared: [String: ActionIntent] = [:]
  struct LeaseOwner: Sendable { let session: String; let expiresAt: Double }
  var leaseOwners: [String: LeaseOwner] = [:]
  var stopped = false

  init(workspaceID: String, store: any GraphStore, hostDigests: Set<String>, now: @escaping @Sendable () -> Double = ExtensionRuntime.monotonicTime()) {
    self.workspaceID = workspaceID; self.store = store; self.hostDigests = hostDigests; self.now = now
  }
  nonisolated static func monotonicTime() -> @Sendable () -> Double {
    let clock = ContinuousClock(), start = ContinuousClock.now, wall = Date().timeIntervalSince1970
    return { let elapsed = start.duration(to: clock.now).components; return wall + Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18 }
  }
  func host(_ peer: ConnectionPeer?) -> Bool { peer == nil || hostDigests.contains(peer!.binaryDigest) }
  func load() async throws {
    guard !stopped else { throw failure("SESSION_EXPIRED", "Extension host is shut down.") }
    if state != nil { return }
    // First readers share initialization; only competing mutations receive busy.
    while writing { try await Task.sleep(for: .milliseconds(5)) }
    guard !stopped else { throw failure("SESSION_EXPIRED", "Extension host is shut down.") }
    if state != nil { return }
    guard !writing else { throw failure("RESOURCE_BUSY", "Extension persistence is busy.") }
    writing = true; defer { writing = false }
    let raw = try await store.extensionState()
    guard case .object = raw else { throw failure("EXTENSION_STATE_CORRUPT", "Persisted extension state is not a document; core queries remain available.") }
    var value = raw.object.isEmpty ? ExtensionState() : try raw.decode(ExtensionState.self)
    for key in value.dispatches.keys where !["completed", "failed", "cancelled", "rejected", "expired"].contains(value.dispatches[key]!.state) { value.dispatches[key]!.lastObserved = value.dispatches[key]!.state; value.dispatches[key]!.state = "unknown" }
    for key in value.runs.keys where !value.runs[key]!.committed { value.runs[key]!.contributions = [:]; value.runs[key]!.sessionID = "" }
    try await store.replaceExtensionState(try JSONValue.encode(value))
    state = value
  }
  func persist(_ candidate: ExtensionState, provider: String = "host", cause: String = "") async throws {
    guard !stopped else { throw failure("SESSION_EXPIRED", "Extension host is shut down.") }
    guard !writing else { throw failure("RESOURCE_BUSY", "Extension persistence is busy.") }
    writing = true; defer { writing = false }
    var value = candidate
    value.revision += 1; value.originProviderID = provider; value.causationID = cause
    try await store.replaceExtensionState(try JSONValue.encode(value))
    state = value
  }
  func requireHost(_ peer: ConnectionPeer?) throws { guard host(peer) else { throw failure("POLICY_DENIED", "Only the authenticated host user may perform this operation.") } }
  func principal(_ peer: ConnectionPeer?, credential: String?, permission: ExtensionPermission? = nil, admit: Bool = true) throws -> (ExtensionState.Grant, Session) {
    guard let peer, let credential, var session = sessions[credential], session.peer == peer.auditIdentity, session.expiresAt > now(), let grant = state?.grants[session.grantID], !grant.disabled, grant.binaryDigest == peer.binaryDigest, grant.codeIdentity == peer.codeIdentity else { throw failure("SESSION_EXPIRED", "A peer-bound approved Provider session is required.") }
    if let permission { guard grant.permissions.contains(permission) else { throw failure("POLICY_DENIED", "Permission not granted: \(permission.rawValue)") } }
    if !admit { return (grant, session) }
    if now() - session.window >= 1 { session.window = now(); session.requests = 0 }
    guard session.requests < 64 else { throw failure("RESOURCE_LIMIT", "Provider request rate exceeded.") }
    session.requests += 1; session.expiresAt = now() + 15; sessions[credential] = session
    return (grant, session)
  }
  func authorize(_ method: String, peer: ConnectionPeer?, credential: String?, admit: Bool = true) async throws -> String? {
    if host(peer) { return nil }
    try await load()
    let permission: ExtensionPermission
    if ["canvas.list", "canvas.get", "canvas.export"].contains(method) { permission = .canvasRead }
    else if method.hasPrefix("canvas.") {
      _ = try principal(peer, credential: credential, permission: .canvasRead, admit: false)
      permission = .canvasControl
    }
    else if ["source.read", "inputs.read"].contains(method) { permission = .inputsRead }
    else if method == "events.poll" { permission = .eventsSubscribe }
    else if ["workspace.status", "graph.overview", "graph.children", "graph.node", "graph.neighbors", "graph.search", "graph.path", "graph.impact", "graph.cfg", "graph.diff", "graph.explain", "graph.evidence", "graph.annotations", "graph.capabilities", "graph.export", "extensionGraphs.list", "graph.scan", "inputs.acquire", "inputs.release", "inputs.renew", "inputs.manifest"].contains(method) { permission = .graphRead }
    else { throw failure("POLICY_DENIED", "Provider cannot invoke host mutation: \(method)") }
    return try principal(peer, credential: credential, permission: permission, admit: admit).1.id
  }
  func ownLease(_ id: String, session: String, expiresAt: Double? = nil) {
    leaseOwners = leaseOwners.filter { $0.value.expiresAt > now() }
    leaseOwners[id] = LeaseOwner(session: session, expiresAt: expiresAt ?? now() + 300)
  }
  func releaseLease(_ id: String) { leaseOwners[id] = nil }
  func checkLease(_ id: String, owner: String?) throws {
    guard owner == nil || leaseOwners[id]?.session == owner && (leaseOwners[id]?.expiresAt ?? 0) > now() else { throw failure("POLICY_DENIED", "Input lease belongs to another session.") }
  }
  func failure(_ code: String, _ message: String) -> ArchitectureError { ArchitectureError(code, message, exitCode: ["RESOURCE_BUSY", "RESOURCE_LIMIT"].contains(code) ? 6 : 5) }
  func shutdown() async {
    stopped = true; sessions.removeAll(); pending.removeAll(); prepared.removeAll(); leaseOwners.removeAll()
    // Accepted persistence finishes before owner shutdown, even when the caller is cancelled.
    while writing {
      let pause = Task { try await Task.sleep(for: .milliseconds(5)) }
      do { try await pause.value } catch { await Task.yield() }
    }
  }
  func event() async throws -> JSONValue {
    try await load()
    return .object(["extensionSequence": .number(Double(state!.revision)), "originProviderID": .string(state!.originProviderID), "causationID": .string(state!.causationID), "category": .string("extensions"), "sessionRevision": .string(CanonicalJSON.identity(sessions.values.filter { $0.expiresAt > now() }.map(\.id).sorted().joined(separator: ":")))])
  }
}
