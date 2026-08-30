import Foundation

/// Produces a value-free structural inventory while decoded JSON is still
/// available. Returned summaries retain no payload strings, numbers, IDs, exact
/// cadence values, or absolute timestamps.
enum EightSleepPayloadShapeAnalyzer {
  static func summarize(
    _ root: JSONValue,
    redacting identifiers: Set<String> = []
  ) -> [EightSleepProbePathSummary] {
    let harvestedIdentifiers = SensitiveIdentifierCollector.collect(from: root)
    var walker = Walker(redactedIdentifiers: identifiers.union(harvestedIdentifiers))
    walker.inspect(root, path: "$")
    return walker.summaries
  }
}

private struct Walker {
  private static let maximumCadenceSamples = 4_096

  private var accumulators: [String: PathAccumulator] = [:]
  private var sanitizedKeys: [String: String] = [:]
  private let redactedIdentifiers: Set<String>
  private let timestampParser = TimestampParser()

  init(redactedIdentifiers: Set<String>) {
    self.redactedIdentifiers = Set(redactedIdentifiers.filter { !$0.isEmpty })
  }

  var summaries: [EightSleepProbePathSummary] {
    accumulators.keys.sorted().compactMap { path in
      accumulators[path]?.summary(path: path)
    }
  }

  mutating func inspect(_ value: JSONValue, path: String) {
    switch value {
    case .object(let object):
      record(kind: .object, at: path)
      recordCadence(cadenceObservations(inObjectKeys: object.keys), at: path)

      for key in object.keys.sorted() {
        guard let child = object[key] else { continue }
        let safeKey = sanitizedKey(key)
        inspect(child, path: childPath(parent: path, key: safeKey))
      }

    case .array(let array):
      recordArray(count: array.count, at: path)
      recordCadence(cadenceObservations(in: array), at: path)
      let itemPath = path + "[]"
      for child in array {
        inspect(child, path: itemPath)
      }

    case .string(let string):
      let kind: EightSleepProbeValueKind
      if timestampParser.parse(string) != nil {
        kind = .timestampString
      } else if string.count <= 64, Double(string)?.isFinite == true {
        kind = .numericString
      } else {
        kind = .text
      }
      record(kind: kind, at: path)

    case .number:
      record(kind: .number, at: path)

    case .bool:
      record(kind: .boolean, at: path)

    case .null:
      record(kind: .null, at: path)
    }
  }

  private func childPath(parent: String, key: String) -> String {
    parent == "$" ? key : parent + "." + key
  }

  private mutating func sanitizedKey(_ key: String) -> String {
    if let cached = sanitizedKeys[key] { return cached }
    let sanitized = sanitizedFieldKey(key, redacting: redactedIdentifiers)
    sanitizedKeys[key] = sanitized
    return sanitized
  }

  private func cadenceObservations(in values: [JSONValue]) -> CadenceObservations {
    var totalCount = 0
    var sampledDates: [Date] = []
    sampledDates.reserveCapacity(min(values.count, Self.maximumCadenceSamples))

    for value in values {
      guard let timestamp = timestampObservation(value) else { continue }
      totalCount += 1
      if sampledDates.count < Self.maximumCadenceSamples {
        sampledDates.append(timestamp)
      }
    }

    return CadenceObservations(
      totalCount: totalCount,
      sampledDates: sampledDates,
      wasCapped: totalCount > sampledDates.count
    )
  }

  private func cadenceObservations<S: Sequence>(inObjectKeys keys: S) -> CadenceObservations
  where S.Element == String {
    var totalCount = 0
    var sampledDates: [Date] = []
    sampledDates.reserveCapacity(Self.maximumCadenceSamples)

    for key in keys {
      guard let timestamp = timestampParser.parse(key) else { continue }
      totalCount += 1
      if sampledDates.count < Self.maximumCadenceSamples {
        sampledDates.append(timestamp)
      }
    }

    return CadenceObservations(
      totalCount: totalCount,
      sampledDates: sampledDates,
      wasCapped: totalCount > sampledDates.count
    )
  }

  private func timestampObservation(_ value: JSONValue) -> Date? {
    switch value {
    case .array(let values):
      guard let first = values.first else { return nil }
      return timestampParser.parse(first)

    case .object(let object):
      let keysByNormalizedName = Dictionary(
        object.keys.map { ($0.lowercased().filter(\.isLetter), $0) },
        uniquingKeysWith: { first, _ in first }
      )
      for normalizedName in [
        "timestamp", "sampletime", "recordedat", "time", "ts", "epoch",
        "datetime", "date", "starttime", "start", "createdat",
      ] {
        guard
          let key = keysByNormalizedName[normalizedName],
          let candidate = object[key],
          let timestamp = timestampParser.parse(candidate)
        else { continue }
        return timestamp
      }
      return nil

    case .string, .number:
      return timestampParser.parse(value)

    case .bool, .null:
      return nil
    }
  }

  private mutating func record(kind: EightSleepProbeValueKind, at path: String) {
    accumulators[path, default: PathAccumulator()].record(kind: kind)
  }

  private mutating func recordArray(count: Int, at path: String) {
    accumulators[path, default: PathAccumulator()].recordArray(count: count)
  }

  private mutating func recordCadence(_ observations: CadenceObservations, at path: String) {
    guard observations.totalCount > 0 else { return }
    accumulators[path, default: PathAccumulator()].recordCadence(observations)
  }
}

private struct CadenceObservations {
  let totalCount: Int
  let sampledDates: [Date]
  let wasCapped: Bool
}

private struct PathAccumulator {
  private var countsByKind: [EightSleepProbeValueKind: Int] = [:]
  private var arrayInstanceCount = 0
  private var totalArrayElementCount = 0
  private var minimumArrayElementCount: Int?
  private var maximumArrayElementCount: Int?
  private var timestampObservationCount = 0
  private var cadenceGapCount = 0
  private var cadenceBuckets: [EightSleepProbeCadenceBucket: Int] = [:]
  private var cadenceSampleWasCapped = false

  mutating func record(kind: EightSleepProbeValueKind) {
    countsByKind[kind, default: 0] += 1
  }

  mutating func recordArray(count: Int) {
    record(kind: .array)
    arrayInstanceCount += 1
    totalArrayElementCount += count
    minimumArrayElementCount = min(minimumArrayElementCount ?? count, count)
    maximumArrayElementCount = max(maximumArrayElementCount ?? count, count)
  }

  mutating func recordCadence(_ observations: CadenceObservations) {
    timestampObservationCount += observations.totalCount
    cadenceSampleWasCapped = cadenceSampleWasCapped || observations.wasCapped

    let uniqueDates = Array(Set(observations.sampledDates)).sorted()
    for (first, second) in zip(uniqueDates, uniqueDates.dropFirst()) {
      let gap = second.timeIntervalSince(first)
      guard gap > 0, gap.isFinite else { continue }
      cadenceGapCount += 1
      cadenceBuckets[cadenceBucket(for: gap), default: 0] += 1
    }
  }

  func summary(path: String) -> EightSleepProbePathSummary {
    EightSleepProbePathSummary(
      path: path,
      kindCounts: countsByKind.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { kind in
        countsByKind[kind].map { EightSleepProbeKindCount(kind: kind, count: $0) }
      },
      arrayInstanceCount: arrayInstanceCount,
      totalArrayElementCount: totalArrayElementCount,
      minimumArrayElementCount: minimumArrayElementCount,
      maximumArrayElementCount: maximumArrayElementCount,
      timestampObservationCount: timestampObservationCount,
      cadenceGapCount: cadenceGapCount,
      typicalCadenceBucket: typicalCadenceBucket,
      cadenceSampleWasCapped: cadenceSampleWasCapped
    )
  }

  private var typicalCadenceBucket: EightSleepProbeCadenceBucket? {
    guard cadenceGapCount > 0 else { return nil }
    let midpoint = (cadenceGapCount - 1) / 2
    var cumulative = 0
    for bucket in EightSleepProbeCadenceBucket.allCases {
      cumulative += cadenceBuckets[bucket, default: 0]
      if cumulative > midpoint { return bucket }
    }
    return nil
  }

  private func cadenceBucket(for seconds: TimeInterval) -> EightSleepProbeCadenceBucket {
    switch seconds {
    case ..<0.01: .underTenMilliseconds
    case ..<0.1: .tenToHundredMilliseconds
    case ..<1: .hundredMillisecondsToOneSecond
    case ..<10: .oneToTenSeconds
    case ..<60: .tenSecondsToOneMinute
    case ..<600: .oneToTenMinutes
    case ..<3_600: .tenMinutesToOneHour
    default: .overOneHour
    }
  }
}

private enum SensitiveIdentifierCollector {
  private static let sensitiveFieldNames: Set<String> = [
    "id", "ids", "userid", "sessionid", "deviceid", "accountid", "profileid",
    "memberid", "podid", "sideid", "uuid", "guid", "serialnumber", "macaddress",
    "token", "accesstoken", "refreshtoken", "email", "username", "password",
  ]

  static func collect(from value: JSONValue) -> Set<String> {
    var identifiers: Set<String> = []
    inspect(value, identifiers: &identifiers)
    return identifiers
  }

  private static func inspect(_ value: JSONValue, identifiers: inout Set<String>) {
    switch value {
    case .object(let object):
      for (key, child) in object {
        let normalized = key.lowercased().filter(\.isLetter)
        if sensitiveFieldNames.contains(normalized) {
          collectPrimitiveValues(from: child, identifiers: &identifiers)
        }
        inspect(child, identifiers: &identifiers)
      }

    case .array(let array):
      for child in array {
        switch child {
        case .object, .array:
          inspect(child, identifiers: &identifiers)
        case .string, .number, .bool, .null:
          break
        }
      }

    case .string, .number, .bool, .null:
      break
    }
  }

  private static func collectPrimitiveValues(
    from value: JSONValue,
    identifiers: inout Set<String>
  ) {
    switch value {
    case .string(let string):
      if !string.isEmpty { identifiers.insert(string) }
    case .number(let number):
      if number.isFinite { identifiers.insert(String(number)) }
    case .array(let array):
      for child in array {
        collectPrimitiveValues(from: child, identifiers: &identifiers)
      }
    case .object(let object):
      for child in object.values {
        collectPrimitiveValues(from: child, identifiers: &identifiers)
      }
    case .bool, .null:
      break
    }
  }
}

private struct TimestampParser {
  private let fractionalFormatter: ISO8601DateFormatter
  private let standardFormatter: ISO8601DateFormatter

  init() {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    self.fractionalFormatter = fractionalFormatter

    let standardFormatter = ISO8601DateFormatter()
    standardFormatter.formatOptions = [.withInternetDateTime]
    self.standardFormatter = standardFormatter
  }

  func parse(_ value: JSONValue) -> Date? {
    switch value {
    case .string(let string): parse(string)
    case .number(let number): parseEpoch(number)
    case .object, .array, .bool, .null: nil
    }
  }

  func parse(_ string: String) -> Date? {
    if string.count <= 48,
      string.contains("T") || string.contains("t")
    {
      if let date = fractionalFormatter.date(from: string)
        ?? standardFormatter.date(from: string)
      {
        return date
      }
    }
    guard string.count <= 24, let number = Double(string) else { return nil }
    return parseEpoch(number)
  }

  private func parseEpoch(_ value: Double) -> Date? {
    guard value.isFinite else { return nil }
    let seconds: Double
    switch abs(value) {
    case 946_684_800 ... 4_102_444_800:
      seconds = value
    case 946_684_800_000 ... 4_102_444_800_000:
      seconds = value / 1_000
    case 946_684_800_000_000 ... 4_102_444_800_000_000:
      seconds = value / 1_000_000
    case 946_684_800_000_000_000 ... 4_102_444_800_000_000_000:
      seconds = value / 1_000_000_000
    default:
      return nil
    }
    return Date(timeIntervalSince1970: seconds)
  }
}
