import ArchitectureCore
import ArchitectureStore
import Darwin
import Foundation

public actor ArchitectureDaemon {
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var providerTasks: Set<UUID> = []
  private let hostDigests: Set<String>
  private let service: ArchitectureService
  private let paths: WorkspacePaths
  public init(paths: WorkspacePaths, store: any GraphStore, trustedHostDigests: Set<String> = []) throws {
    self.paths = paths
    let identity = try ConnectionPeer.current()
    hostDigests = trustedHostDigests.union([identity.binaryDigest])
    service = ArchitectureService(paths: paths, store: store, trustedHostDigests: hostDigests)
  }
  public func run() async throws {
    ProcessSignals.install()
    let runtime = try LocalSocket.runtimeDirectory(paths.workspaceID)
    let lockPath = runtime.appendingPathComponent("daemon.lock").path
    let lock = Darwin.open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard lock >= 0 else {
      throw ArchitectureError("POLICY_DENIED", "Cannot open daemon lock.", exitCode: 5)
    }
    defer { Darwin.close(lock) }
    guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
      throw ArchitectureError(
        "DAEMON_ALREADY_RUNNING", "Another daemon owns this workspace.", exitCode: 6)
    }
    let socketPath = runtime.appendingPathComponent("rpc.sock").path
    if FileManager.default.fileExists(atPath: socketPath) {
      guard unlink(socketPath) == 0 else {
        throw ArchitectureError(
          "CONNECTION_FAILED", "Cannot replace stale workspace socket.", exitCode: 6)
      }
    }
    let listener = try LocalSocket.listen(path: socketPath)
    defer {
      Darwin.close(listener)
      unlink(socketPath)
    }
    let watch = Task { [service] in
      while !Task.isCancelled {
        await service.refresh()
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
    }
    do {
      try await acceptConnections(listener)
    } catch {
      await shutdown(watch)
      throw error
    }
    await shutdown(watch)
  }

  private func acceptConnections(_ listener: Int32) async throws {
    while !Task.isCancelled, !ProcessSignals.interrupted, !(await service.shouldStop()) {
      let accepted: LocalConnection?
      do {
        accepted = try LocalSocket.accept(listener)
      } catch let error as ArchitectureError where error.code == "PEER_CONNECTION_REJECTED" {
        FileHandle.standardError.write(Data("Rejected IPC peer: \(error.message)\n".utf8))
        try await Task.sleep(for: .milliseconds(5))
        continue
      }
      if let connection = accepted {
        let admissionPeer: ConnectionPeer
        do { admissionPeer = try await connection.peerIdentity() }
        catch { FileHandle.standardError.write(Data("Rejected unidentified IPC peer: \(error)\n".utf8)); await connection.close(); continue }
        let host = hostDigests.contains(admissionPeer.binaryDigest)
        if tasks.count >= 64 || !host && providerTasks.count >= 48 {
          await connection.close()
        } else {
          let id = UUID()
          if !host { providerTasks.insert(id) }
          tasks[id] = Task { [service, paths] in
            var requestID: JSONValue = .null
            do {
              if let request = try await connection.read() {
                requestID = request["id"]
                guard request["jsonrpc"].string == "2.0",
                  request["workspaceID"].string == paths.workspaceID,
                  request["protocolVersion"].string == "1.0", let method = request["method"].string
                else {
                  throw ArchitectureError(
                    "PROTOCOL_MISMATCH", "Workspace or protocol identity mismatch.", exitCode: 7)
                }
                let peer = try await connection.peerIdentity()
                let result = try await service.handle(method, params: request["params"], peer: peer, credential: request["extensionCredential"].string)
                try await connection.write(
                  .object(["jsonrpc": .string("2.0"), "id": requestID, "result": result]))
                if method == "daemon.stop" { await service.acknowledgeStop() }
              }
            } catch {
              let error =
                (error as? ArchitectureError)
                ?? ArchitectureError("REQUEST_FAILED", String(describing: error))
              do {
                try await connection.write(
                  .object([
                    "jsonrpc": .string("2.0"), "id": requestID,
                    "error": .object([
                      "code": .number(-32000), "message": .string(error.message),
                      "data": .object([
                        "code": .string(error.code), "exitCode": .number(Double(error.exitCode)),
                      ]),
                    ]),
                  ]))
              } catch {
                FileHandle.standardError.write(Data("RPC response failed: \(error)\n".utf8))
              }
            }
            await connection.close()
            self.finished(id)
          }
        }
      } else {
        try await Task.sleep(for: .milliseconds(10))
      }
    }
  }

  private func shutdown(_ watch: Task<Void, Never>) async {
    watch.cancel()
    await watch.value
    await service.shutdown()
    let remaining = Array(tasks.values)
    for task in remaining { task.cancel() }
    for task in remaining { await task.value }
    tasks.removeAll()
  }
  private func finished(_ id: UUID) { tasks.removeValue(forKey: id); providerTasks.remove(id) }
}
