import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ExtensionActionDefinition: Codable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let operation: String
  public let effect: String
  public let requiresConfirmation: Bool
  public let inputSchemaID: String
  public let inputSchema: JSONValue
  public init(id: String, title: String, operation: String = "execute", effect: String = "externalExecution", requiresConfirmation: Bool = true, inputSchemaID: String = "arguments.v1", inputSchema: JSONValue = .object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)])) {
    self.id = id; self.title = title; self.operation = operation; self.effect = effect; self.requiresConfirmation = requiresConfirmation; self.inputSchemaID = inputSchemaID; self.inputSchema = inputSchema
  }
}
