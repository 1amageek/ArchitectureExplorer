import ArchitectureCore
import Foundation

enum CanvasXMIReader {
  typealias Element = CanvasXMLTree.Element
  static func read(_ root: Element, into builder: CanvasBuilder) throws {
    guard ["XMI", "Model", "Package"].contains(root.local) else { throw CanvasSyntax.invalid("Expected UML 2 XMI Model/Package.") }
    let types: Set<String> = ["Model", "Package", "Class", "Interface", "Enumeration", "DataType", "PrimitiveType", "Property", "Operation", "Parameter", "EnumerationLiteral", "StateMachine", "Region", "State", "Pseudostate", "FinalState", "Interaction", "Lifeline", "MessageOccurrenceSpecification", "ExecutionOccurrenceSpecification", "Message", "Generalization", "Dependency", "Association", "Realization", "InterfaceRealization", "Transition"]
    let wrappers: Set<String> = ["XMI", "ownedComment", "eAnnotations", "details", "body", "type", "lowerValue", "upperValue", "defaultValue", "guard", "specification", "effect", "trigger", "ownedRule", "ownedEnd"]
    func type(_ e: Element) -> String { let value = e.attributes.first { $0.key.hasSuffix(":type") }?.value ?? e.local; return String(value.split(separator: ":").last ?? Substring(value)) }
    var entries: [(Element, String?, String)] = [], identifiers = Set<String>()
    func walk(_ e: Element, parent: String?) throws {
      if ["ownedComment", "eAnnotations", "details", "body", "type", "lowerValue", "upperValue", "defaultValue", "guard", "specification", "effect", "trigger", "ownedRule", "ownedEnd"].contains(e.local) { return }
      let kind = type(e), id = e.attribute("id")
      if let href = e.attributes["href"], !href.hasPrefix("#") { throw CanvasSyntax.unsupported("External UML references require a separate resolver.") }
      guard types.contains(kind) || wrappers.contains(e.local) else { throw CanvasSyntax.unsupported("Unsupported UML XMI element/type: \(kind)") }
      if let id { guard identifiers.insert(id).inserted else { throw CanvasSyntax.invalid("Duplicate XMI identity: \(id)") }; entries.append((e, parent, kind)) }
      for child in e.children { try walk(child, parent: id ?? parent) }
    }
    try walk(root, parent: nil)
    let sequence = entries.contains { $0.2 == "Interaction" }, states = entries.contains { $0.2 == "StateMachine" }
    if sequence && states { throw CanvasSyntax.unsupported("Import UML interactions and state machines as separate diagram documents.") }
    builder.document.kind = sequence ? "sequence" : states ? "stateTransition" : "hierarchy"
    let structural: Set<String> = ["Model", "Package", "Class", "Interface", "Enumeration", "DataType", "PrimitiveType", "Property", "Operation", "Parameter", "EnumerationLiteral", "StateMachine", "Region", "State", "Pseudostate", "FinalState"]
    if sequence {
      let allowed: Set<String> = ["Model", "Package", "Interaction", "Lifeline", "MessageOccurrenceSpecification", "ExecutionOccurrenceSpecification", "Message"]
      guard entries.allSatisfy({ allowed.contains($0.2) }) else { throw CanvasSyntax.unsupported("The interaction profile cannot mix class/state diagrams.") }
    }
    for (element, parent, kind) in entries {
      guard let id = element.attribute("id") else { continue }
      if kind == "Lifeline" { try builder.lane(id, label: element.attributes["name"]); continue }
      if ["MessageOccurrenceSpecification", "ExecutionOccurrenceSpecification"].contains(kind) {
        guard let covered = element.attributes["covered"], !covered.contains(" ") else { throw CanvasSyntax.unsupported("UML occurrences require one covered lifeline.") }
        builder.document.nodes.append(CanvasNode(id: id, label: element.attributes["name"] ?? "Event", role: "event", laneID: covered, order: Double(builder.document.nodes.count), details: element.literal)); continue
      }
      if structural.contains(kind) && !sequence {
        let role = kind == "Pseudostate" ? element.attributes["kind"] ?? "initial" : kind == "FinalState" ? "final" : kind.lowercased()
        try builder.node(id, label: element.attributes["name"] ?? id, role: role, parent: parent, details: element.literal)
      }
    }
    for (element, owner, kind) in entries {
      if kind == "Message" {
        guard let source = element.attributes["sendEvent"], let target = element.attributes["receiveEvent"] else { throw CanvasSyntax.invalid("UML message event endpoints are missing.") }
        let label = element.attributes["name"] ?? "Message"
        try builder.edge(source, target, label: label, role: "message", details: element.literal)
        for i in builder.document.nodes.indices where builder.document.nodes[i].id == source || builder.document.nodes[i].id == target { builder.document.nodes[i].label = label }
      } else if kind == "Transition" {
        guard let source = element.attributes["source"], let target = element.attributes["target"] else { throw CanvasSyntax.invalid("UML transition endpoints are missing.") }
        try builder.edge(source, target, label: element.attributes["name"] ?? element.descendants("body").first?.content ?? "", role: "transition", details: element.literal)
      } else if ["Generalization", "Dependency", "Realization", "InterfaceRealization"].contains(kind) {
        let sources = (element.attributes["client"] ?? element.attributes["specific"] ?? owner ?? "").split(separator: " ").map(String.init)
        let targets = (element.attributes["supplier"] ?? element.attributes["general"] ?? element.attributes["contract"] ?? "").split(separator: " ").map(String.init)
        guard !sources.isEmpty, !targets.isEmpty else { throw CanvasSyntax.invalid("UML dependency endpoints are missing.") }
        for a in sources { for b in targets { try builder.edge(a, b, label: element.attributes["name"] ?? "", role: kind.lowercased(), details: element.literal) } }
      } else if kind == "Association" {
        let ends = element.children.filter { $0.local == "ownedEnd" }.compactMap { $0.attributes["type"] }
        guard ends.count == 2 else { throw CanvasSyntax.unsupported("UML association profile requires two ownedEnd type references.") }
        try builder.edge(ends[0], ends[1], label: element.attributes["name"] ?? "", role: "association", directed: false, details: element.literal)
      }
    }
    if let title = entries.first(where: { $0.2 == "Interaction" || $0.2 == "StateMachine" || $0.2 == "Model" })?.0.attributes["name"] { builder.document.title = title }
  }
}
