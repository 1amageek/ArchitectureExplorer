import ArchitectureCore
import Foundation
import Yams

/// Projects only explicitly declared relationships. Files are provenance and drill-down targets.
public enum RepositoryArchitecture {
  struct Graph {
    var nodes: [String: JSONValue] = [:]
    var edges: [String: JSONValue] = [:]
    var notice = ""
    mutating func node(_ id: String, _ label: String, _ role: String, _ evidence: String,
      service: String? = nil, language: String? = nil, source: [String]? = nil) {
      var value: [String: JSONValue] = ["id": .string(id), "label": .string(label), "role": .string(role),
        "details": .object(["status": .string(evidence), "evidence": .string(evidence)])]
      if let service { value["service"] = .string(service) }
      if let language { value["language"] = .string(language) }
      if let source { value["sourcePath"] = .array(source.map(JSONValue.string)) }
      nodes[id] = .object(value)
    }
    mutating func edge(_ from: String, _ to: String, _ label: String, _ role: String, _ evidence: String) {
      let id = "edge:" + CanonicalJSON.identity([from, to, label].joined(separator: "\u{0}"))
      edges[id] = .object(["id": .string(id), "source": .string(from), "target": .string(to),
        "label": .string(label), "role": .string(role), "directed": .bool(true),
        "details": .object(["evidence": .string(evidence)])])
    }
    func view(_ title: String, _ mode: String, checkout: String) throws -> JSONValue {
      guard nodes.count <= 250, edges.count <= 500 else {
        throw ArchitectureError("RESOURCE_LIMIT", "Architecture exceeds the 250-node or 500-relation view budget.")
      }
      return .object(["title": .string(title), "checkout": .string(checkout), "architecture": .string(mode),
        "nodes": .array(nodes.keys.sorted().compactMap { nodes[$0] }), "edges": .array(edges.keys.sorted().compactMap { edges[$0] }),
        "outlineNotice": .string(notice)])
    }
  }

  public static func view(map: RepositoryMap, parameters: JSONValue) throws -> JSONValue {
    let scope = try map.browse(parameters)
    guard scope["directory"].bool == true, let repo = scope["repo"].string, let checkout = scope["checkout"].string else {
      return RepositoryOutline.annotate(scope)
    }
    func read(_ path: [String]) throws -> String? {
      guard let input = try map.input(repo: repo, path: path) else { return nil }
      guard input["truncated"].bool == false else { throw ArchitectureError("RESOURCE_LIMIT", path.joined(separator: "/") + " exceeds the 16 KiB input budget.") }
      return input["text"].string
    }
    for name in ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"] {
      guard let yaml = try read([name]) else { continue }
      guard let doc = try Yams.compose(yaml: yaml), let services = doc["services"]?.mapping, !services.isEmpty else {
        throw ArchitectureError("INVALID_MANIFEST", "Compose services are missing from " + name)
      }
      if let service = parameters["service"].string {
        guard let config = services[service] else { throw ArchitectureError("UNKNOWN_SERVICE", "Service is no longer declared.") }
        if let path = try entrySource(config, checkout: checkout, read: read), let source = try read(path) {
          return try RepositoryComposition.project(service: service, checkout: checkout, path: path, source: source)
        }
        var graph = Graph()
        graph.notice = "Source composition unresolved: no supported local entry point was established for this service."
        graph.node("service:"+service, service, "Compose service", name + " · services." + service)
        return try graph.view(service, "Service composition", checkout: checkout)
      }
      var graph = Graph()
      for (key, config) in services {
        guard let service = key.string else { continue }
        let id = "service:" + service, origin = name + " · services." + service
        graph.node(id, service, "Compose service", origin, service: service)
        for dependency in names(config["depends_on"]) {
          guard services[dependency] != nil else { graph.notice = "Some service dependencies are unresolved."; continue }
          let condition = config["depends_on"]?[dependency]?["condition"]?.string
          let label = condition == "service_healthy" ? "Requires healthy service" : "Depends on"
          graph.edge(id, "service:" + dependency, label, "dependsOn", origin + ".depends_on." + dependency + (condition.map { " · " + $0 } ?? ""))
        }
        for network in names(config["networks"]) {
          let declared = doc["networks"]?[network] != nil
          graph.node("network:"+network, network, declared ? "Network" : "Referenced network", declared ? name + " · networks." + network : origin + ".networks")
          graph.edge(id, "network:"+network, "Joins", "joinsNetwork", origin + ".networks")
        }
        for mount in config["volumes"]?.sequence ?? [] {
          let fields = mount.string?.split(separator: ":")
          let volume = mount["type"]?.string == "volume" ? mount["source"]?.string : (fields?.count ?? 0) >= 2 ? fields?.first.map(String.init) : nil
          if let volume, doc["volumes"]?[volume] != nil {
            graph.node("volume:"+volume, volume, "Volume", name + " · volumes." + volume)
            graph.edge(id, "volume:"+volume, "Mounts", "mountsVolume", origin + ".volumes")
          }
        }
      }
      return try graph.view(checkout, "Deployment architecture", checkout: checkout)
    }
    var graph = Graph()
    if let manifest = try read(["package.json"]) {
      let value = try JSONDecoder().decode(JSONValue.self, from: Data(manifest.utf8))
      let package = value["name"].string ?? checkout
      graph.node("package", package, "Package", "package.json")
      let exports = value["exports"].object
      let subpaths = exports.keys.filter { $0.hasPrefix(".") }.sorted()
      let endpoints = subpaths.isEmpty && (value["exports"] != .null || value["main"].string != nil) ? ["."] : subpaths
      var compilerConfig: String?
      if !endpoints.isEmpty {
        do { compilerConfig = try read(["tsconfig.json"]) }
        catch { graph.notice = "Entry source mapping unavailable: " + String(describing: error) }
      }
      for endpoint in endpoints {
        let id = "export:" + endpoint
        let spec = subpaths.isEmpty ? value["exports"] : value["exports"][endpoint]
        let target = spec.string ?? spec["import"].string ?? spec["default"].string ?? (value["exports"] == .null ? value["main"].string : nil)
        var path: [String]?
        if let target, let compilerConfig {
          do { path = try sourcePath(output: target, config: compilerConfig) }
          catch { graph.notice = "Entry source mapping unavailable: invalid compiler configuration." }
        }
        let evidence = value["exports"] == .null ? "package.json · main" : "package.json · exports " + endpoint
        graph.node(id, endpoint == "." ? package : String(endpoint.dropFirst(2)), "Public entry point", evidence, source: path)
        graph.edge("package", id, "Exports", "exports", evidence)
      }
      for dependency in value["dependencies"].object.keys.sorted() {
        let id = "package:" + dependency, evidence = "package.json · dependencies." + dependency
        graph.node(id, dependency, "Package dependency", evidence)
        graph.edge("package", id, "Depends on", "dependsOn", evidence)
      }
      return try graph.view(checkout, "Package architecture", checkout: checkout)
    }
    graph.notice = "No supported deployment or package declarations for this repository."
    return try graph.view(checkout, "Architecture unresolved", checkout: checkout)
  }

  private static func names(_ node: Node?) -> [String] {
    node?.mapping?.keys.compactMap(\.string) ?? node?.sequence?.compactMap(\.string) ?? []
  }

  private static func sourcePath(output: String, config: String?) throws -> [String]? {
    guard let config else { return nil }
    let decoder = JSONDecoder(); decoder.allowsJSON5 = true
    let options = try decoder.decode(JSONValue.self, from: Data(config.utf8))["compilerOptions"]
    func parts(_ path: String) -> [String] { path.split(separator: "/").map(String.init).filter { $0 != "." } }
    guard let root = options["rootDir"].string, let out = options["outDir"].string,
          ![root, out, output].contains(where: { $0.hasPrefix("/") || parts($0).contains("..") }),
          output.hasSuffix(".js"), parts(output).starts(with: parts(out)) else { return nil }
    let path = parts(root) + parts(output).dropFirst(parts(out).count)
    guard let last = path.last else { return nil }
    return Array(path.dropLast()) + [String(last.dropLast(3)) + ".ts"]
  }

  private static func entrySource(_ service: Node, checkout: String,
    read: ([String]) throws -> String?) throws -> [String]? {
    guard service["entrypoint"] == nil, service["command"] == nil, let build = service["build"],
          let stage = build["target"]?.string else { return nil }
    let context = build["context"]?.string ?? ".", file = build["dockerfile"]?.string ?? "Dockerfile"
    guard (context == "." && file == "Dockerfile") || (context == ".." && file == checkout + "/Dockerfile"),
          let docker = try read(["Dockerfile"]) else { return nil }
    var active = false, target: String?
    for line in docker.split(whereSeparator: \.isNewline) {
      let words = line.split(whereSeparator: \.isWhitespace)
      if words.first?.uppercased() == "FROM" { active = words.count == 4 && words[2].uppercased() == "AS" && String(words[3]) == stage }
      if active, words.first?.uppercased() == "ENTRYPOINT" {
        target = nil
        let raw = words.dropFirst().joined(separator: " ")
        guard raw.first == "[" else { continue }
        let command = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
        if command.count == 2, command[0] == "node" { target = command[1] }
      }
    }
    guard let target else { return nil }
    return try sourcePath(output: target, config: read(["tsconfig.json"]))
  }
}
