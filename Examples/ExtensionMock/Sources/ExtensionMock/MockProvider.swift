import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import Foundation

/// Explicitly launched test Provider; it simulates work and never claims real verification.
@main struct MockProvider {
  static func output(_ value: JSONValue) throws { FileHandle.standardOutput.write(try CanonicalJSON.encode(value) + Data([10])) }
  static func main() async {
    do { try await run() }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
  }
  static func run() async throws {
    guard CommandLine.arguments.count == 3 else { throw ArchitectureError("INVALID_ARGUMENT", "Usage: ExtensionMock WORKSPACE STATE_DIRECTORY", exitCode: 2) }
    let workspace = CommandLine.arguments[1], directory = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let ledger = try ProviderActionLedger(path: directory.appendingPathComponent("actions.json"))
    let credentialPath = directory.appendingPathComponent("resume.json")
    var resume: String?
    if FileManager.default.fileExists(atPath: credentialPath.path) { resume = try JSONDecoder().decode(String.self, from: Data(contentsOf: credentialPath)) }
    let empty: JSONValue = .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)])
    let cancelSchema: JSONValue = .object(["type": .string("object"), "properties": .object(Dictionary(uniqueKeysWithValues: ["requestID", "jobID", "runID"].map { ($0, JSONValue.object(["type": .string("string")])) })), "required": .array(["requestID", "jobID", "runID"].map(JSONValue.string)), "additionalProperties": .bool(false)])
    let manifest = ExtensionManifest(extensionID: "local.example.mock", displayName: "Mock analysis", requestedPermissions: ExtensionPermission.allCases, views: [ExtensionViewDefinition(id: "results", kind: "table", title: "Mock results"), ExtensionViewDefinition(id: "timeline", kind: "timeline", title: "Mock timeline")], actions: [ExtensionActionDefinition(id: "check", title: "Simulate analysis", inputSchemaID: "check.v1", inputSchema: empty), ExtensionActionDefinition(id: "cancel", title: "Cancel mock job", operation: "cancel", inputSchemaID: "cancel.v1", inputSchema: cancelSchema)])
    var provider: ExtensionProviderClient?
    while provider == nil {
      do { provider = try await ExtensionProviderClient.register(workspace: workspace, manifest: manifest, resumeCredential: resume) }
      catch let error as ArchitectureError where error.code == "APPROVAL_REQUIRED" { try output(.object(["state": .string("approvalRequired"), "message": .string(error.message)])); try await Task.sleep(for: .seconds(1)) }
    }
    let session = provider!
    try CanonicalJSON.encode(session.registration.resumeCredential).write(to: credentialPath, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialPath.path)
    let status = try await session.client.call("workspace.status")
    guard let snapshotID = status["snapshotID"].string else { throw ArchitectureError("SOURCE_UNAVAILABLE", "Index the workspace before starting the mock.", exitCode: 3) }
    let input = try await session.inputManifest(snapshotID: snapshotID)
    let inputs = try await session.verifiedInputs(input)
    let page = try await session.client.scanSnapshot(snapshotID: snapshotID, collection: "entities", limit: 1)
    let ids = page.records.compactMap { $0["id"].string }
    let binding = ExtensionBinding(workspaceID: input.workspaceID, snapshotID: snapshotID, inputManifestDigest: try input.digest, entityIDs: ids)
    let run = try await session.begin(runID: UUID().uuidString, scope: "workspace", contributionSetID: "mock-results", binding: binding, kinds: ["annotation", "graph", "view"], viewIDs: ["results", "timeline"])
    let contributions = [
      ExtensionContribution(id: "local.example.mock:finding", kind: "annotation", binding: binding, data: try JSONValue.encode(ExtensionAnnotation(reportedStatus: "simulated", claim: "Mock data only; <script>not executable</script>", scope: "workspace", assumptions: ["No verifier was run"]))),
      ExtensionContribution(id: "local.example.mock:graph", kind: "graph", binding: binding, data: .object(["nodes": .array([.object(["id": .string("local.example.mock:input"), "label": .string("Captured input")]), .object(["id": .string("local.example.mock:result"), "label": .string("Simulated report")])]), "edges": .array([.object(["id": .string("local.example.mock:relation"), "source": .string("local.example.mock:input"), "target": .string("local.example.mock:result"), "kind": .string("mock.reports")])])])),
      ExtensionContribution(id: "local.example.mock:results", kind: "view", binding: binding, data: .object(["kind": .string("table"), "columns": .array([.string("Source files"), .string("Reported status")]), "rows": .array([.array([.number(Double(inputs.count)), .string("simulated")])])])),
      ExtensionContribution(id: "local.example.mock:timeline", kind: "view", binding: binding, data: .object(["kind": .string("timeline"), "items": .array([.object(["time": .string("1"), "label": .string("Input captured")]), .object(["time": .string("2"), "label": .string("Mock publication complete")])])]))
    ]
    let publication = try PublicationManifest(contributions: contributions)
    try await session.prepare(run, manifest: publication); try await session.stage(run, contributions: contributions); try await session.commit(run, manifest: publication)
    try output(.object(["state": .string("ready"), "runID": .string(run.id), "publicationID": .string(run.publicationID), "sessionID": .string(session.registration.sessionID)]))
    let jobs = MockJobs()
    let reconciliation = try await session.reconcile()
    for record in reconciliation.array {
      let intent = try record["intent"].decode(ActionIntent.self)
      do { let old = try await ledger.lookup(intent, providerID: manifest.extensionID); try await session.receipt(for: intent, receipt: old) }
      catch { try output(.object(["state": .string("unknown"), "requestID": .string(intent.requestID), "message": .string(String(describing: error))])) }
    }
    ProcessSignals.install()
    while !ProcessSignals.interrupted {
      try await session.heartbeat()
      if let intent = try await session.nextAction() {
        let reservation = try await ledger.reserve(intent, providerID: manifest.extensionID)
        try await session.receipt(for: intent, receipt: reservation.receipt)
        if reservation.mayStart {
          if intent.actionID == "cancel" { await jobs.cancel(intent.arguments["requestID"].string ?? "") }
          else {
            let actionRun = try await session.begin(runID: UUID().uuidString, scope: "workspace", contributionSetID: "mock-results", binding: intent.binding, kinds: [], viewIDs: [])
            guard let jobID = reservation.receipt.jobID else { throw ArchitectureError("PROTOCOL_MISMATCH", "Mock accepted receipt has no job.", exitCode: 7) }
            await jobs.start(intent, jobID: jobID, run: actionRun, client: session)
          }
          try output(.object(["state": .string("accepted"), "requestID": .string(intent.requestID), "jobID": reservation.receipt.jobID.map(JSONValue.string) ?? .null]))
        }
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    await jobs.shutdown(); try await session.disconnect(); await ledger.shutdown()
  }
}

actor MockJobs {
  private var tasks: [String: Task<Void, Never>] = [:]
  func start(_ intent: ActionIntent, jobID: String, run: ExtensionRun, client: ExtensionProviderClient) {
    tasks[intent.requestID] = Task {
      do {
        try await client.report(requestID: intent.requestID, jobID: jobID, runID: run.id, revision: 1, state: "running")
        var status = "completed"
        do { try await Task.sleep(for: .seconds(8)) }
        catch is CancellationError { status = "cancelled" }
        let terminal = status
        // This owned task shields cleanup/reporting from the cancelled work task.
        try await Task {
          if terminal == "cancelled" { try await Task.sleep(for: .milliseconds(600)) }
          let manifest = try PublicationManifest(contributions: [])
          try await client.prepare(run, manifest: manifest)
          try await client.commit(run, manifest: manifest, completion: terminal == "cancelled" ? "cancelled" : "complete")
          try await client.report(requestID: intent.requestID, jobID: jobID, runID: run.id, revision: 2, state: terminal)
        }.value
      } catch { FileHandle.standardError.write(Data("Mock job outcome unknown: \(error)\n".utf8)) }
      tasks[intent.requestID] = nil
    }
  }
  func cancel(_ requestID: String) { tasks[requestID]?.cancel() }
  func shutdown() async { let owned = Array(tasks.values); for task in owned { task.cancel() }; for task in owned { await task.value }; tasks.removeAll() }
}
