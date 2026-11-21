import Darwin
import Foundation
import Security

/// Immutable kernel-identified peer; request payloads never construct this identity.
public struct ConnectionPeer: Codable, Sendable, Equatable {
  public let processID: Int32
  public let auditIdentity: String
  public let executable: String
  public let codeIdentity: String
  public let binaryDigest: String

  public static func current() throws -> ConnectionPeer {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { throw denied() }
    return try identify(code: code, pid: getpid(), audit: "self")
  }
  static func read(_ descriptor: Int32) throws -> ConnectionPeer {
    var pid: Int32 = 0
    var pidSize = socklen_t(MemoryLayout<Int32>.size)
    var token = [UInt32](repeating: 0, count: 8)
    var tokenSize = socklen_t(32)
    let status = token.withUnsafeMutableBytes { bytes in
      getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, bytes.baseAddress, &tokenSize)
    }
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidSize) == 0, status == 0, tokenSize == 32 else { throw denied() }
    let data = token.withUnsafeBytes { Data($0) }
    var code: SecCode?
    let attributes = [kSecGuestAttributeAudit: data] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { throw denied() }
    return try identify(code: code, pid: pid, audit: data.base64EncodedString())
  }
  private static func identify(code: SecCode, pid: Int32, audit: String) throws -> ConnectionPeer {
    guard SecCodeCheckValidity(code, [], nil) == errSecSuccess else { throw denied() }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { throw denied() }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let values = information as? [String: Any], let path = values[kSecCodeInfoMainExecutable as String] as? URL,
      let identity = values[kSecCodeInfoUnique as String] as? Data else { throw denied() }
    let bytes = try Data(contentsOf: path, options: .mappedIfSafe)
    guard bytes.count <= 128 * 1024 * 1024 else { throw ArchitectureError("RESOURCE_LIMIT", "Peer executable exceeds identity budget.", exitCode: 6) }
    return ConnectionPeer(processID: pid, auditIdentity: audit, executable: path.path, codeIdentity: identity.base64EncodedString(), binaryDigest: CanonicalJSON.digest(bytes))
  }
  private static func denied() -> ArchitectureError { ArchitectureError("AUTHENTICATION_REQUIRED", "Kernel peer code identity could not be established.", exitCode: 5) }
}
