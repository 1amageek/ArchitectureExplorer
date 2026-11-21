import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation

extension ExtensionRuntime {
  func isCancellation(_ params: JSONValue, peer: ConnectionPeer?) async throws -> Bool {
    try requireHost(peer); try await load()
    return state!.grants[params["registrationID"].string ?? ""]?.manifest.actions.first(where: { $0.id == params["actionID"].string })?.operation == "cancel"
  }
  func action(_ method: String, params: JSONValue, peer: ConnectionPeer?, credential: String?, snapshot: Snapshot?) async throws -> JSONValue {
    try await load()
    if method == "actions.prepare" {
      try requireHost(peer)
      guard let id = params["registrationID"].string, let grant = state!.grants[id], !grant.disabled, let definition = grant.manifest.actions.first(where: { $0.id == params["actionID"].string }), let session = sessions.values.first(where: { $0.grantID == id && $0.expiresAt > now() }) else { throw failure("PROVIDER_DISCONNECTED", "Action requires a connected approved Provider.") }
      guard grant.permissions.contains(.actionsReceive) else { throw failure("POLICY_DENIED", "Action delivery permission missing.") }
      try ExtensionRules.schema(definition.inputSchema, value: params["arguments"])
      let binding = try params["binding"].decode(ExtensionBinding.self)
      if definition.operation != "cancel" {
        guard let snapshot else { throw failure("INPUT_CHANGED", "Execution requires retained input metadata.") }
        try validate(binding, snapshot: snapshot)
      }
      prepared = prepared.filter { $0.value.deadline > now() }
      guard prepared.count < 64 else { throw failure("RESOURCE_LIMIT", "Confirmation budget exceeded.") }
      if definition.operation == "cancel" {
        guard let parent = state!.dispatches.values.first(where: { $0.intent.requestID == params["arguments"]["requestID"].string }), parent.intent.registrationID == grant.id, parent.intent.binding == binding, parent.receipt?.jobID == params["arguments"]["jobID"].string, parent.runID == params["arguments"]["runID"].string, !["completed", "failed", "cancelled"].contains(parent.state) else { throw failure("INVALID_ARGUMENT", "Cancel target is not an active bound job.") }
      }
      let token = epoch + ":" + String(Int(now() + 3900)) + ":" + UUID().uuidString + UUID().uuidString
      let intent = try ActionIntent(requestID: UUID().uuidString, registrationID: id, sessionID: session.id, providerID: grant.manifest.extensionID, actionID: definition.id, actionDefinitionDigest: CanonicalJSON.digest(try CanonicalJSON.encode(definition)), inputSchemaID: definition.inputSchemaID, effect: definition.effect, binding: binding, arguments: params["arguments"], requestedAt: now(), deadline: now() + 300, idempotencyKey: epoch + ":" + UUID().uuidString, authorizationToken: token)
      prepared[token] = intent
      return .object(["intent": try JSONValue.encode(intent), "title": .string(definition.title), "provider": .string(grant.manifest.displayName), "executable": .string(grant.executable), "requiresConfirmation": .bool(true)])
    }
    if method == "actions.confirm" {
      try requireHost(peer)
      guard let token = params["token"].string else { throw failure("CONFIRMATION_REQUIRED", "Host confirmation token is required.") }
      let tokenParts = token.split(separator: ":")
      if tokenParts.count == 3, let expiration = Double(tokenParts[1]), expiration <= now() { throw failure("IDEMPOTENCY_KEY_EXPIRED", "Confirmation retention expired.") }
      guard tokenParts.first.map(String.init) == epoch else { throw failure("SESSION_EXPIRED", "Confirmation belongs to another host epoch.") }
      if let old = state!.dispatches.values.first(where: { $0.intent.authorizationToken == token }) {
        guard old.intent.deadline + 3600 > now() else { throw failure("IDEMPOTENCY_KEY_EXPIRED", "Dispatch retention deadline passed.") }
        guard let grant = state!.grants[old.intent.registrationID], !grant.disabled, grant.permissions.contains(.actionsReceive), sessions.values.contains(where: { $0.id == old.intent.sessionID && $0.expiresAt > now() }) else { throw failure("SESSION_EXPIRED", "Confirmation belongs to an inactive session.") }
        _ = try boundDefinition(old.intent, grant: grant)
        guard old.intent.requestFingerprint == params["requestFingerprint"].string else { throw failure("IDEMPOTENCY_CONFLICT", "Confirmation fingerprint changed.") }
        return try JSONValue.encode(old)
      }
      guard let intent = prepared[token], intent.deadline > now(), intent.requestFingerprint == params["requestFingerprint"].string, intent.requestFingerprint == (try intent.verifiedFingerprint()), let grant = state!.grants[intent.registrationID], !grant.disabled, grant.permissions.contains(.actionsReceive), sessions.values.contains(where: { $0.id == intent.sessionID && $0.expiresAt > now() }) else { throw failure("CONFIRMATION_REQUIRED", "Expired or modified confirmation binding.") }
      let definition = try boundDefinition(intent, grant: grant)
      let currentDigest = try snapshot.map { try InputManifest(snapshot: $0).digest }
      guard definition.operation == "cancel" || currentDigest == intent.binding.inputManifestDigest else { throw failure("INPUT_CHANGED", "Input changed after confirmation preparation.") }
      var value = state!
      value.dispatches = value.dispatches.filter { $0.value.intent.deadline + 3600 > now() }
      guard value.dispatches.count < 512 else { throw failure("RESOURCE_LIMIT", "Dispatch retention budget exceeded.") }
      var dispatch = ExtensionState.Dispatch(intent: intent)
      if definition.operation == "cancel", let target = intent.arguments["requestID"].string, let key = value.dispatches.first(where: { $0.value.intent.requestID == target })?.key {
        guard let parent = value.dispatches[key], !["completed", "failed", "cancelled", "rejected", "expired"].contains(parent.state), parent.intent.registrationID == grant.id, parent.intent.binding == intent.binding, parent.receipt?.jobID == intent.arguments["jobID"].string, parent.runID == intent.arguments["runID"].string else { throw failure("JOB_ALREADY_TERMINAL", "Cancel target completed or changed after confirmation preparation.") }
        dispatch.targetRequestID = target; value.dispatches[key]!.lastObserved = value.dispatches[key]!.state; value.dispatches[key]!.state = "cancelling"; value.dispatches[key]!.cancelRequested = true
      }
      value.dispatches[intent.idempotencyKey] = dispatch
      try await persist(value, provider: grant.manifest.extensionID, cause: intent.requestID)
      prepared[token] = nil
      return try JSONValue.encode(dispatch)
    }
    let (grant, session) = try principal(peer, credential: credential, permission: .actionsReceive)
    var value = state!
    switch method {
    case "actions.next":
      guard let key = value.dispatches.keys.sorted().first(where: { value.dispatches[$0]!.intent.registrationID == grant.id && value.dispatches[$0]!.intent.sessionID == session.id && value.dispatches[$0]!.state == "queued" && value.dispatches[$0]!.intent.deadline > now() }) else { return .null }
      value.dispatches[key]!.state = "delivered"; value.dispatches[key]!.lastObserved = "delivered"
      let intent = value.dispatches[key]!.intent
      try await persist(value, provider: grant.manifest.extensionID, cause: intent.requestID)
      return try JSONValue.encode(intent)
    case "actions.reconcile":
      return .array(try value.dispatches.values.filter { $0.intent.registrationID == grant.id && ["unknown", "delivered", "accepted", "cancelling"].contains($0.state) }.map { try JSONValue.encode($0) })
    case "actions.receipt":
      guard let key = params["idempotencyKey"].string, var dispatch = value.dispatches[key], dispatch.intent.registrationID == grant.id, dispatch.intent.requestFingerprint == params["requestFingerprint"].string, dispatch.state != "queued" else { throw failure("IDEMPOTENCY_CONFLICT", "Receipt has no matching delivered request.") }
      let receipt = try params["receipt"].decode(ActionReceipt.self)
      guard receipt.accepted ? receipt.jobID?.isEmpty == false && receipt.reason == nil : receipt.jobID == nil && receipt.reason?.isEmpty == false else { throw failure("INVALID_ARGUMENT", "Receipt must be accepted(jobID) or rejected(reason).") }
      if let previous = dispatch.receipt { guard previous == receipt else { throw failure("IDEMPOTENCY_CONFLICT", "Initial receipt is immutable.") }; return try JSONValue.encode(previous) }
      dispatch.receipt = receipt; dispatch.state = receipt.accepted ? "accepted" : "rejected"; dispatch.lastObserved = dispatch.state; value.dispatches[key] = dispatch
      try await persist(value, provider: grant.manifest.extensionID, cause: dispatch.intent.requestID)
      return try JSONValue.encode(receipt)
    case "actions.state":
      guard let request = params["requestID"].string, let key = value.dispatches.first(where: { $0.value.intent.requestID == request && $0.value.intent.registrationID == grant.id })?.key, var dispatch = value.dispatches[key], let job = params["jobID"].string, dispatch.receipt?.accepted == true, dispatch.receipt?.jobID == job, dispatch.runID == nil || dispatch.runID == params["runID"].string, let revision = params["revision"].int, revision > 0, let status = params["state"].string, ["running", "completed", "failed", "cancelled", "unknown"].contains(status), let runID = params["runID"].string, let run = value.runs[runID], run.providerID == grant.manifest.extensionID, run.registrationID == grant.id, run.binding == dispatch.intent.binding else { throw failure("INVALID_ARGUMENT", "Job state must match an accepted request/run/input.") }
      if revision <= dispatch.jobRevision { return try JSONValue.encode(dispatch) }
      guard !["completed", "failed", "cancelled"].contains(dispatch.state) || dispatch.state == status else { throw failure("PROTOCOL_MISMATCH", "Conflicting terminal job state.") }
      dispatch.jobRevision = revision; dispatch.runID = runID; dispatch.observingSessionID = session.id
      dispatch.state = dispatch.cancelRequested && status == "running" ? "cancelling" : status
      dispatch.lastObserved = dispatch.state; value.dispatches[key] = dispatch
      try await persist(value, provider: grant.manifest.extensionID, cause: request)
      return try JSONValue.encode(dispatch)
    default: throw failure("UNSUPPORTED_CAPABILITY", "Unknown action method.")
    }
  }
  func boundDefinition(_ intent: ActionIntent, grant: ExtensionState.Grant) throws -> ExtensionActionDefinition {
    guard let definition = grant.manifest.actions.first(where: { $0.id == intent.actionID }), intent.actionDefinitionDigest == CanonicalJSON.digest(try CanonicalJSON.encode(definition)), intent.inputSchemaID == definition.inputSchemaID, intent.effect == definition.effect else { throw failure("INPUT_CHANGED", "Approved operation definition changed.") }
    try ExtensionRules.schema(definition.inputSchema, value: intent.arguments)
    return definition
  }
}
