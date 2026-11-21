import ArchitectureCore
import ArchitectureIndexer
import ArchitectureIR
@testable import ArchitectureService
import Foundation
import Testing

struct PropertyContextTests {
  @Test(.timeLimit(.minutes(1))) func verificationSpecEditsChangeCapturedInputs() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let folder = root.appendingPathComponent("Verification/Subject")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let paths = try WorkspacePaths(root.path), config = try IndexConfiguration(paths: paths)
    let path = "Verification/Subject/properties.json", file = root.appendingPathComponent(path)
    let configurationPath = "Verification/Subject/invar.json"
    for expression in ["true", "false"] {
      let bytes = Data(expression.utf8)
      let configuration = Data(("{\"approved\":" + expression + "}").utf8)
      try bytes.write(to: file)
      try configuration.write(to: root.appendingPathComponent(configurationPath))
      let capture = try WorkspaceScanner().capture(paths: paths, configuration: config, generation: 1)
      #expect(capture.inputs[path] == CanonicalJSON.digest(bytes))
      #expect(capture.inputs[configurationPath] == CanonicalJSON.digest(configuration))
      #expect(capture.sources.isEmpty)
    }
  }

  @Test(.timeLimit(.minutes(1))) func pinnedSourcesIncludeTransitiveReferencesConsumersTestsAndDesign() throws {
    let files = ["Sources/Selected.swift":"struct Selected { let value: Helper }",
      "Sources/Helper.swift":"struct Helper { let leaf: Leaf }", "Sources/Leaf.swift":"struct Leaf {}",
      "Demo/Caller.swift":"let selected = Selected()", "Tests/HelperTests.swift":"func testHelper() { _ = Helper() }",
      "Sources/README.md":"Selected behavior.", "DESIGN.md":"Workspace requirements.",
      "Other/DESIGN.md":"Unrelated.", "Other/Noise.swift":"struct Noise {}"].mapValues { Data($0.utf8) }
    let entities = [("Selected","Selected"),("Helper","Helper"),("Leaf","Leaf")].map { name, file in
      let path = "Sources/" + file + ".swift"
      return Entity(id: name, kind: "type", language: "swift", name: name, identityKey: name, entityRevision: "1",
        anchor: SourceAnchor(path: path, digest: CanonicalJSON.digest(files[path]!), startByte: 0, endByte: files[path]!.count))
    }
    var inputs = files.mapValues(CanonicalJSON.digest)
    inputs["@designDocuments"] = "markdown-v1"
    let snapshot = Snapshot(id: "snapshot", workspaceID: "workspace", generation: 1, contextDigest: "context",
      inputs: inputs, entities: entities, facts: [], evidence: [], coverage: [])
    let context = try PropertyContext.build(snapshot, files: files, entityID: "Selected")
    let rows = context["files"].array
    #expect(Set(rows.compactMap { $0["path"].string }) == Set(files.keys.filter { !$0.hasPrefix("Other/") }))
    for row in rows {
      let path = try #require(row["path"].string)
      #expect(Data((row["text"].string ?? "").utf8) == files[path])
    }
    #expect(context["relations"].array.contains { $0["symbol"].string == "Helper" && $0["kind"].string == "identifierCandidate" })
    #expect(throws: ArchitectureError.self) { try PropertyContext.build(snapshot, files: files, entityID: "unknown") }
  }
}
