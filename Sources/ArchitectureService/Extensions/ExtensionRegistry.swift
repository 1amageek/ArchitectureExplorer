import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation

extension ExtensionRuntime {
  func registry(_ method: String, params: JSONValue, peer: ConnectionPeer?, credential: String?) async throws -> JSONValue {
    try await load()
    switch method {
    case "extensions.register":
      guard let peer else { throw failure("AUTHENTICATION_REQUIRED", "Provider registration requires an OS peer.") }
      let manifest = try ExtensionRules.manifest(params["manifest"])
      guard params["profile"] == .null, params["scope"] == .null || params["scope"] == .string("workspace") else { throw failure("UNSUPPORTED_CAPABILITY", "Only an explicitly negotiated profile and workspace scope are supported.") }
      let digest = CanonicalJSON.digest(try CanonicalJSON.encode(manifest))
      if bundledProvider?.matches(peer, manifest: manifest) == true,
         let grant = try await companionGrant(peer: peer, manifest: manifest) {
        return try openSession(grant, peer: peer)
      }
      if let grant = state!.grants.values.first(where: { $0.bundled != true && $0.binaryDigest == peer.binaryDigest && $0.codeIdentity == peer.codeIdentity && $0.manifest == manifest && !$0.disabled }), params["resumeCredential"].string == grant.resumeCredential {
        return try openSession(grant, peer: peer)
      }
      pending = pending.filter { $0.value.expiresAt > now() && state!.grants[$0.key]?.disabled != false }
      let id = CanonicalJSON.identity(peer.auditIdentity + ":" + digest)
      guard pending.count < 64 || pending[id] != nil else { throw failure("RESOURCE_LIMIT", "Approval queue exceeded.") }
      pending[id] = Pending(peer: peer, manifest: manifest, expiresAt: now() + 300)
      // Credentials are returned only to the approved live peer, never to the approving browser.
      if let grant = state!.grants[id], grant.manifest == manifest, !grant.disabled, grant.binaryDigest == peer.binaryDigest {
        return try await registry(method, params: .object(["manifest": params["manifest"], "resumeCredential": .string(grant.resumeCredential)]), peer: peer, credential: nil)
      }
      throw ArchitectureError("APPROVAL_REQUIRED", "Host approval required for registration \(id).", exitCode: 5)
    case "extensions.pending":
      try requireHost(peer)
      pending = pending.filter { $0.value.expiresAt > now() && state!.grants[$0.key]?.disabled != false }
      return .array(try pending.sorted { $0.key < $1.key }.map { .object(["id": .string($0.key), "peer": try JSONValue.encode($0.value.peer), "manifest": try JSONValue.encode($0.value.manifest)]) })
    case "extensions.approve":
      try requireHost(peer)
      guard let id = params["id"].string, let item = pending[id], item.expiresAt > now(), state!.grants.count < 16 || state!.grants[id] != nil else { throw failure("APPROVAL_EXPIRED", "Pending approval unavailable or budget exceeded.") }
      let permissions = try params["permissions"].decode([ExtensionPermission].self)
      guard Set(permissions).isSubset(of: Set(item.manifest.requestedPermissions)) else { throw failure("POLICY_DENIED", "Cannot grant unrequested permission.") }
      var value = state!
      for other in value.grants.keys where other != id && value.grants[other]!.manifest.extensionID == item.manifest.extensionID { value.grants[other]!.disabled = true; sessions = sessions.filter { $0.value.grantID != other } }
      value.grants[id] = ExtensionState.Grant(id: id, manifest: item.manifest, binaryDigest: item.peer.binaryDigest, codeIdentity: item.peer.codeIdentity, executable: item.peer.executable, resumeCredential: UUID().uuidString + UUID().uuidString, permissions: permissions)
      try await persist(value)
      return .object(["approved": .bool(true), "id": .string(id)])
    case "extensions.heartbeat":
      let (grant, session) = try principal(peer, credential: credential)
      return .object(["registrationID": .string(grant.id), "sessionID": .string(session.id), "expiresAt": .number(session.expiresAt)])
    case "extensions.permissions":
      try requireHost(peer)
      guard let id = params["id"].string, var grant = state!.grants[id] else { throw failure("INVALID_ARGUMENT", "Unknown registration.") }
      let permissions = try params["permissions"].decode([ExtensionPermission].self)
      guard Set(permissions).isSubset(of: Set(grant.permissions)) else { throw failure("APPROVAL_REQUIRED", "Permission expansion requires a new approval.") }
      grant.permissions = permissions
      var value = state!; value.grants[id] = grant
      try await persist(value)
      sessions = sessions.filter { $0.value.grantID != id }
      return try publicGrant(grant)
    case "extensions.disconnect", "extensions.unregister":
      let id: String
      if host(peer) { id = params["id"].string ?? "" } else { id = try principal(peer, credential: credential).0.id }
      sessions = sessions.filter { $0.value.grantID != id }
      var value = state!
      for key in value.dispatches.keys where value.dispatches[key]!.intent.registrationID == id && !["completed", "failed", "cancelled", "rejected"].contains(value.dispatches[key]!.state) { value.dispatches[key]!.lastObserved = value.dispatches[key]!.state; value.dispatches[key]!.state = "unknown" }
      for key in value.runs.keys where value.runs[key]!.providerID == value.grants[id]?.manifest.extensionID && !value.runs[key]!.committed { value.runs[key]!.contributions = [:]; value.runs[key]!.sessionID = "" }
      if method == "extensions.unregister" { value.grants[id]?.disabled = true }
      try await persist(value)
      return .object(["disconnected": .bool(true)])
    case "extensions.list":
      if !host(peer) { let (grant, _) = try principal(peer, credential: credential); return .array([try publicGrant(grant)]) }
      return .array(try state!.grants.values.sorted { $0.id < $1.id }.map { try publicGrant($0) })
    default: throw failure("UNSUPPORTED_CAPABILITY", "Unknown extension registry method.")
    }
  }
  private func companionGrant(peer: ConnectionPeer, manifest: ExtensionManifest) async throws -> ExtensionState.Grant? {
    let id = CanonicalJSON.identity(workspaceID + ":bundled-provider:" + manifest.extensionID)
    let previous = state!.grants[id]
    guard previous?.disabled != true else { return nil }
    if let previous, previous.codeIdentity == peer.codeIdentity, previous.binaryDigest == peer.binaryDigest,
       previous.executable == peer.executable, previous.manifest == manifest { return previous }

    let legacy = state!.grants.values.filter { $0.manifest.extensionID == manifest.extensionID && $0.bundled != true }
    let activeLegacy = legacy.first { !$0.disabled }
    guard previous != nil || legacy.isEmpty || activeLegacy != nil else { return nil }
    let permissions = (previous ?? activeLegacy).map { grant in
      manifest.requestedPermissions.filter(grant.permissions.contains)
    } ?? manifest.requestedPermissions
    let grant = ExtensionState.Grant(id: id, manifest: manifest, binaryDigest: peer.binaryDigest,
      codeIdentity: peer.codeIdentity, executable: peer.executable, resumeCredential: UUID().uuidString + UUID().uuidString,
      permissions: permissions, bundled: true)
    var value = state!
    for other in value.grants.keys where other != id && value.grants[other]!.manifest.extensionID == manifest.extensionID {
      value.grants[other]!.disabled = true
    }
    value.grants[id] = grant
    try await persist(value)
    sessions = sessions.filter { state!.grants[$0.value.grantID]?.disabled == false && $0.value.grantID != id }
    pending = pending.filter { $0.value.manifest.extensionID != manifest.extensionID }
    return grant
  }
  private func openSession(_ grant: ExtensionState.Grant, peer: ConnectionPeer) throws -> JSONValue {
    sessions = sessions.filter { $0.value.expiresAt > now() }
    guard sessions.count < 64 else { throw failure("RESOURCE_LIMIT", "Session budget exceeded.") }
    sessions = sessions.filter { $0.value.grantID != grant.id }
    pending[grant.id] = nil
    let session = Session(id: UUID().uuidString, grantID: grant.id, peer: peer.auditIdentity, expiresAt: now() + 15, window: now())
    let token = UUID().uuidString + UUID().uuidString
    sessions[token] = session
    return try JSONValue.encode(ExtensionRegistration(id: grant.id, providerID: grant.manifest.extensionID,
      sessionID: session.id, credential: token, resumeCredential: grant.resumeCredential,
      grantedPermissions: grant.permissions, expiresAt: session.expiresAt))
  }
  func publicGrant(_ grant: ExtensionState.Grant) throws -> JSONValue {
    let connected = sessions.values.contains { $0.grantID == grant.id && $0.expiresAt > now() }
    return .object(["id": .string(grant.id), "providerID": .string(grant.manifest.extensionID), "manifest": try JSONValue.encode(grant.manifest), "permissions": try JSONValue.encode(grant.permissions), "connected": .bool(connected && !grant.disabled), "disabled": .bool(grant.disabled), "executable": .string(grant.executable), "binaryDigest": .string(grant.binaryDigest)])
  }
}
