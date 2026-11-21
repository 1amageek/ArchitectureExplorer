import ArchitectureCanvas
import ArchitectureCore
import Foundation
import Testing

struct CanvasTests {
  let reader = CanvasFileReader()
  func fixture(_ name: String) throws -> String {
    let url = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/Canvas/" + name)
    return try String(contentsOf: url, encoding: .utf8)
  }
  @Test(.timeLimit(.minutes(1))) func importedNodesRetainSourceLanguageIndependentlyOfDetails() throws {
    let json = #"{"nodes":[{"id":"handler","role":"Method","language":"ts","details":{"status":"public"}},{"id":"net","role":"Network"}],"edges":[]}"#
    let document = try reader.read(name: "diagram.json", text: json)
    #expect(document.nodes[0].language == "ts")
    #expect(document.nodes[0].details["status"].string == "public")
    #expect(document.nodes[1].language == nil)
  }

  @Test(.timeLimit(.minutes(1)), arguments: ["hierarchy.json", "relations.json", "controlFlow.json", "dataFlow.json", "stateTransition.json", "sequence.json", "proofDependencies.json", "dependencies.dot", "cfg.dot", "flow.mmd", "states.mmd", "sequence.mmd", "classes.puml", "states.puml", "sequence.puml", "nested.graphml", "machine.scxml", "classes.xmi", "states.xmi", "sequence.xmi", "image.svg", "architecture.json"])
  func realFilesRetainDrawableStructure(_ name: String) throws {
    let text = try fixture(name), document = try reader.read(name: name, text: text)
    #expect(document.sourceName == name); #expect(!document.sourceDigest.isEmpty)
    try document.validate()
    if name == "image.svg" { #expect(document.nodes.isEmpty); #expect(document.svg!.contains("Before ")); #expect(document.svg!.range(of: "inside")!.lowerBound < document.svg!.range(of: " after")!.lowerBound) }
    else { #expect(!document.nodes.isEmpty); #expect(!document.edges.isEmpty) }
    if name.hasPrefix("sequence") { #expect(document.kind == "sequence"); #expect(document.lanes.count == 2); #expect(document.nodes.allSatisfy { $0.laneID != nil && $0.order != nil }) }
    if name == "dependencies.dot" { #expect(document.nodes.first { $0.id == "A" }?.parentID == "cluster_host"); #expect(document.edges.contains { $0.source == "C" && $0.target == "A" }) }
    if name == "machine.scxml" { #expect(document.kind == "stateTransition"); #expect(document.edges.contains { $0.label == "begin [ready]" }); #expect(document.nodes.first { $0.id == "busy" }!.details != .null) }
  }
  @Test(.timeLimit(.minutes(1))) func commonInlineSyntaxAndGraphAttributesRetainMeaning() throws {
    let inline = try reader.read(name: "inline.mmd", text: "flowchart TD; A-->B; B-->C")
    #expect(inline.nodes.map(\.id) == ["A", "B", "C"]); #expect(inline.edges.count == 2)
    #expect(inline.metadata["rankdir"].string == "TD")
    let implicit = try reader.read(name: "default.scxml", text: #"<scxml xmlns="http://www.w3.org/2005/07/scxml"><state id="ready"/><final id="done"/></scxml>"#)
    #expect(implicit.edges.contains { $0.source == "__initial_root" && $0.target == "ready" })
    let alias = try reader.read(name: "state.mmd", text: "stateDiagram-v2\nstate Ready : Waiting for work\nReady --> Done : finish")
    #expect(alias.nodes.first { $0.id == "Ready" }!.label == "Waiting for work")
    let dots = try reader.read(name: "graph.dot", text: "graph G { rankdir=LR; \"one node\" -- b -- c [label=\"literal <tag>\"]; }")
    #expect(dots.nodes.count == 3); #expect(dots.edges.allSatisfy { !$0.directed }); #expect(dots.metadata["rankdir"].string == "LR")
    let strict = try reader.read(name: "strict.dot", text: #"strict graph { "node" [label="Literal"]; "node" -- "subgraph" [label="old"]; "subgraph" -- "node" [label="new"]; ";" -- "node"; }"#)
    #expect(strict.nodes.count == 3); #expect(strict.edges.count == 2); #expect(strict.edges[0].label == "new")
    let text = try fixture("architecture.json"), ir = try reader.read(name: "architecture.json", text: text)
    #expect(ir.metadata["architectureIR"]["freshness"].string == "stale")
    #expect(ir.nodes.first { $0.id == "count" }?.parentID == "owner")
  }
  @Test(.timeLimit(.minutes(1))) func malformedAndUnsupportedInputsFailWithoutEmptySuccess() throws {
    let cases: [(String, String)] = [
      ("broken.json", "{bad"), ("empty.json", "{\"nodes\":[],\"edges\":[]}"),
      ("duplicate.json", "{\"nodes\":[{\"id\":\"a\"},{\"id\":\"a\"}],\"edges\":[]}"),
      ("dangling.json", "{\"nodes\":[{\"id\":\"a\"}],\"edges\":[{\"source\":\"a\",\"target\":\"missing\"}]}"),
      ("cycle.json", "{\"nodes\":[{\"id\":\"a\",\"parentID\":\"b\"},{\"id\":\"b\",\"parentID\":\"a\"}],\"edges\":[]}"),
      ("broken.dot", "digraph { a ->"), ("broken.mmd", "flowchart TD\nsubgraph x\na-->b"), ("unsupported.mmd", "pie\nA:1"),
      ("unsafe.puml", "@startuml\n!include https://example.invalid/a\n@enduml"),
      ("unsafe.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>"),
      ("external.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"><use href=\"https://example.invalid/x\"/></svg>"),
      ("xxe.scxml", "<!DOCTYPE scxml [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><scxml>&secret;</scxml>"),
      ("unknown.xmi", "<XMI><element type=\"unsupported\"/></XMI>"),
      ("model.tla", "---- MODULE X ----")
    ]
    for (name, text) in cases { #expect(throws: (any Error).self) { try reader.read(name: name, text: text) } }
    #expect(throws: (any Error).self) { try reader.read(name: "large.dot", text: String(repeating: "a", count: 1024 * 1024 + 1)) }
  }
  @Test(.timeLimit(.minutes(1))) func concurrentPresentationMutationsHaveOneRevisionWinner() async throws {
    let owner = CanvasSessions(), text = try fixture("relations.json")
    let opened = try await owner.handle("canvas.open", parameters: .object(["name": .string("relations.json"), "text": .string(text)]))
    let id = opened["viewSessionID"].string!
    let winners = try await withThrowingTaskGroup(of: Int.self) { group in
      for target in ["a", "b"] {
        group.addTask {
          do { _ = try await owner.handle("canvas.select", parameters: .object(["viewSessionID": .string(id), "expectedRevision": .number(1), "ids": .array([.string(target)])])); return 1 }
          catch let error as ArchitectureError where error.code == "REVISION_CONFLICT" { return 0 }
        }
      }
      var count = 0; for try await winner in group { count += winner }; return count
    }
    #expect(winners == 1)
    let state = try await owner.handle("canvas.get", parameters: .object(["viewSessionID": .string(id)])); #expect(state["revision"].int == 2)
    await owner.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func staticImagesAndInvalidPresentationUpdatesKeepTheirContracts() async throws {
    let owner = CanvasSessions(), text = try fixture("image.svg")
    let opened = try await owner.handle("canvas.open", parameters: .object(["name": .string("image.svg"), "text": .string(text)]))
    let id = opened["viewSessionID"].string!
    _ = try await owner.handle("canvas.select", parameters: .object(["viewSessionID": .string(id), "ids": .array([.string("__svg")])]))
    let box: JSONValue = .object(["id": .string("__svg"), "x": .number(0), "y": .number(0), "width": .number(960), "height": .number(320)])
    let positioned = try await owner.handle("canvas.setGeometry", parameters: .object(["viewSessionID": .string(id), "geometry": .array([box])]))
    for bad in [JSONValue.string("node"), .number(2), .array([.number(2)])] {
      await #expect(throws: (any Error).self) { try await owner.handle("canvas.setFilter", parameters: .object(["viewSessionID": .string(id), "filter": .object(["roles": bad])])) }
    }
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.setGeometry", parameters: .object(["viewSessionID": .string(id), "geometry": .array([box, box])])) }
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.setCamera", parameters: .object(["viewSessionID": .string(id), "camera": .object(["zoom": .number(0), "pan": .object(["x": .number(0), "y": .number(0)])])])) }
    let unchanged = try await owner.handle("canvas.get", parameters: .object(["viewSessionID": .string(id)])); #expect(unchanged == positioned)
    let exported = try await owner.handle("canvas.export", parameters: .object(["viewSessionID": .string(id), "format": .string("svg")]))
    let roundtrip = try reader.read(name: "export.svg", text: exported["text"].string!); #expect(roundtrip.svg != nil)
    await owner.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func sequencePresentationIdentitiesCanBeSelectedWithoutInventingFacts() async throws {
    let owner = CanvasSessions(), text = try fixture("sequence.mmd")
    let opened = try await owner.handle("canvas.open", parameters: .object(["name": .string("sequence.mmd"), "text": .string(text)])), id = opened["viewSessionID"].string!
    let lane = "__lane:" + opened["document"]["lanes"].array[0]["id"].string!
    for identity in [lane, "__fragment:0"] {
      let selected = try await owner.handle("canvas.select", parameters: .object(["viewSessionID": .string(id), "ids": .array([.string(identity)])]))
      #expect(selected["state"]["selection"].array == [.string(identity)])
      #expect(selected["document"]["nodes"].array.count == opened["document"]["nodes"].array.count)
    }
    await owner.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func collapsedSVGExportsKeepExternalConnectionsAndReimport() async throws {
    let owner = CanvasSessions()
    let text = #"{"nodes":[{"id":"parent"},{"id":"child","parentID":"parent"},{"id":"other"}],"edges":[{"id":"external","source":"child","target":"other"},{"id":"internal","source":"parent","target":"child"}]}"#
    let opened = try await owner.handle("canvas.open", parameters: .object(["name": .string("graph.json"), "text": .string(text)])), id = opened["viewSessionID"].string!
    _ = try await owner.handle("canvas.collapse", parameters: .object(["viewSessionID": .string(id), "ids": .array([.string("parent")])]))
    let geometry = ["parent", "other"].enumerated().map { index, id in JSONValue.object(["id": .string(id), "x": .number(0), "y": .number(Double(index * 160)), "width": .number(264), "height": .number(88)]) }
    _ = try await owner.handle("canvas.setGeometry", parameters: .object(["viewSessionID": .string(id), "geometry": .array(geometry)]))
    let exported = try await owner.handle("canvas.export", parameters: .object(["viewSessionID": .string(id), "format": .string("svg")])), svg = exported["text"].string!
    #expect(svg.contains("data-edge-id=\"external\"")); #expect(!svg.contains("data-edge-id=\"internal\"")); #expect(!svg.contains("data-node-id=\"child\""))
    let roundtrip = try reader.read(name: "export.svg", text: svg); #expect(roundtrip.svg!.contains("external"))
    await owner.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func manyFilesAreBoundedWithoutEvictingOpenDocuments() async throws {
    let owner = CanvasSessions(), text = try fixture("relations.json")
    for index in 0..<32 { _ = try await owner.handle("canvas.open", parameters: .object(["name": .string("diagram-\(index).json"), "text": .string(text)])) }
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.open", parameters: .object(["name": .string("overflow.json"), "text": .string(text)])) }
    let list = try await owner.handle("canvas.list", parameters: .object([:])); #expect(list["sessions"].array.count == 32)
    let id = list["sessions"].array[0]["viewSessionID"].string!
    _ = try await owner.handle("canvas.close", parameters: .object(["viewSessionID": .string(id)]))
    _ = try await owner.handle("canvas.open", parameters: .object(["name": .string("replacement.json"), "text": .string(text)]))
    let replaced = try await owner.handle("canvas.list", parameters: .object([:])); #expect(replaced["sessions"].array.count == 32)
    await owner.shutdown()
  }
  @Test(.timeLimit(.minutes(1))) func sharedSessionsAreAtomicRevisionedAndDoNotInventExports() async throws {
    let owner = CanvasSessions(), text = try fixture("relations.json")
    let opened = try await owner.handle("canvas.open", parameters: .object(["name": .string("relations.json"), "text": .string(text)]))
    let id = opened["viewSessionID"].string!, revision = opened["revision"].int!
    let selected = try await owner.handle("canvas.select", parameters: .object(["viewSessionID": .string(id), "expectedRevision": .number(Double(revision)), "ids": .array([.string("a")])]))
    #expect(selected["state"]["selection"].array == [.string("a")])
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.select", parameters: .object(["viewSessionID": .string(id), "expectedRevision": .number(Double(revision)), "ids": .array([])])) }
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.open", parameters: .object(["viewSessionID": .string(id), "name": .string("bad.dot"), "text": .string("invalid")])) }
    let afterFailure = try await owner.handle("canvas.get", parameters: .object(["viewSessionID": .string(id)])); #expect(afterFailure == selected)
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.export", parameters: .object(["viewSessionID": .string(id), "format": .string("svg")])) }
    let geometry: JSONValue = .array([.object(["id": .string("a"), "x": .number(0), "y": .number(0), "width": .number(264), "height": .number(80)]), .object(["id": .string("b"), "x": .number(0), "y": .number(160), "width": .number(264), "height": .number(80)])])
    _ = try await owner.handle("canvas.setGeometry", parameters: .object(["viewSessionID": .string(id), "geometry": geometry]))
    let exported = try await owner.handle("canvas.export", parameters: .object(["viewSessionID": .string(id), "format": .string("svg")]))
    #expect(exported["text"].string!.contains("data-edge-id=\"ab\""))
    let json = try await owner.handle("canvas.export", parameters: .object(["viewSessionID": .string(id), "format": .string("json")]))
    let decoded = try reader.read(name: "roundtrip.json", text: json["text"].string!); #expect(decoded.nodes.count == 2)
    _ = try await owner.handle("canvas.close", parameters: .object(["viewSessionID": .string(id)]))
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.get", parameters: .object(["viewSessionID": .string(id)])) }
    await owner.shutdown()
    await #expect(throws: (any Error).self) { try await owner.handle("canvas.list", parameters: .object([:])) }
  }
}
