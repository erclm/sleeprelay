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

func sanitizedFieldKey(
  _ key: String,
  redacting identifiers: Set<String> = []
) -> String {
  let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
  let isLongHexIdentifier = trimmed.count >= 16 && trimmed.allSatisfy(\.isHexDigit)
  let isUUID = UUID(uuidString: trimmed) != nil
  let isKnownIdentifier = identifiers.contains(trimmed)
  let isDateOrTimestamp =
    trimmed.range(
      of: #"^\d{4}-\d{2}-\d{2}(?:[Tt ][^\s]*)?$"#,
      options: .regularExpression
    ) != nil
    || trimmed.range(
      of: #"^(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})$"#,
      options: .regularExpression
    ) != nil
  let isTimeOnly =
    trimmed.range(
      of: #"^\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?$"#,
      options: .regularExpression
    ) != nil
  let isNumericKey =
    !trimmed.isEmpty
    && trimmed.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }
    && Double(trimmed) != nil
  let isHighEntropyIdentifier =
    trimmed.count >= 20
    && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    && trimmed.filter(\.isNumber).count >= 4
  let isLongOpaqueKey =
    trimmed.count >= 32
    && !trimmed.contains(where: \.isWhitespace)
  let isShortMixedOpaqueKey =
    trimmed.count >= 8
    && (trimmed.contains("_") || trimmed.contains("-"))
    && trimmed.filter(\.isNumber).count >= 2
    && trimmed.contains(where: \.isLetter)
  let isMeasurementValueKey =
    trimmed.range(
      of: #"^(?:bpm|hr|hrv|rmssd|sdnn|rr|ibi|spo2|temp|temperature|respiratory)[^\d]*\d+(?:\.\d+)?$"#,
      options: [.regularExpression, .caseInsensitive]
    ) != nil
  let identifierPrefixes = ["user-", "session-", "device-", "account-"]
  let schemaSuffixWords: Set<String> = [
    "configuration", "config", "count", "data", "date", "details", "duration", "end",
    "firmware", "hardware", "metrics", "model", "name", "profile", "settings", "source",
    "start", "status", "summary", "temperature", "time", "timezone", "type", "version",
  ]
  let lowercased = trimmed.lowercased()
  let isIdentifierPrefixedKey = identifierPrefixes.contains { prefix in
    guard lowercased.hasPrefix(prefix) else { return false }
    let suffix = String(lowercased.dropFirst(prefix.count))
    let words = suffix.split(separator: "-").map(String.init)
    let isSchemaSuffix = !words.isEmpty && words.allSatisfy { word in
      schemaSuffixWords.contains(word)
        || word.range(of: #"^v\d+$"#, options: .regularExpression) != nil
    }
    return !isSchemaSuffix
  }

  if trimmed.isEmpty {
    return "{empty-field}"
  }

  if isDateOrTimestamp || isTimeOnly {
    return "{timestamp}"
  }

  if isNumericKey {
    return "{index}"
  }

  if isMeasurementValueKey {
    return "{value-key}"
  }

  if trimmed.contains("@")
    || isLongHexIdentifier
    || isUUID
    || isKnownIdentifier
    || isHighEntropyIdentifier
    || isLongOpaqueKey
    || isShortMixedOpaqueKey
    || isIdentifierPrefixedKey
  {
    return "{identifier}"
  }

  let scalars = trimmed.unicodeScalars.map { scalar -> String in
    if CharacterSet.controlCharacters.contains(scalar)
      || CharacterSet.newlines.contains(scalar)
      || CharacterSet.illegalCharacters.contains(scalar)
      || scalar.properties.generalCategory == .format
    {
      return "?"
    }
    switch scalar {
    case ".": return #"\."#
    case "[": return #"\["#
    case "]": return #"\]"#
    case "\\": return #"\\"#
    case "$": return #"\$"#
    case "|": return #"\|"#
    case "{": return #"\{"#
    case "}": return #"\}"#
    default: return String(scalar)
    }
  }
  return scalars.joined()
}
