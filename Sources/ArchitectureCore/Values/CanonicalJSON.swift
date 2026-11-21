import CryptoKit
import Foundation

public enum CanonicalJSON {
  public static func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
  }
  private static let hexDigits = Array("0123456789abcdef".utf8)
  public static func digest(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    var bytes = [UInt8](repeating: 0, count: 64)
    for (index, value) in digest.enumerated() {
      bytes[index * 2] = hexDigits[Int(value >> 4)]
      bytes[index * 2 + 1] = hexDigits[Int(value & 15)]
    }
    return String(decoding: bytes, as: UTF8.self)
  }
  public static func digest(_ value: String) -> String { digest(Data(value.utf8)) }
  /// Identity keys encode ownership and signature, never source contents or line numbers.
  public static func identity(_ key: String) -> String { "ae-" + digest(key) }
}
