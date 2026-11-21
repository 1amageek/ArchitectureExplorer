import ArchitectureCore
import ArchitectureIR
import Foundation

public struct SemanticProvider: Sendable {
  public init() {}
  public func query(
    input: SourceInput, workspace: URL, executable: String, operation: String, byteOffset: Int,
    trusted: Bool
  ) async throws -> JSONValue {
    guard trusted else {
      throw ArchitectureError(
        "WORKSPACE_TRUST_REQUIRED",
        "Language servers can prepare builds and execute project code; explicit workspace trust is required.",
        exitCode: 5)
    }
    let methods = [
      "definition": ("definitionProvider", "textDocument/definition"),
      "references": ("referencesProvider", "textDocument/references"),
      "incomingCalls": ("callHierarchyProvider", "callHierarchy/incomingCalls"),
      "outgoingCalls": ("callHierarchyProvider", "callHierarchy/outgoingCalls"),
    ]
    guard let (capability, method) = methods[operation] else {
      throw ArchitectureError("UNSUPPORTED_CAPABILITY", "Unknown semantic operation.", exitCode: 3)
    }
    let process = try LSPProcess(executable: executable, workspace: workspace)
    do {
      let initialize: JSONValue = .object([
        "processId": .number(Double(ProcessInfo.processInfo.processIdentifier)),
        "rootUri": .string(workspace.absoluteString),
        "capabilities": .object([
          "general": .object(["positionEncodings": .array([.string("utf-16")])])
        ]), "initializationOptions": .object(["backgroundIndexing": .bool(false)]),
        "workspaceFolders": .array([
          .object([
            "uri": .string(workspace.absoluteString), "name": .string(workspace.lastPathComponent),
          ])
        ]),
      ])
      let result = try await process.request("initialize", params: initialize)
      let capabilities = result["capabilities"]
      guard
        capabilities["positionEncoding"] == .null
          || capabilities["positionEncoding"].string == "utf-16"
      else {
        throw ArchitectureError(
          "UNSUPPORTED_CAPABILITY", "Provider negotiated an unsupported position encoding.",
          exitCode: 3)
      }
      guard capabilities[capability] != .null, capabilities[capability] != .bool(false) else {
        throw ArchitectureError(
          "UNSUPPORTED_CAPABILITY", "Provider does not advertise \(operation).", exitCode: 3)
      }
      try await process.notify("initialized", params: .object([:]))
      let uri = workspace.appendingPathComponent(input.path).absoluteString
      try await process.notify(
        "textDocument/didOpen",
        params: .object([
          "textDocument": .object([
            "uri": .string(uri), "languageId": .string(input.language),
            "version": .number(Double(input.generation)),
            "text": .string(String(decoding: input.bytes, as: UTF8.self)),
          ])
        ]))
      let position = try SourcePositions.lspPosition(input.bytes, byteOffset: byteOffset)
      var params: JSONValue = .object([
        "textDocument": .object(["uri": .string(uri)]), "position": position,
        "context": .object(["includeDeclaration": .bool(true)]),
      ])
      if operation.hasSuffix("Calls") {
        let items = try await process.request("textDocument/prepareCallHierarchy", params: params)
        guard items.array.count == 1, let item = items.array.first else {
          throw ArchitectureError(
            "AMBIGUOUS_BINDING", "Call hierarchy did not identify exactly one callable.",
            exitCode: 3)
        }
        params = .object(["item": item])
      }
      let data = try await process.request(method, params: params)
      try await process.shutdown()
      return .object([
        "provider": .string(executable), "providerInfo": result["serverInfo"],
        "capabilities": capabilities,
        "operation": .string(operation), "basis": .string("semantic"),
        "freshness": .string("unknown"), "completeness": .string("partial"),
        "inputDigest": .string(input.digest), "contextDigest": .string(input.contextDigest),
        "data": data,
        "diagnostics": .array([
          .object([
            "code": .string("STALE_ANALYSIS"),
            "message": .string(
              "The server reads live dependency files; whole-project input consistency has not been established."
            ),
          ])
        ]),
      ])
    } catch {
      try await process.shutdown()
      throw error
    }
  }
}
