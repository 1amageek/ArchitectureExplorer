import ArchitectureCore
import Foundation

public enum ExtensionRules {
  private static func number(_ value: JSONValue) -> Double? { if case .number(let number) = value { return number }; return nil }
  public static let viewKinds: Set<String> = ["text", "table", "keyValue", "artifactList", "graph", "timeline", "overlay"]
  public static func schema(_ schema: JSONValue, value: JSONValue? = nil, depth: Int = 0) throws {
    guard depth < 8, schema.object.count > 0, schema.object.count <= 12 else { throw ArchitectureError("INVALID_SCHEMA", "Schema depth/object budget exceeded.", exitCode: 2) }
    let allowed: Set<String> = ["type", "properties", "required", "additionalProperties", "items", "enum", "minimum", "maximum", "minLength", "maxLength", "maxItems"]
    guard Set(schema.object.keys).isSubset(of: allowed), let type = schema["type"].string, ["object", "array", "string", "number", "integer", "boolean", "null"].contains(type) else { throw ArchitectureError("INVALID_SCHEMA", "Unsupported schema keyword/type.", exitCode: 2) }
    for key in ["minLength", "maxLength", "maxItems"] where schema[key] != .null {
      guard let limit = schema[key].int, limit >= 0, limit <= (key == "maxItems" ? 256 : 4096) else { throw ArchitectureError("INVALID_SCHEMA", "Invalid schema bound.", exitCode: 2) }
    }
    if schema["properties"] != .null { guard case .object = schema["properties"] else { throw ArchitectureError("INVALID_SCHEMA", "Properties must be an object.", exitCode: 2) } }
    if schema["required"] != .null { guard case .array = schema["required"], Set(schema["required"].array.compactMap(\.string)).count == schema["required"].array.count else { throw ArchitectureError("INVALID_SCHEMA", "Required must contain unique property names.", exitCode: 2) } }
    if schema["enum"] != .null { guard case .array = schema["enum"], !schema["enum"].array.isEmpty else { throw ArchitectureError("INVALID_SCHEMA", "Enum must be a nonempty array.", exitCode: 2) } }
    guard schema["properties"].object.count <= 64, schema["enum"].array.count <= 64 else { throw ArchitectureError("RESOURCE_LIMIT", "Schema member budget exceeded.", exitCode: 6) }
    if type == "object" {
      guard schema["additionalProperties"].bool == false else { throw ArchitectureError("INVALID_SCHEMA", "Objects must reject additional properties.", exitCode: 2) }
      for child in schema["properties"].object.values { try self.schema(child, depth: depth + 1) }
      guard schema["required"].array.allSatisfy({ $0.string != nil && schema["properties"].object[$0.string!] != nil }) else { throw ArchitectureError("INVALID_SCHEMA", "Required properties must be declared.", exitCode: 2) }
    }
    if type == "array" { try self.schema(schema["items"], depth: depth + 1) }
    guard let value else { return }
    let valid: Bool
    switch (type, value) {
    case ("object", .object(let fields)):
      valid = Set(fields.keys).isSubset(of: Set(schema["properties"].object.keys)) && schema["required"].array.allSatisfy { fields[$0.string!] != nil }
      if valid { for (key, child) in fields { try self.schema(schema["properties"][key], value: child, depth: depth + 1) } }
    case ("array", .array(let items)):
      valid = items.count <= min(schema["maxItems"].int ?? 256, 256)
      if valid { for item in items { try self.schema(schema["items"], value: item, depth: depth + 1) } }
    case ("string", .string(let text)): valid = text.utf8.count <= min(schema["maxLength"].int ?? 4096, 4096) && text.utf8.count >= (schema["minLength"].int ?? 0)
    case ("number", .number(let n)), ("integer", .number(let n)):
      valid = n.isFinite && (type != "integer" || n.rounded() == n) && n >= (number(schema["minimum"]) ?? -Double.greatestFiniteMagnitude) && n <= (number(schema["maximum"]) ?? Double.greatestFiniteMagnitude)
    case ("boolean", .bool): valid = true
    case ("null", .null): valid = true
    default: valid = false
    }
    guard valid, schema["enum"] == .null || schema["enum"].array.contains(value) else { throw ArchitectureError("INVALID_ARGUMENT", "Arguments do not match the registered schema.", exitCode: 2) }
  }
  public static func manifest(_ value: JSONValue) throws -> ExtensionManifest {
    let allowed: Set<String> = ["schemaVersion", "extensionID", "displayName", "version", "extensionAPI", "specificationProfiles", "architectureIRMajors", "requestedPermissions", "views", "actions"]
    guard Set(value.object.keys).isSubset(of: allowed) else { throw ArchitectureError("INVALID_MANIFEST", "Unknown manifest fields.", exitCode: 2) }
    for view in value["views"].array { guard Set(view.object.keys) == ["id", "kind", "title"] else { throw ArchitectureError("INVALID_MANIFEST", "Unknown view declaration fields.", exitCode: 2) } }
    let actionKeys: Set<String> = ["id", "title", "operation", "effect", "requiresConfirmation", "inputSchemaID", "inputSchema"]
    for action in value["actions"].array { guard Set(action.object.keys) == actionKeys else { throw ArchitectureError("INVALID_MANIFEST", "Unknown action declaration fields.", exitCode: 2) } }
    guard Set(value["extensionAPI"].object.keys) == ["major", "minimumMinor"] else { throw ArchitectureError("INVALID_MANIFEST", "Unknown extension API negotiation fields.", exitCode: 2) }
    let manifest = try value.decode(ExtensionManifest.self)
    guard manifest.schemaVersion == "1.0", manifest.extensionAPI.major == 1, manifest.extensionAPI.minimumMinor == 0, manifest.specificationProfiles == ["aex-1.3"], manifest.architectureIRMajors.contains(1) else { throw ArchitectureError("PROTOCOL_MISMATCH", "Extension API/schema/profile/IR mismatch.", exitCode: 7) }
    guard validID(manifest.extensionID), !manifest.displayName.isEmpty, manifest.displayName.utf8.count <= 128, manifest.version.utf8.count <= 64, manifest.views.count <= 16, manifest.actions.count <= 16, Set(manifest.views.map(\.id)).count == manifest.views.count, Set(manifest.actions.map(\.id)).count == manifest.actions.count, Set(manifest.requestedPermissions).count == manifest.requestedPermissions.count, try CanonicalJSON.encode(value).count <= 65536 else { throw ArchitectureError("INVALID_MANIFEST", "Manifest identity/member/byte budget exceeded.", exitCode: 2) }
    for view in manifest.views { guard validID(view.id), viewKinds.contains(view.kind), view.title.utf8.count <= 128 else { throw ArchitectureError("INVALID_MANIFEST", "Unsupported declarative view.", exitCode: 2) } }
    for action in manifest.actions {
      guard validID(action.id), action.effect == "externalExecution", ["execute", "cancel"].contains(action.operation), action.title.utf8.count <= 128, validID(action.inputSchemaID) else { throw ArchitectureError("INVALID_MANIFEST", "External actions require a registered schema and execution effect.", exitCode: 2) }
      try schema(action.inputSchema)
    }
    return manifest
  }
  public static func validID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 160 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0) }
  }
  public static func contribution(_ contribution: ExtensionContribution, provider: ExtensionManifest, binding: ExtensionBinding) throws {
    guard contribution.binding == binding, contribution.id.hasPrefix(provider.extensionID + ":"), try CanonicalJSON.encode(contribution).count <= 1024 * 1024 else { throw ArchitectureError("INVALID_PUBLICATION", "Contribution namespace/binding/byte mismatch.", exitCode: 2) }
    let value = contribution.data
    switch contribution.kind {
    case "annotation":
      let report = try value.decode(ExtensionAnnotation.self)
      guard Set(value.object.keys) == ["reportedStatus", "claim", "scope", "assumptions", "evidence", "translationStatus", "attributes"], report.reportedStatus.utf8.count <= 128, report.claim.utf8.count <= 16384, report.scope.utf8.count <= 4096, report.assumptions.count <= 128, report.evidence.count <= 128, report.attributes.count <= 64 else { throw ArchitectureError("INVALID_PUBLICATION", "Annotation report exceeds its typed contract.", exitCode: 2) }
    case "graph":
      let nodes = value["nodes"].array, edges = value["edges"].array, ids = nodes.compactMap { $0["id"].string }
      guard case .array = value["nodes"], case .array = value["edges"], nodes.count <= 500, edges.count <= 1500, Set(edges.compactMap { $0["id"].string }).count == edges.count, ids.count == nodes.count, Set(ids).count == ids.count, ids.allSatisfy({ $0.hasPrefix(provider.extensionID + ":") }), edges.allSatisfy({ ids.contains($0["source"].string ?? "") && ids.contains($0["target"].string ?? "") && ($0["id"].string?.hasPrefix(provider.extensionID + ":") == true) }) else { throw ArchitectureError("INVALID_PUBLICATION", "External graph identities/endpoints exceed contract.", exitCode: 2) }
    case "view":
      guard let view = provider.views.first(where: { provider.extensionID + ":" + $0.id == contribution.id }), value["kind"].string == view.kind, try CanonicalJSON.encode(value).count <= 65536 else { throw ArchitectureError("INVALID_PUBLICATION", "Unregistered or over-budget view.", exitCode: 2) }
      switch view.kind {
      case "text": guard value["text"].string != nil else { throw ArchitectureError("INVALID_PUBLICATION", "Text view needs literal text.", exitCode: 2) }
      case "table": guard case .array = value["columns"], case .array = value["rows"], value["columns"].array.count <= 32, value["rows"].array.count <= 256, value["columns"].array.allSatisfy({ $0.string != nil }), value["rows"].array.allSatisfy({ row in if case .array(let cells) = row { return cells.count == value["columns"].array.count }; return false }) else { throw ArchitectureError("INVALID_PUBLICATION", "Table columns/rows must be bounded rectangular arrays.", exitCode: 2) }
      case "keyValue": guard case .object = value["values"], value["values"].object.count <= 128 else { throw ArchitectureError("INVALID_PUBLICATION", "Invalid key/value view.", exitCode: 2) }
      case "timeline", "overlay": guard case .array = value["items"], value["items"].array.count <= 256, value["items"].array.allSatisfy({ if case .object = $0 { return true }; return false }) else { throw ArchitectureError("INVALID_PUBLICATION", "Invalid timeline/overlay items.", exitCode: 2) }
      case "artifactList": guard case .array = value["artifacts"], value["artifacts"].array.count <= 128 else { throw ArchitectureError("INVALID_PUBLICATION", "Invalid artifact list.", exitCode: 2) }
      case "graph": try self.contribution(ExtensionContribution(id: contribution.id, kind: "graph", binding: binding, data: value), provider: provider, binding: binding)
      default: break
      }
      for artifact in value["artifacts"].array {
        guard let path = artifact["path"].string, !path.hasPrefix("/"), !path.contains(":"), !path.split(separator: "/").contains(".."), artifact["digest"].string?.count == 64 else { throw ArchitectureError("ARTIFACT_OUTSIDE_ROOT", "Invalid relative artifact reference.", exitCode: 5) }
      }
    default: throw ArchitectureError("UNSUPPORTED_CAPABILITY", "Unknown contribution kind.", exitCode: 3)
    }
  }
}
