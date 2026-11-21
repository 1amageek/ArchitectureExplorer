import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  public init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
      return
    }
    if let v = try Self.attempt(String.self, c) {
      self = .string(v)
      return
    }
    if let v = try Self.attempt(Bool.self, c) {
      self = .bool(v)
      return
    }
    if let v = try Self.attempt(Double.self, c) {
      self = .number(v)
      return
    }
    if let v = try Self.attempt([JSONValue].self, c) {
      self = .array(v)
      return
    }
    self = .object(try c.decode([String: JSONValue].self))
  }
  private static func attempt<T: Decodable>(
    _ type: T.Type, _ container: any SingleValueDecodingContainer
  ) throws -> T? {
    do { return try container.decode(type) } catch DecodingError.typeMismatch { return nil }
  }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .object(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
  public subscript(_ key: String) -> JSONValue {
    if case .object(let v) = self { return v[key] ?? .null }
    return .null
  }
  public var string: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  public var int: Int? {
    if case .number(let v) = self, v.isFinite, v.rounded(.towardZero) == v, v >= Double(Int.min),
      v < Double(Int.max)
    {
      return Int(v)
    }
    return nil
  }
  public var bool: Bool? {
    if case .bool(let v) = self { return v }
    return nil
  }
  public var array: [JSONValue] {
    if case .array(let v) = self { return v }
    return []
  }
  public var object: [String: JSONValue] {
    if case .object(let v) = self { return v }
    return [:]
  }
  public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try CanonicalJSON.encode(value)
    return try JSONDecoder().decode(Self.self, from: data)
  }
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let data = try CanonicalJSON.encode(self)
    return try JSONDecoder().decode(type, from: data)
  }
}
