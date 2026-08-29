import Foundation

enum JSONValue: Decodable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value"
      )
    }
  }
}

extension JSONValue {
  var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var numberValue: Double? {
    switch self {
    case .number(let value): value
    case .string(let value): Double(value)
    default: nil
    }
  }

  var boolValue: Bool? {
    guard case .bool(let value) = self else { return nil }
    return value
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  func value(at path: [String]) -> JSONValue? {
    guard let first = path.first, let value = self[first] else { return nil }
    guard path.count > 1 else { return value }
    guard let nested = value.objectValue else { return nil }
    return nested.value(at: Array(path.dropFirst()))
  }

  func firstNumber(at paths: [[String]]) -> Double? {
    paths.lazy.compactMap { value(at: $0)?.numberValue }.first
  }

  func firstString(at paths: [[String]]) -> String? {
    paths.lazy.compactMap { value(at: $0)?.stringValue }.first
  }
}
