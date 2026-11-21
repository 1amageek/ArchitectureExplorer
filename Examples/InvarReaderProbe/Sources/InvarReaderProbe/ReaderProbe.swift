import ArchitectureClient
import ArchitectureCore
import ArchitectureExtensions
import Foundation
import VerificationExplorer

/// Executes the real Invar input adapter with an explicitly approved Explorer session.
@main struct ReaderProbe {
  static func main() async {
    do {
      guard CommandLine.arguments.count == 2 else { throw ArchitectureError("INVALID_ARGUMENT", "Usage: InvarReaderProbe WORKSPACE", exitCode: 2) }
      let manifest = ExtensionManifest(extensionID: "local.example.invar-reader", displayName: "Invar reader integration probe", requestedPermissions: [.graphRead, .inputsRead])
      var session: ExtensionProviderClient?
      while session == nil {
        do { session = try await ExtensionProviderClient.register(workspace: CommandLine.arguments[1], manifest: manifest) }
        catch let error as ArchitectureError where error.code == "APPROVAL_REQUIRED" {
          FileHandle.standardOutput.write(Data("Approval required\n".utf8)); try await Task.sleep(for: .seconds(1))
        }
      }
      let provider = session!
      do {
        let captured = try await ExplorerSnapshotReader(client: provider.client).capture()
        let value: JSONValue = .object(["state": .string("captured"), "snapshotID": .string(captured.inventory.snapshotID), "files": .number(Double(captured.files.count)), "entities": .number(Double(captured.inventory.entities.count)), "facts": .number(Double(captured.inventory.facts.count))])
        FileHandle.standardOutput.write(try CanonicalJSON.encode(value) + Data([10]))
        try await provider.disconnect()
      } catch { let original = error; do { try await provider.disconnect() } catch { throw ArchitectureError("SESSION_CLEANUP_FAILED", "Capture failed (\(original)); disconnect failed (\(error)).", exitCode: 7) }; throw original }
    } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
  }
}
