import ArchitectureClient
import ArchitectureCore
import ArchitectureHTTPHost
import ArchitectureWeb
import Darwin
import Foundation
import SwiftWebCore

public enum ExplorerServer {
  public static func run(workspace: String, port requested: Int = 0, noOpen: Bool = false, repositoryMap: URL? = nil, threadID: UUID? = nil)
    async throws
  {
    guard (0...65535).contains(requested) else {
      throw ArchitectureError("INVALID_ARGUMENT", "Invalid loopback port.", exitCode: 2)
    }
    let port = try requested == 0 ? availablePort() : requested
    let authority = SessionAuthority(port: port)
    let client = try ArchitectureClient(workspace: workspace)
    let collection = try repositoryMap.map { try RepositoryMap(root: client.paths.root, manifest: $0) }
    if collection == nil { _ = try await liveEvent(client, after: .object([:])) }
    let streams = SubscriptionStreams()
    var hooks = SwiftWebDevelopmentHooks.disabled
    hooks.registerRoutes = { routes in
      routes.webSocket(
        [.constant("events")],
        shouldUpgrade: { request in
          guard collection == nil, await authority.authorize(request, webSocket: true) else { return nil }
          return [:]
        },
        onUpgrade: { request, channel in
          let subscription = await streams.start {
            var previous: JSONValue = .object([:])
            while !Task.isCancelled {
              do {
                let event = try await liveEvent(client, after: previous)
                if event["type"].string != "unchanged" || event["extensionChanged"].bool == true {
                  let data = try CanonicalJSON.encode(event)
                  try await channel.send(String(decoding: data, as: UTF8.self))
                }
                previous = event
                try await Task.sleep(for: .milliseconds(250))
              } catch is CancellationError { return } catch {
                if let error = error as? ArchitectureError, error.code == "WEB_HOST_PAIRING_MISMATCH" {
                  do {
                    let event = JSONValue.object([
                      "type": .string("liveUnavailable"), "code": .string(error.code),
                      "message": .string(error.message),
                    ])
                    let data = try CanonicalJSON.encode(event)
                    try await channel.send(String(decoding: data, as: UTF8.self))
                  } catch {
                    FileHandle.standardError.write(Data("WebSocket diagnostic delivery failed: \(error)\n".utf8))
                  }
                }
                do { try await channel.close() } catch {
                  FileHandle.standardError.write(Data("WebSocket close failed: \(error)\n".utf8))
                }
                return
              }
            }
          }
          await channel.onClose {
            await streams.cancel(subscription)
          }
        })
    }
    await SwiftWebDevelopmentSupport.shared.install(hooks)
    let app = ExplorerApp(authority: authority, client: client, collection: collection, threadID: threadID)
    let installation: HTTPServerAppInstallation
    do {
      installation = try await HTTPServerHost(hostname: "127.0.0.1", port: port).render(app)
    } catch {
      await streams.shutdown()
      await SwiftWebDevelopmentSupport.shared.reset()
      throw error
    }
    let url = authority.origin + "/#token=" + authority.launchToken
    let task = Task { try await installation.serve() }
    // Confirm the actual listening host before reporting a usable URL.
    do {
      let root = URL(string: authority.origin + "/")!
      let deadline = ContinuousClock.now.advanced(by: .seconds(10))
      var ready = false
      while ContinuousClock.now < deadline {
        do {
          let (_, response) = try await URLSession.shared.data(from: root)
          if (response as? HTTPURLResponse)?.statusCode == 200 {
            ready = true
            break
          }
        } catch { try await Task.sleep(for: .milliseconds(50)) }
      }
      guard ready else {
        throw ArchitectureError(
          "WEB_HOST_UNAVAILABLE", "Web listener did not become ready.", exitCode: 6)
      }
      let output = try CanonicalJSON.encode(
        JSONValue.object(["url": .string(url), "workspaceID": .string(client.paths.workspaceID)]))
      FileHandle.standardOutput.write(output + Data([10]))
      if !noOpen {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [url]
        try open.run()
      }
      ProcessSignals.install()
      while !ProcessSignals.interrupted { try await Task.sleep(for: .milliseconds(100)) }
      task.cancel()
      try await installation.shutdown()
      do { try await task.value } catch is CancellationError {}
      await streams.shutdown()
      await SwiftWebDevelopmentSupport.shared.reset()
    } catch {
      task.cancel()
      do { try await installation.shutdown() } catch let cleanup {
        FileHandle.standardError.write(Data("Web shutdown failed: \(cleanup)\n".utf8))
      }
      await streams.shutdown()
      await SwiftWebDevelopmentSupport.shared.reset()
      throw error
    }
  }
  private static func liveEvent(_ client: ArchitectureClient, after previous: JSONValue) async throws -> JSONValue {
    do {
      return try await client.call("events.poll", parameters: previous)
    } catch let error as ArchitectureError where ["SESSION_EXPIRED", "AUTHENTICATION_REQUIRED", "POLICY_DENIED"].contains(error.code) {
      throw ArchitectureError(
        "WEB_HOST_PAIRING_MISMATCH",
        "Explorer cannot connect because the Web host and workspace daemon are from different builds. Restart Explorer and the daemon using the same paired build.",
        exitCode: 5)
    }
  }
  private static func availablePort() throws -> Int {
    let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw ArchitectureError("CONNECTION_FAILED", "Cannot allocate loopback socket.", exitCode: 6)
    }
    defer { Darwin.close(descriptor) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let status = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard status == 0 else {
      throw ArchitectureError(
        "CONNECTION_FAILED", "Cannot bind temporary loopback socket.", exitCode: 6)
    }
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let result = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &size) }
    }
    guard result == 0 else {
      throw ArchitectureError("CONNECTION_FAILED", "Cannot determine loopback port.", exitCode: 6)
    }
    return Int(UInt16(bigEndian: address.sin_port))
  }
}
