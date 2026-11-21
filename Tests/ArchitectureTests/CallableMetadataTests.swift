import ArchitectureFrontend
import Foundation
import Testing

struct CallableMetadataTests {
  @Test(.timeLimit(.minutes(1))) func structuredCallablesRetainLanguageSemantics() throws {
    for language in ["swift", "rust"] {
      let filename = language == "swift" ? "CallableSwift.swift" : "callable_rust.rs"
      let url = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("CallableNodes/" + filename)
      let input = SourceInput(workspaceID: "structured", path: filename, language: language, bytes: try Data(contentsOf: url), contextDigest: "context", generation: 1)
      let result = try SkeletonFrontend().analyze(input)
      let update = try #require(result.entities.first { $0.name == "update" })
      let signature = try #require(update.attributes["declaration.callable"])
      #expect(signature["version"] == .number(1))
      #expect(signature["effects"].array.compactMap(\.string).contains("async"))
      #expect(signature["parameters"].array.first?["name"].string == "value")
      let free = try #require(result.entities.first { $0.name == (language == "swift" ? "callableSwift" : "callable_rust") })
      #expect(free.kind == "function")
      #expect(free.attributes["declaration.callable"]?["receiver"]["kind"].string == "none")
      #expect(free.attributes["declaration.callable"]?["results"].array.first?["type"].string == "T")
      #expect(result.facts.contains { $0.kind == "contains" && $0.source == update.id })
      #expect(result.facts.contains { $0.kind == "candidateCalls" })
      #expect(!result.facts.contains { $0.kind == "calls" })
      if language == "swift" {
        #expect(signature["receiver"]["kind"].string == "instance")
        #expect(signature["parameters"].array.first?["label"].string == "_")
        #expect(signature["parameters"].array.first?["type"].string == "T")
        #expect(signature["parameters"].array.first?["passing"].array.compactMap(\.string) == ["inout"])
        #expect(signature["annotations"].array.compactMap(\.string) == ["@MainActor"])
        #expect(signature["constraints"].array.compactMap(\.string) == ["where T: Equatable"])
        #expect(signature["modifiers"].array.compactMap(\.string) == ["mutating"])
        let make = try #require(result.entities.first { $0.name == "make" })
        #expect(make.attributes["declaration.callable"]?["receiver"]["kind"].string == "type")
        #expect(make.attributes["declaration.callable"]?["parameters"].array.first?["spelling"].string == "_ value: Int = 10")
      } else {
        #expect(signature["receiver"]["kind"].string == "mutableBorrow")
        #expect(signature["receiver"]["spelling"].string == "&'a mut self")
        #expect(signature["typeParameters"].array.compactMap(\.string) == ["'a", "T"])
        #expect(signature["constraints"].array.compactMap(\.string) == ["where T: Clone"])
        #expect(signature["safety"].array.compactMap(\.string) == ["unsafe"])
        #expect(signature["effects"].array.compactMap(\.string) == ["async"])
        #expect(signature["results"].array.first?["type"].string == "Result<&'a T, Error>")
        for (name, kind) in [("new", "type"), ("consume", "owned"), ("inspect", "sharedBorrow"), ("boxed", "explicitType")] {
          let member = try #require(result.entities.first { $0.name == name })
          #expect(member.attributes["declaration.callable"]?["receiver"]["kind"].string == kind)
          #expect(member.attributes["declaration.kind"]?.string == (name == "new" ? "associatedFunction" : "method"))
        }
      }
    }
  }
  @Test(.timeLimit(.minutes(1))) func swiftSignaturesKeepAccessParametersEffectsAndResults() throws {
    let source = """
      struct Client {
        public static func fetch(_ key: String, transform: (Int) -> Bool) async throws -> [String: Int] { [:] }
        private func reset() {}
        func explicit() -> Void {}
        func apply(_ transform: (Int) -> Bool) {}
        func identity<T>(_ value: T) -> T where T: Equatable { value }
        init(token: String) {}
        deinit {}
      }
      """
    let input = SourceInput(workspaceID: "callables", path: "Client.swift", language: "swift", bytes: Data(source.utf8), contextDigest: "context", generation: 1)
    let result = try SkeletonFrontend().analyze(input)
    let fetch = try #require(result.entities.first { $0.name == "fetch" })
    #expect(fetch.attributes["declaration.access"]?.string == "public")
    #expect(fetch.attributes["declaration.parameters"]?.string == "(_ key: String, transform: (Int) -> Bool)")
    #expect(fetch.attributes["declaration.returnType"]?.string == "[String: Int]")
    #expect(fetch.attributes["declaration.returnTypeExplicit"]?.bool == true)
    #expect(fetch.attributes["declaration.modifiers"]?.array.compactMap(\.string) == ["static", "async", "throws"])
    let reset = try #require(result.entities.first { $0.name == "reset" })
    #expect(reset.attributes["declaration.access"]?.string == "private")
    #expect(reset.attributes["declaration.returnType"]?.string == "Void")
    #expect(reset.attributes["declaration.returnTypeExplicit"]?.bool == false)
    let explicit = try #require(result.entities.first { $0.name == "explicit" })
    #expect(explicit.attributes["declaration.returnTypeExplicit"]?.bool == true)
    let apply = try #require(result.entities.first { $0.name == "apply" })
    #expect(apply.attributes["declaration.returnType"]?.string == "Void")
    let identity = try #require(result.entities.first { $0.name == "identity" })
    #expect(identity.attributes["declaration.returnType"]?.string == "T")
    let deinitializer = try #require(result.entities.first { $0.attributes["declaration.kind"]?.string == "deinitializer" })
    #expect(deinitializer.attributes["declaration.returnType"] == nil)
    #expect(deinitializer.attributes["declaration.parameters"]?.string == "")
    let initializer = try #require(result.entities.first { $0.attributes["declaration.kind"]?.string == "initializer" })
    #expect(initializer.attributes["declaration.returnType"] == nil)
    #expect(initializer.attributes["declaration.parameters"]?.string == "(token: String)")
  }

  @Test(.timeLimit(.minutes(1))) func rustResultsAndModifiersRetainSourceSpellings() throws {
    let source = "pub async unsafe fn fetch<'a>(value: &'a str) -> Result<String, Error> { todo!() }\nfn reset() {}"
    let input = SourceInput(workspaceID: "callables", path: "client.rs", language: "rust", bytes: Data(source.utf8), contextDigest: "context", generation: 1)
    let result = try SkeletonFrontend().analyze(input)
    let fetch = try #require(result.entities.first { $0.name == "fetch" })
    #expect(fetch.attributes["declaration.access"]?.string == "pub")
    #expect(fetch.attributes["declaration.parameters"]?.string == "(value: &'a str)")
    #expect(fetch.attributes["declaration.returnType"]?.string == "Result<String, Error>")
    #expect(fetch.attributes["declaration.modifiers"]?.array.compactMap(\.string) == ["async", "unsafe"])
    let reset = try #require(result.entities.first { $0.name == "reset" })
    #expect(reset.attributes["declaration.returnType"]?.string == "()")
    #expect(reset.attributes["declaration.returnTypeExplicit"]?.bool == false)
  }
}
