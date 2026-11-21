import ArchitectureCore
import ArchitectureFrontend
import ArchitectureIR
import Foundation
import Yams

/// Projects native Backstage records in the captured workspace catalog.
struct CatalogContext {
  static let producer = "c4.backstage"
  static let filenames: Set<String> = ["catalog-info.yaml", "catalog-info.yml", "catalog-info.json"]

  private struct Record: Decodable {
    struct Metadata: Decodable {
      let name: String
      let namespace: String?
      let title: String?
      let description: String?
    }
    struct Spec: Decodable {
      let system: String?
      let type: String?
      let domain: String?
      let subdomainOf: String?
      let dependsOn: [String]?
      let providesApis: [String]?
      let consumesApis: [String]?
    }
    let apiVersion: String
    let kind: String
    let metadata: Metadata
    let spec: Spec?
  }
  private struct Entry {
    let record: Record
    let namespace: String
    let ref: String
    let anchor: SourceAnchor
    let evidenceID: String
  }

  private(set) var nodes: [Entity] = []
  private(set) var facts: [Fact] = []
  private(set) var evidence: [Evidence] = []
  private(set) var diagnostics: [Diagnostic] = []

  private static func identifier(_ value: String) -> Bool {
    value.range(of: #"^[a-z0-9]([a-z0-9._-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
  }

  private static func reference(_ raw: String, kind: String?, namespace: String) -> String? {
    let parts = raw.lowercased().components(separatedBy: ":")
    guard parts.count <= 2, let type = parts.count == 2 ? parts.first : kind,
      ["system", "component", "resource", "domain", "api"].contains(type), let path = parts.last else { return nil }
    let names = path.components(separatedBy: "/")
    guard names.count <= 2, names.allSatisfy(identifier), let name = names.last else { return nil }
    return type + ":" + (names.count == 2 ? names[0] : namespace) + "/" + name
  }

  init(workspaceID: String, inputs: [SourceInput], contextDigest: String) throws {
    var entries: [String: [Entry]] = [:]
    func identity(_ key: String) -> String { CanonicalJSON.identity(workspaceID + ":backstage:" + key) }
    for input in inputs {
      try Task.checkCancellation()
      do {
        guard input.bytes.count <= 256 * 1024, let text = String(data: input.bytes, encoding: .utf8)
        else { throw ArchitectureError("INVALID_CATALOG", "Catalog exceeds 256 KiB or is not UTF-8.") }
        let parser = try Parser(yaml: text)
        var local: [Entry] = []
        var index = 0
        while let node = try parser.nextRoot() {
          index += 1
          guard index <= 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Catalog exceeds 1024 documents.") }
          let record = try YAMLDecoder().decode(Record.self, from: node)
          guard record.apiVersion == "backstage.io/v1alpha1" else {
            throw ArchitectureError("UNSUPPORTED_CATALOG", "Unsupported catalog API version.")
          }
          let kind = record.kind.lowercased()
          guard ["component", "system", "resource", "domain", "api"].contains(kind) else { continue }
          let namespace = (record.metadata.namespace ?? "default").lowercased()
          let name = record.metadata.name.lowercased()
          guard Self.identifier(namespace), Self.identifier(name) else {
            throw ArchitectureError("INVALID_CATALOG", "Invalid catalog entity reference.")
          }
          let ref = kind + ":" + namespace + "/" + name
          local.append(Entry(record: record, namespace: namespace, ref: ref,
            anchor: input.anchor(0, input.bytes.count),
            evidenceID: identity("record:" + input.path + ":" + String(index) + ":" + input.digest)))
        }
        for entry in local { entries[entry.ref, default: []].append(entry) }
      } catch {
        diagnostics.append(Diagnostic("C4_CATALOG_INVALID", "Cannot resolve catalog: " + input.path, scope: input.path))
      }
    }
    var unique: [String: Entry] = [:]
    for (ref, matches) in entries {
      guard matches.count == 1 else {
        diagnostics.append(Diagnostic("C4_AMBIGUOUS", "Multiple catalog records declare " + ref))
        continue
      }
      let entry = matches[0]
      unique[ref] = entry
      evidence.append(Evidence(id: entry.evidenceID, producer: Self.producer,
        inputDigest: entry.anchor.digest, contextDigest: contextDigest, basis: "designDeclared", anchor: entry.anchor))
    }
    func areas(of entry: Entry) -> [JSONValue] {
      var result: [JSONValue] = []
      var seen: Set<String> = []
      var current = entry
      var next = current.record.spec?.domain
      while let raw = next {
        guard let ref = Self.reference(raw, kind: "domain", namespace: current.namespace),
          ref.hasPrefix("domain:"), let domain = unique[ref], seen.insert(ref).inserted,
          seen.count <= 32 else {
          diagnostics.append(Diagnostic("C4_UNRESOLVED", "Unresolved domain chain of " + entry.ref, scope: entry.anchor.path))
          return []
        }
        result.append(.object(["id": .string(identity(ref)), "name": .string(domain.record.metadata.title ?? domain.record.metadata.name)]))
        current = domain
        next = domain.record.spec?.subdomainOf
      }
      return result.reversed()
    }
    func system(_ entry: Entry) -> Entry? {
      if entry.ref.hasPrefix("system:") { return entry }
      guard let raw = entry.record.spec?.system,
        let ref = Self.reference(raw, kind: "system", namespace: entry.namespace),
        ref.hasPrefix("system:") else { return nil }
      return unique[ref]
    }
    struct Link: Hashable {
      let source: String
      let target: String
      let operation: String
      let artifact: String
    }
    var links: [Link: Set<String>] = [:]
    var providers: [String: [Entry]] = [:]
    func apiRef(_ raw: String, _ entry: Entry) -> String? {
      guard let ref = Self.reference(raw, kind: "api", namespace: entry.namespace),
        ref.hasPrefix("api:"), unique[ref] != nil else { return nil }
      return ref
    }
    let components = unique.values.filter { $0.ref.hasPrefix("component:") }
    var runtimeIDs = Set<String>()
    var containerCounts: [String: Int] = [:]
    for entry in unique.values {
      let type = entry.record.spec?.type?.lowercased() ?? ""
      let store = entry.ref.hasPrefix("resource:") && ["database", "cache", "queue", "object-storage"].contains(type)
      let application = entry.ref.hasPrefix("component:") && ["service", "website", "mobile-app", "worker", "api-gateway"].contains(type)
      guard store || application, let owner = system(entry) else { continue }
      runtimeIDs.insert(entry.ref)
      containerCounts[owner.ref, default: 0] += 1
      nodes.append(Entity(id: identity(entry.ref), kind: store ? "dataStore" : "application",
        language: "none", name: entry.record.metadata.title ?? entry.record.metadata.name,
        identityKey: entry.ref, entityRevision: entry.anchor.digest, anchor: entry.anchor,
        attributes: ["context.ref": .string(entry.ref), "context.owner": .string(identity(owner.ref)),
          "context.catalogType": .string(type),
          "context.purpose": .string(entry.record.metadata.description ?? "")]))
    }
    for entry in unique.values where entry.ref.hasPrefix("system:") {
      nodes.append(Entity(id: identity(entry.ref), kind: "softwareSystem", language: "none",
        name: entry.record.metadata.title ?? entry.record.metadata.name, identityKey: entry.ref,
        entityRevision: entry.anchor.digest, anchor: entry.anchor,
        attributes: ["context.ref": .string(entry.ref), "context.areas": .array(areas(of: entry)),
          "context.containerCount": .number(Double(containerCounts[entry.ref] ?? 0)),
          "context.purpose": .string(entry.record.metadata.description ?? "")]))
    }
    var interiors: [String: [Link: Set<String>]] = [:]
    func interior(_ from: Entry, _ to: Entry, _ source: Entry, _ target: Entry, _ operation: String,
      _ artifact: String, _ evidence: [String]) {
      for owner in Set([source.ref, target.ref]) {
        let start = source.ref == owner && runtimeIDs.contains(from.ref) ? from.ref : source.ref
        let end = target.ref == owner && runtimeIDs.contains(to.ref) ? to.ref : target.ref
        guard start != end else { continue }
        let link = Link(source: start, target: end, operation: operation, artifact: artifact)
        interiors[identity(owner), default: [:]][link, default: []].formUnion(evidence)
      }
    }
    for provider in components {
      for raw in Set(provider.record.spec?.providesApis ?? []) {
        if let ref = apiRef(raw, provider) {
          providers[ref, default: []].append(provider)
        } else {
          diagnostics.append(Diagnostic("C4_UNRESOLVED", "Unresolved provided API of " + provider.ref, scope: provider.anchor.path))
        }
      }
    }
    for entry in components {
      try Task.checkCancellation()
      for raw in Set(entry.record.spec?.dependsOn ?? []) {
        guard let source = system(entry),
          let targetRef = Self.reference(raw, kind: nil, namespace: entry.namespace),
          !targetRef.hasPrefix("api:"), let targetEntry = unique[targetRef], let target = system(targetEntry) else {
          diagnostics.append(Diagnostic("C4_UNRESOLVED", "Unresolved catalog dependency of " + entry.ref, scope: entry.anchor.path))
          continue
        }
        interior(entry, targetEntry, source, target, "dependsOn", "",
          [entry.evidenceID, source.evidenceID, targetEntry.evidenceID, target.evidenceID])
        guard source.ref != target.ref else { continue }
        let link = Link(source: source.ref, target: target.ref, operation: "dependsOn", artifact: "")
        links[link, default: []].formUnion([entry.evidenceID, source.evidenceID, targetEntry.evidenceID, target.evidenceID])
      }
      for raw in Set(entry.record.spec?.consumesApis ?? []) {
        guard let source = system(entry), let ref = apiRef(raw, entry), let api = unique[ref],
          let matches = providers[ref], matches.count == 1, let provider = matches.first,
          let target = system(provider) else {
          diagnostics.append(Diagnostic("C4_UNRESOLVED", "Missing or ambiguous catalog API provider for " + entry.ref, scope: entry.anchor.path))
          continue
        }
        interior(entry, provider, source, target, "consumesApi", ref,
          [source.evidenceID, entry.evidenceID, api.evidenceID, provider.evidenceID, target.evidenceID])
        guard source.ref != target.ref else { continue }
        let link = Link(source: source.ref, target: target.ref, operation: "consumesApi", artifact: ref)
        links[link, default: []].formUnion([source.evidenceID, entry.evidenceID, api.evidenceID, provider.evidenceID, target.evidenceID])
      }
    }
    interiors["workspace"] = links
    for (scope, scopedLinks) in interiors {
      for (link, ids) in scopedLinks {
        let supports = ids.sorted()
        let key = [link.operation, link.source, link.target, link.artifact].joined(separator: "|")
        let label = link.operation == "dependsOn" ? "Depends on" : "Uses " + link.artifact
        facts.append(Fact(id: identity(scope == "workspace" ? key : scope + "|" + key), producer: Self.producer, scope: scope,
          kind: link.operation, source: identity(link.source), target: identity(link.target),
          revision: CanonicalJSON.identity(supports.joined(separator: ":")), evidenceIDs: supports,
          attributes: ["context.operation": .string(label)]))
      }
    }
    diagnostics.sort { ($0.scope, $0.message) < ($1.scope, $1.message) }
  }
}
