import ArchitectureCore
import ArchitectureExtensions
import ArchitectureIR
import Foundation

extension ExtensionRuntime {
  func publication(_ method: String, params: JSONValue, peer: ConnectionPeer?, credential: String?, snapshot: Snapshot?) async throws -> JSONValue {
    try await load()
    let (grant, session) = try principal(peer, credential: credential, permission: .runsWrite)
    var value = state!
    if method == "runs.begin" {
      guard let runID = params["runID"].string, ExtensionRules.validID(runID), let scope = params["scope"].string, ExtensionRules.validID(scope), let setID = params["contributionSetID"].string, ExtensionRules.validID(setID), let snapshot else { throw failure("INVALID_ARGUMENT", "Run needs an identity, scope, contribution set and retained snapshot.") }
      let kinds = params["contributionKinds"].array.compactMap(\.string).sorted()
      let views = params["viewIDs"].array.compactMap(\.string).sorted()
      guard kinds.count <= 3, Set(kinds).count == kinds.count, Set(kinds).isSubset(of: ["annotation", "graph", "view"]), views.count <= 16, Set(views).count == views.count, Set(views).isSubset(of: Set(grant.manifest.views.map(\.id))), !kinds.contains("view") || !views.isEmpty else { throw failure("INVALID_ARGUMENT", "Declare bounded contribution kinds and registered view IDs before work.") }
      for kind in kinds {
        let permission: ExtensionPermission = kind == "annotation" ? .annotationsWrite : kind == "graph" ? .graphsWrite : .viewsWrite
        guard grant.permissions.contains(permission) else { throw failure("POLICY_DENIED", "Run contribution permission missing.") }
      }
      let binding = try params["binding"].decode(ExtensionBinding.self)
      try validate(binding, snapshot: snapshot)
      let id = grant.manifest.extensionID + ":" + runID
      let slot = CanonicalJSON.identity(workspaceID + ":" + grant.manifest.extensionID + ":" + scope + ":" + setID)
      if var run = value.runs[id] {
        guard run.registrationID == grant.id, run.slot == slot, run.binding == binding, run.contributionKinds == kinds, run.viewIDs == views else { throw failure("IDEMPOTENCY_CONFLICT", "Run identity has different inputs/scope.") }
        if run.committed { return try JSONValue.encode(run) }
        guard run.expiresAt > now() else { throw failure("PUBLICATION_EXPIRED", "Run admission expired.") }
        if run.sessionID != session.id { run.sessionID = session.id; run.publicationID = UUID().uuidString; run.manifest = nil; run.contributions = [:]; value.runs[id] = run; try await persist(value, provider: grant.manifest.extensionID, cause: id) }
        return try JSONValue.encode(run)
      }
      guard value.runs.count < 128, (value.generations[slot] ?? 0) < Int.max - 1 else { throw failure("RESOURCE_LIMIT", "Run retention/generation budget exceeded.") }
      let generation = (value.generations[slot] ?? 0) + 1
      let run = ExtensionState.Run(id: id, providerID: grant.manifest.extensionID, registrationID: grant.id, slot: slot, binding: binding, generation: generation, contributionKinds: kinds, viewIDs: views, publicationID: UUID().uuidString, sessionID: session.id, expiresAt: now() + 3600, providerVersion: grant.manifest.version)
      value.generations[slot] = generation; value.runs[id] = run
      try await persist(value, provider: grant.manifest.extensionID, cause: id)
      return try JSONValue.encode(run)
    }
    guard let id = params["runID"].string, var run = value.runs[id], run.providerID == grant.manifest.extensionID, run.registrationID == grant.id, run.sessionID == session.id, run.expiresAt > now(), params["publicationID"].string == run.publicationID else { throw failure("PUBLICATION_EXPIRED", "Run/publication/session binding is unavailable.") }
    guard !run.committed || method == "runs.commit" else { throw failure("PUBLICATION_REQUIRED", "Committed publications are immutable.") }
    guard run.completion == "pending" || method == "runs.commit" else { throw failure("PUBLICATION_EXPIRED", "A finished attempt cannot be reopened.") }
    switch method {
    case "runs.prepare":
      let manifest = try params["manifest"].decode(PublicationManifest.self)
      guard manifest.entries.count <= 64, manifest.entries.keys.allSatisfy({ $0.hasPrefix(grant.manifest.extensionID + ":") }), manifest.entries.values.allSatisfy({ $0.count == 64 }) else { throw failure("RESOURCE_LIMIT", "Invalid publication manifest budget/namespace.") }
      if let diagnostic = manifest.attemptDiagnostic {
        guard (1...1024).contains(diagnostic.utf8.count) else { throw failure("INVALID_PUBLICATION", "Attempt diagnostic exceeds its text budget.") }
      }
      if let previous = run.manifest { guard previous == manifest else { throw failure("IDEMPOTENCY_CONFLICT", "Publication manifest is immutable.") } }
      guard !run.committed else { throw failure("PUBLICATION_REQUIRED", "Committed publications are immutable.") }
      run.manifest = manifest
    case "annotations.replaceBatch", "extensionGraphs.replace", "views.replace":
      guard !run.committed, let manifest = run.manifest else { throw failure("PUBLICATION_REQUIRED", "Prepare an immutable publication manifest first.") }
      let contributions = try params["contributions"].decode([ExtensionContribution].self)
      guard contributions.count <= 64 else { throw failure("RESOURCE_LIMIT", "Contribution batch exceeds budget.") }
      let expected = method == "annotations.replaceBatch" ? "annotation" : method == "extensionGraphs.replace" ? "graph" : "view"
      let permission: ExtensionPermission = expected == "annotation" ? .annotationsWrite : expected == "graph" ? .graphsWrite : .viewsWrite
      guard grant.permissions.contains(permission) else { throw failure("POLICY_DENIED", "Contribution permission missing.") }
      for contribution in contributions {
        guard contribution.kind == expected, run.contributionKinds.contains(expected), expected != "view" || run.viewIDs.contains(String(contribution.id.dropFirst(grant.manifest.extensionID.count + 1))), manifest.entries[contribution.id] == (try contribution.digest) else { throw failure("INVALID_PUBLICATION", "Contribution differs from its manifest.") }
        try ExtensionRules.contribution(contribution, provider: grant.manifest, binding: run.binding)
        run.contributions[contribution.id] = contribution
      }
      guard try CanonicalJSON.encode(run.contributions).count <= 2 * 1024 * 1024 else { throw failure("RESOURCE_LIMIT", "Publication exceeds 2 MiB.") }
    case "runs.commit":
      guard let manifest = run.manifest else { throw failure("PUBLICATION_REQUIRED", "Prepare the publication before commit.") }
      let digest = CanonicalJSON.digest(try CanonicalJSON.encode(manifest))
      guard params["manifestDigest"].string == digest else { throw failure("IDEMPOTENCY_CONFLICT", "Commit manifest digest mismatch.") }
      if run.committed { guard params["completion"].string == "complete" else { throw failure("IDEMPOTENCY_CONFLICT", "Committed completion cannot change.") }; return .object(["runID": .string(id), "publicationID": .string(run.publicationID), "committed": .bool(true)]) }
      let completion = params["completion"].string ?? "unknown"
      guard ["complete", "partial", "failed", "cancelled", "unknown"].contains(completion) else { throw failure("INVALID_ARGUMENT", "Unknown completion state.") }
      if run.completion != "pending" { guard run.completion == completion else { throw failure("IDEMPOTENCY_CONFLICT", "Run completion is immutable.") }; return try JSONValue.encode(run) }
      run.completion = completion
      if completion == "complete" {
        guard Set(run.contributions.keys) == Set(manifest.entries.keys) else { throw failure("PUBLICATION_INCOMPLETE", "Publication pages are incomplete.") }
        for contribution in run.contributions.values {
          let permission: ExtensionPermission = contribution.kind == "annotation" ? .annotationsWrite : contribution.kind == "graph" ? .graphsWrite : .viewsWrite
          guard grant.permissions.contains(permission) else { throw failure("POLICY_DENIED", "Publication permission revoked.") }
        }
        if let previous = value.heads[run.slot], let head = value.runs[previous], head.generation > run.generation { throw failure("PUBLICATION_SUPERSEDED", "A newer complete publication owns this slot; historySaved=false.") }
        run.committed = true; run.manifestDigest = digest; value.heads[run.slot] = id
      } else { run.contributions = [:] }
    case "runs.abort": run.completion = "failed"; run.contributions = [:]
    default: throw failure("UNSUPPORTED_CAPABILITY", "Unknown publication method.")
    }
    value.runs[id] = run
    try await persist(value, provider: grant.manifest.extensionID, cause: id)
    return .object(["runID": .string(id), "publicationID": .string(run.publicationID), "committed": .bool(run.committed), "completion": .string(run.completion)])
  }
  func validate(_ binding: ExtensionBinding, snapshot: Snapshot) throws {
    let manifest = InputManifest(snapshot: snapshot)
    guard binding.workspaceID == workspaceID, binding.snapshotID == snapshot.id, binding.inputManifestDigest == (try manifest.digest), binding.entityIDs.count <= 500, binding.factIDs.count <= 1500, Set(binding.entityIDs).isSubset(of: Set(snapshot.entities.map(\.id))), Set(binding.factIDs).isSubset(of: Set(snapshot.facts.map(\.id))) else { throw failure("INPUT_CHANGED", "Binding does not match retained inputs and source identities.") }
  }
  func visible(snapshot: Snapshot, cursor: String? = nil) async throws -> JSONValue {
    try await load()
    let current = try InputManifest(snapshot: snapshot).digest
    let publications = try state!.heads.values.sorted().compactMap { id -> JSONValue? in
      guard let run = state!.runs[id] else { return nil }
      let provider = state!.grants[run.registrationID]
      let known = Set(run.binding.entityIDs).isSubset(of: Set(snapshot.entities.map(\.id))) && Set(run.binding.factIDs).isSubset(of: Set(snapshot.facts.map(\.id)))
      let applicability = !known ? "unmatched" : run.binding.snapshotID == snapshot.id && run.binding.inputManifestDigest == current ? "unknown" : "stale"
      let version = run.providerVersion ?? provider?.manifest.version
      return .object(["runID": .string(run.id), "publicationID": .string(run.publicationID), "generation": .number(Double(run.generation)), "providerID": .string(run.providerID), "applicability": .string(applicability), "binding": try JSONValue.encode(run.binding), "contributions": try JSONValue.encode(run.contributions.values.sorted { $0.id < $1.id }), "providerVersion": version.map(JSONValue.string) ?? .null, "provider": provider.map { .string($0.manifest.displayName) } ?? .string(run.providerID)])
    }
    let registrations = try state!.grants.values.sorted { $0.id < $1.id }.map { try publicGrant($0) }
    let actions = try state!.dispatches.values.sorted { $0.intent.requestID < $1.intent.requestID }.map { item -> JSONValue in
      let connected = sessions.values.contains { $0.grantID == item.intent.registrationID && ($0.id == item.intent.sessionID || $0.id == item.observingSessionID) && $0.expiresAt > now() }
      let terminal = ["completed", "failed", "cancelled", "rejected", "expired"].contains(item.state)
      return .object(["requestID": .string(item.intent.requestID), "providerID": .string(item.intent.providerID), "actionID": .string(item.intent.actionID), "state": .string(connected || terminal ? item.state : "unknown"), "lastObserved": .string(item.lastObserved), "receipt": try JSONValue.encode(item.receipt), "runID": item.runID.map(JSONValue.string) ?? .null, "binding": try JSONValue.encode(item.intent.binding)])
    }
    let attempts = state!.runs.values.sorted { $0.id < $1.id }.map { run in
      var record: [String: JSONValue] = ["runID": .string(run.id), "slot": .string(run.slot), "completion": .string(run.completion), "generation": .number(Double(run.generation))]
      if run.binding.snapshotID == snapshot.id, ["partial", "failed", "cancelled", "unknown"].contains(run.completion), let diagnostic = run.manifest?.attemptDiagnostic {
        record["diagnostic"] = .string(diagnostic)
      }
      return JSONValue.object(record)
    }
    let records = registrations.map { ("registrations", $0) } + actions.map { ("actions", $0) } + publications.map { ("publications", $0) } + attempts.map { ("attempts", $0) }
    let prefix = CanonicalJSON.identity(snapshot.id + ":" + String(state!.revision))
    var offset = 0
    if let cursor {
      let parts = cursor.split(separator: ":")
      guard parts.count == 2, String(parts[0]) == prefix, let index = Int(parts[1]), (0...records.count).contains(index) else { throw failure("CURSOR_EXPIRED", "External results changed; resync from the first page.") }
      offset = index
    }
    var page: [String: [JSONValue]] = ["registrations": [], "actions": [], "publications": [], "attempts": []]
    var used = 0
    while offset < records.count {
      let (kind, record) = records[offset], bytes = try CanonicalJSON.encode(record).count
      guard bytes <= 3 * 1024 * 1024 else { throw failure("RESOURCE_LIMIT", "An indivisible publication exceeds the public response budget.") }
      if used + bytes > 3 * 1024 * 1024 { break }
      page[kind, default: []].append(record); used += bytes; offset += 1
    }
    var result = page.mapValues(JSONValue.array)
    result["profile"] = .string("aex-1.3"); result["revision"] = .number(Double(state!.revision))
    result["nextCursor"] = offset < records.count ? .string(prefix + ":" + String(offset)) : .null
    result["truncated"] = .bool(offset < records.count)
    return .object(result)
  }
}
