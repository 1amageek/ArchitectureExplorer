import ArchitectureFrontend
import Foundation
import Testing

struct PropertyMetadataTests {
  @Test(.timeLimit(.minutes(1))) func propertiesKeepExplicitSyntaxWithoutInferringTypes() throws {
    let source = """
      struct Account {
        public let name: String
        public private(set) var count: Int = 0
        private var handler: ((Int) -> String)?
        var inferred = 42
        var computed: String { "value" }
        let first = 1, second: String = "two"
      }
      """
    let input = SourceInput(workspaceID: "metadata", path: "Account.swift", language: "swift",
      bytes: Data(source.utf8), contextDigest: "context", generation: 1)
    let result = try SkeletonFrontend().analyze(input)
    let name = try #require(result.entities.first { $0.name == "name" })
    #expect(name.attributes["declaration.access"]?.string == "public")
    #expect(name.attributes["declaration.binding"]?.string == "let")
    #expect(name.attributes["declaration.type"]?.string == "String")
    let count = try #require(result.entities.first { $0.name == "count" })
    #expect(count.attributes["declaration.access"]?.string == "public")
    #expect(count.attributes["declaration.setterAccess"]?.string == "private")
    #expect(count.attributes["declaration.binding"]?.string == "var")
    #expect(count.attributes["declaration.type"]?.string == "Int")
    let handler = try #require(result.entities.first { $0.name == "handler" })
    #expect(handler.attributes["declaration.access"]?.string == "private")
    #expect(handler.attributes["declaration.type"]?.string == "((Int) -> String)?")
    let inferred = try #require(result.entities.first { $0.name == "inferred" })
    #expect(inferred.attributes["declaration.access"] == nil)
    #expect(inferred.attributes["declaration.type"] == nil)
    let computed = try #require(result.entities.first { $0.name == "computed" })
    #expect(computed.attributes["declaration.type"]?.string == "String")
    let first = try #require(result.entities.first { $0.name == "first" })
    #expect(first.attributes["declaration.type"] == nil)
  }

  @Test(.timeLimit(.minutes(1))) func rustFieldsAndConstantsDoNotInventBindingMutability() throws {
    let source = """
      pub struct Account { pub name: String, pub(crate) count: u32, hidden: Option<String> }
      pub const LIMIT: usize = 4;
      static mut CURRENT: usize = 0;
      """
    let input = SourceInput(workspaceID: "metadata", path: "account.rs", language: "rust",
      bytes: Data(source.utf8), contextDigest: "context", generation: 1)
    let result = try SkeletonFrontend().analyze(input)
    let name = try #require(result.entities.first { $0.name == "name" })
    #expect(name.attributes["declaration.access"]?.string == "pub")
    #expect(name.attributes["declaration.binding"]?.string == "field")
    #expect(name.attributes["declaration.type"]?.string == "String")
    let count = try #require(result.entities.first { $0.name == "count" })
    #expect(count.attributes["declaration.access"]?.string == "pub(crate)")
    let hidden = try #require(result.entities.first { $0.name == "hidden" })
    #expect(hidden.attributes["declaration.access"] == nil)
    #expect(hidden.attributes["declaration.type"]?.string == "Option<String>")
    let limit = try #require(result.entities.first { $0.name == "LIMIT" })
    #expect(limit.attributes["declaration.binding"]?.string == "const")
    let current = try #require(result.entities.first { $0.name == "CURRENT" })
    #expect(current.attributes["declaration.binding"]?.string == "static mut")
  }
  @Test(.timeLimit(.minutes(1))) func deepSourceRetainsDeclarationsAndPreorderIdentity() throws {
    let expression = String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)
    let source = "struct Deep { public let name: String; func deep() -> Int { return " + expression + " } }"
    let input = SourceInput(workspaceID: "metadata", path: "Deep.swift", language: "swift",
      bytes: Data(source.utf8), contextDigest: "context", generation: 1)
    let result = try SkeletonFrontend().analyze(input)
    #expect(result.entities.contains { $0.name == "deep" && $0.kind == "method" })
    let name = try #require(result.entities.first { $0.name == "name" })
    #expect(name.attributes["declaration.binding"]?.string == "let")
    let owner = try #require(result.entities.first { $0.name == "Deep" })
    #expect(result.facts.contains { $0.source == owner.id && $0.target == name.id && $0.kind == "contains" })
    let repeated = try SkeletonFrontend().analyze(input)
    #expect(result.entities == repeated.entities)
    #expect(result.facts == repeated.facts)
  }

}
