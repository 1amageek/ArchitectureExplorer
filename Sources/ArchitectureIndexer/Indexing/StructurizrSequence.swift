import ArchitectureCore
import ArchitectureFrontend
import ArchitectureIR
import Foundation

enum StructurizrSequence {
  static let fileLimit = 128 * 1024
  static let citationBudget = 4 * 1024 * 1024
  static let citationLimit = 128

  struct Relationship: Hashable {
    let source: String
    let target: String
    let label: String
    let technology: String
    let declaration: ArchitectureSequence.Declaration

    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.declaration.path == rhs.declaration.path && lhs.declaration.line == rhs.declaration.line
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(declaration.path)
      hasher.combine(declaration.line)
    }
  }

  struct Reference {
    let path: String
    let line: Int
    let digest: String

    init?(_ line: String) {
      guard let match = line.wholeMatch(of: #/\/\/ Source: (.+):([0-9]+) sha256=([a-f0-9]{64})/#),
        let number = Int(match.2), number > 0 else { return nil }
      let path = String(match.1)
      guard !path.isEmpty, !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
          !$0.isEmpty && !$0.hasPrefix(".") && !["node_modules", "target", "Dist"].contains($0)
        }) else { return nil }
      self.path = path
      self.line = number
      self.digest = String(match.3)
    }
  }

  private struct Draft {
    let key: String
    let scope: String
    let declaration: ArchitectureSequence.Declaration
    var title: String
    var requirements: [String] = []
    var messages: [ArchitectureSequence.Message] = []
    var participants: [ArchitectureSequence.Participant] = []
    var requests: Set<Relationship> = []
  }

  static func lines(_ source: String) -> [Substring] {
    source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
  }

  private enum Block { case workspace, views, scenario, properties }

  static func parse(_ file: SourceInput, architecture: StructurizrContext,
    citedFiles: [String: SourceInput]) throws -> [ArchitectureSequence] {
    guard file.bytes.count <= fileLimit, let content = String(data: file.bytes, encoding: .utf8) else {
      throw ArchitectureError("SEQUENCE_DSL_INVALID", "SEQUENCES.dsl must be UTF-8 within 128 KiB.")
    }
    let elements = Dictionary(uniqueKeysWithValues: architecture.nodes.compactMap { node in
      node.attributes["context.ref"]?.string.map { ($0, node) }
    })
    let relations = Dictionary(grouping: architecture.sequenceRelationships) { [$0.source, $0.target] }
    let evidence = citedFiles.mapValues { file in
      (file.digest, String(data: file.bytes, encoding: .utf8).map(lines))
    }
    var stack: [Block] = []
    var started = false
    var hasViews = false
    var seen = architecture.viewKeys
    var pending: [Reference] = []
    var draft: Draft?
    var result: [ArchitectureSequence] = []
    var totalMessages = 0
    for (offset, raw) in lines(content).enumerated() {
      try Task.checkCancellation()
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      let location = ArchitectureSequence.Declaration(path: file.path, line: offset + 1, text: line)
      func invalid(_ message: String) -> ArchitectureError {
        ArchitectureError("SEQUENCE_DSL_INVALID", "\(file.path):\(location.line): \(message)")
      }
      if line.hasPrefix("// Source:") {
        guard stack.last == .scenario, let reference = Reference(line), pending.count < 8 else {
          throw invalid("Expected up to eight workspace source citations per message.")
        }
        pending.append(reference)
        continue
      }
      let tokens: [String]
      do { tokens = try StructurizrContext.tokens(Substring(line)) }
      catch { throw invalid("Invalid quoted value.") }
      if tokens.isEmpty { continue }
      guard line.utf8.count <= 2048 else { throw invalid("Statement exceeds the 2 KiB limit.") }
      let opens = tokens.last == "{"
      var words = opens ? Array(tokens.dropLast()) : tokens
      if words == ["}"] {
        guard pending.isEmpty, let block = stack.popLast() else { throw invalid("Unexpected closing brace or unused citation.") }
        if block == .scenario {
          guard let completed = draft, !completed.messages.isEmpty else { throw invalid("A scenario needs at least one message.") }
          let subject = elements[completed.scope]?.id
          result.append(.init(key: completed.key, title: completed.title, subjectID: subject,
            participants: completed.participants, requirements: completed.requirements,
            declaration: completed.declaration, messages: completed.messages))
          draft = nil
        }
        continue
      }
      switch stack.last {
      case nil where !started && opens && words == ["workspace", "extends", WorkspacePaths.architectureModelFilename]:
        started = true
        stack.append(.workspace)
      case .workspace where !hasViews && opens && words == ["views"]:
        hasViews = true
        stack.append(.views)
      case .views where opens && (3...4).contains(words.count) && words[0] == "dynamic":
        let scope = words[1], key = words[2]
        guard scope == "*" || ["softwareSystem", "application", "dataStore"].contains(elements[scope]?.kind ?? ""),
          key.wholeMatch(of: /[A-Za-z0-9_-]{1,128}/) != nil,
          seen.insert(key).inserted, result.count < 64 else { throw invalid("Invalid scope, duplicate view key or scenario limit reached.") }
        draft = Draft(key: key, scope: scope, declaration: location, title: words.count == 4 ? words[3] : key)
        stack.append(.scenario)
      case .scenario where opens && words == ["properties"] && pending.isEmpty:
        stack.append(.properties)
      case .properties where !opens && words.count == 2 && words[0] == "invar.requirements":
        let ids = words[1].split(separator: " ").map(String.init)
        guard !ids.isEmpty, ids.count <= 32, Set(ids).count == ids.count, draft?.requirements.isEmpty == true,
          ids.allSatisfy({ $0.wholeMatch(of: /[A-Za-z0-9_.-]{1,64}/) != nil }) else { throw invalid("Invalid or repeated requirement IDs.") }
        draft?.requirements = ids
      case .scenario where !opens && words.count == 2 && ["title", "description"].contains(words[0]) && pending.isEmpty:
        guard !words[1].trimmingCharacters(in: .whitespaces).isEmpty else { throw invalid("Empty scenario title or description.") }
        if words[0] == "title" { draft?.title = words[1] }
      case .scenario where !opens:
        guard var current = draft, current.messages.count < 100, totalMessages < 512 else {
          throw invalid("Message limit reached.")
        }
        if let order = words.first, order.hasSuffix(":") {
          guard Int(order.dropLast()) == current.messages.count + 1 else {
            throw invalid("Explicit message order must match the consecutive scenario order.")
          }
          words.removeFirst()
        }
        guard (4...5).contains(words.count), words[1] == "->",
          let source = elements[words[0]], let target = elements[words[2]], source.id != target.id,
          allowed(source, in: current.scope, elements: elements), allowed(target, in: current.scope, elements: elements),
          !words[3].trimmingCharacters(in: .whitespaces).isEmpty else {
          throw invalid("Expected a labeled message between two in-scope architecture participants.")
        }
        let technology = words.count == 5 ? words[4] : nil
        let direct = relations[[words[0], words[2]], default: []].filter { technology == nil || $0.technology == technology }
        let inverse = relations[[words[2], words[0]], default: []].filter { current.requests.contains($0) && (technology == nil || $0.technology == technology) }
        let candidates = direct.isEmpty ? inverse : direct
        let exact = candidates.filter { $0.label == words[3] }
        let matching = exact.isEmpty ? candidates : exact
        guard matching.count == 1, let relationship = matching.first else {
          throw invalid("Message requires one matching architecture relationship or a prior request to reply to.")
        }
        let reply = direct.isEmpty
        if !reply { current.requests.insert(relationship) }
        for node in [source, target] where !current.participants.contains(where: { $0.id == node.id }) {
          current.participants.append(.init(id: node.id, name: node.name, entryID: node.attributes["context.entryID"]?.string))
        }
        let citations = pending.map { item -> ArchitectureSequence.Citation in
          guard let (digest, lines) = evidence[item.path] else {
            return .init(path: item.path, line: item.line, digest: item.digest, status: .unavailable)
          }
          guard digest == item.digest else {
            return .init(path: item.path, line: item.line, digest: item.digest, status: .stale)
          }
          guard let lines, item.line <= lines.count else {
            return .init(path: item.path, line: item.line, digest: item.digest, status: .unavailable)
          }
          let excerpt = lines[item.line - 1].trimmingCharacters(in: .whitespacesAndNewlines)
          return .init(path: item.path, line: item.line, digest: item.digest, status: .recorded,
            excerpt: excerpt.utf8.count > 384 ? String(decoding: excerpt.utf8.prefix(384), as: UTF8.self) + "…" : excerpt)
        }
        current.messages.append(.init(source: source.id, target: target.id, label: words[3], reply: reply,
          declaration: location, relationship: relationship.declaration, citations: citations))
        draft = current
        pending.removeAll()
        totalMessages += 1
      default:
        throw invalid("Expected a local architecture extension containing named dynamic views.")
      }
    }
    guard stack.isEmpty, started, hasViews, !result.isEmpty else {
      throw ArchitectureError("SEQUENCE_DSL_INVALID", "\(file.path): Incomplete workspace or no dynamic views.")
    }
    return result
  }

  private static func allowed(_ node: Entity, in scope: String, elements: [String: Entity]) -> Bool {
    if node.attributes["context.owner"] != nil {
      return scope != "*" && node.id != elements[scope]?.id
    }
    return node.id != elements[scope]?.id
  }
}
