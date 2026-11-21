import ArchitectureCore
import ArchitectureIR
import Foundation

public struct ActionIntent: Codable, Sendable, Equatable {
  public let requestID: String
  public let registrationID: String
  public let sessionID: String
  public let providerID: String
  public let actionID: String
  public let actionDefinitionDigest: String
  public let inputSchemaID: String
  public let effect: String
  public let binding: ExtensionBinding
  public let arguments: JSONValue
  public let requestedAt: Double
  public let deadline: Double
  public let idempotencyKey: String
  public let requestFingerprint: String
  public let authorizationToken: String
  public init(requestID: String, registrationID: String, sessionID: String, providerID: String, actionID: String, actionDefinitionDigest: String, inputSchemaID: String, effect: String, binding: ExtensionBinding, arguments: JSONValue, requestedAt: Double, deadline: Double, idempotencyKey: String, authorizationToken: String = "") throws {
    self.requestID = requestID; self.registrationID = registrationID; self.sessionID = sessionID; self.providerID = providerID; self.actionID = actionID; self.actionDefinitionDigest = actionDefinitionDigest; self.inputSchemaID = inputSchemaID; self.effect = effect; self.binding = binding; self.arguments = arguments; self.requestedAt = requestedAt; self.deadline = deadline; self.idempotencyKey = idempotencyKey; self.authorizationToken = authorizationToken
    self.requestFingerprint = try Self.fingerprint(requestID: requestID, providerID: providerID, actionID: actionID, definition: actionDefinitionDigest, schema: inputSchemaID, effect: effect, binding: binding, arguments: arguments, deadline: deadline)
  }
  public func verifiedFingerprint() throws -> String {
    try Self.fingerprint(requestID: requestID, providerID: providerID, actionID: actionID, definition: actionDefinitionDigest, schema: inputSchemaID, effect: effect, binding: binding, arguments: arguments, deadline: deadline)
  }
  private static func fingerprint(requestID: String, providerID: String, actionID: String, definition: String, schema: String, effect: String, binding: ExtensionBinding, arguments: JSONValue, deadline: Double) throws -> String {
    let value: JSONValue = .object(["requestID": .string(requestID), "providerID": .string(providerID), "actionID": .string(actionID), "definition": .string(definition), "schema": .string(schema), "effect": .string(effect), "binding": try JSONValue.encode(binding), "arguments": arguments, "deadline": .number(deadline)])
    return CanonicalJSON.digest(try CanonicalJSON.encode(value))
  }
}
