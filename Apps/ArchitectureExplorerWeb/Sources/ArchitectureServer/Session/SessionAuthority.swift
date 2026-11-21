import ArchitectureCore
import Foundation
import SwiftWebCore

public actor SessionAuthority {
  public let origin: String
  public let cookieName: String
  public let launchToken: String
  private let expires = ContinuousClock.now.advanced(by: .seconds(90))
  private var used = false
  private struct Session: Sendable { let deadline: ContinuousClock.Instant; let csrf: String }
  private var sessions: [String: Session] = [:]
  public init(port: Int) {
    origin = "http://127.0.0.1:\(port)"
    cookieName = "architecture-session-\(port)"
    launchToken = UUID().uuidString + UUID().uuidString
  }
  public func validHost(_ request: Request) -> Bool {
    request.url.host == String(origin.dropFirst("http://".count))
      && (request.headers[.origin] == nil || request.headers[.origin] == origin)
  }
  public func authorize(_ request: Request, webSocket: Bool = false) -> Bool {
    guard validHost(request), !webSocket || request.headers[.origin] == origin,
      let cookie = request.cookies[cookieName], let deadline = sessions[cookie],
      ContinuousClock.now < deadline.deadline
    else { return false }
    return true
  }
  public func context(_ request: Request) -> JSONValue? {
    guard authorize(request), let cookie = request.cookies[cookieName], let session = sessions[cookie] else { return nil }
    return .object(["csrf": .string(session.csrf)])
  }
  public func authorizeMutation(_ request: Request) -> Bool {
    guard request.headers[.origin] == origin, let context = context(request), let csrf = context["csrf"].string else { return false }
    return request.headers[.authorization] == "Bearer " + csrf
  }
  public func exchange(_ token: String, request: Request) throws -> String {
    guard validHost(request), request.headers[.origin] == origin, !used,
      ContinuousClock.now < expires, token == launchToken
    else {
      throw ArchitectureError(
        "POLICY_DENIED", "Invalid, expired or previously used launch token.", exitCode: 5)
    }
    used = true
    let session = UUID().uuidString + UUID().uuidString
    sessions[session] = Session(deadline: ContinuousClock.now.advanced(by: .seconds(43200)), csrf: UUID().uuidString + UUID().uuidString)
    return session
  }
}
