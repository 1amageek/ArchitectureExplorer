import ArchitectureCore
import ArchitectureIR
import Foundation

public enum ExtensionPermission: String, Codable, Sendable, CaseIterable {
  case canvasRead = "canvas.read", canvasControl = "canvas.control"
  case graphRead = "graph.read", eventsSubscribe = "events.subscribe", inputsRead = "inputs.read"
  case annotationsWrite = "annotations.write.own", graphsWrite = "extensionGraphs.write.own"
  case viewsWrite = "views.write.own", runsWrite = "runs.write.own", actionsReceive = "actions.receive"
}
