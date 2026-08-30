import Foundation

struct EightSleepDecodedTrends {
  let nights: [EightSleepNight]
  let selectedHRVAlgorithmVersionsBySessionID: [String: String]
}

public enum EightSleepPayloadDecoder {
  private static let maximumSleepDurationSeconds: Double = 48 * 60 * 60

  public static func decodeTrends(
    _ data: Data,
    redacting identifiers: Set<String> = [],
    includePayloadShapeDiagnostics: Bool = false
  ) throws -> [EightSleepNight] {
    try decodeTrendsWithDiagnosticContext(
      data,
      redacting: identifiers,
      includePayloadShapeDiagnostics: includePayloadShapeDiagnostics
    ).nights
  }

  static func decodeTrendsWithDiagnosticContext(
    _ data: Data,
    redacting identifiers: Set<String> = [],
    includePayloadShapeDiagnostics: Bool = false
  ) throws -> EightSleepDecodedTrends {
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    guard
      let object = root.objectValue,
      let days = object["days"]?.arrayValue
    else {
      throw EightSleepAPIError.invalidPayload
    }

    var nights: [EightSleepNight] = []
    var versionsBySessionID: [String: String] = [:]
    for (index, value) in days.enumerated() {
      guard let day = value.objectValue else { continue }
      let night = decodeNight(
        day,
        fallbackIndex: index,
        redacting: identifiers,
        includePayloadShapeDiagnostics: includePayloadShapeDiagnostics
      )
      nights.append(night)
      if includePayloadShapeDiagnostics,
        let sessionID = night.latestSessionID,
        let selectedSession = day["sessions"]?.arrayValue?.compactMap(\.objectValue).first(
          where: { session in
            session.firstString(at: [["id"], ["sessionId"]]) == sessionID
          }
        ),
        let version = selectedSession["hrvAlgorithmVersion"]?.stringValue,
        !version.isEmpty
      {
        versionsBySessionID[sessionID] = version
      }
    }
    return EightSleepDecodedTrends(
      nights: nights,
      selectedHRVAlgorithmVersionsBySessionID: versionsBySessionID
    )
  }

  private static func decodeNight(
    _ object: [String: JSONValue],
    fallbackIndex: Int,
    redacting identifiers: Set<String>,
    includePayloadShapeDiagnostics: Bool
  ) -> EightSleepNight {
    let day = object.firstString(at: [["day"]]) ?? "Unknown night"
    let sessions = object["sessions"]?.arrayValue ?? []
    let sessionObjects = sessions.compactMap(\.objectValue)
    let fallbackSessionID = sessionObjects.reversed().lazy.compactMap {
      $0.firstString(at: [["id"], ["sessionId"]])
    }.first
    let sessionID = object.firstString(at: [["mainSessionId"]]) ?? fallbackSessionID
    let identifier =
      object.firstString(at: [["id"], ["sessionId"]])
      ?? sessionID
      ?? "\(day)-\(fallbackIndex)"
    let shapeRedactions = identifiers.union([identifier, sessionID, day].compactMap { $0 })
    let metricFields = decodeMetricFields(object)
    let explicitRestingHeartRate =
      object.firstNumber(at: [
        ["sleepQualityScore", "heartRate", "current"],
        ["restingHeartRate"],
        ["restingHeartRateBpm"],
        ["sleepQualityScore", "restingHeartRate", "current"],
        ["sleepQualityScore", "restingHeartRate", "average"],
      ])
      ?? metricFields.first(where: isRestingHeartRateField)?.value

    return EightSleepNight(
      id: identifier,
      day: day,
      presenceStart: parseDate(object.firstString(at: [["presenceStart"]])),
      presenceEnd: parseDate(object.firstString(at: [["presenceEnd"]])),
      isProcessing: object["processing"]?.boolValue ?? false,
      score: object.firstNumber(at: [["score"]]),
      sleepDurationSeconds: durationSeconds(
        object.firstNumber(at: [
          ["sleepDurationSeconds"],
          ["sleepDuration"],
        ])
      ),
      averageHeartRateBPM: object.firstNumber(at: [
        ["sleepQualityScore", "heartRate", "average"],
        ["heartRate"],
      ]),
      explicitRestingHeartRateBPM: explicitRestingHeartRate,
      reportedHRVMilliseconds: object.firstNumber(at: [
        ["sleepQualityScore", "hrv", "current"],
        ["sleepQualityScore", "hrv", "average"],
      ]),
      averageRespiratoryRate: object.firstNumber(at: [
        ["sleepQualityScore", "respiratoryRate", "current"],
        ["sleepQualityScore", "respiratoryRate", "average"],
        ["respiratoryRate"],
      ]),
      tossAndTurns: object.firstNumber(at: [["tnt"]]),
      lightSleepSeconds: durationSeconds(object.firstNumber(at: [["lightDuration"]])),
      deepSleepSeconds: durationSeconds(object.firstNumber(at: [["deepDuration"]])),
      remSleepSeconds: durationSeconds(object.firstNumber(at: [["remDuration"]])),
      availableFields: object.keys.sorted(),
      metricFields: metricFields,
      timeSeries: decodeTimeSeries(sessionObjects),
      latestSessionID: sessionID,
      intervalProbe: nil,
      trendsPathSummaries: includePayloadShapeDiagnostics
        ? EightSleepPayloadShapeAnalyzer.summarize(
          .object(object),
          redacting: shapeRedactions
        )
        : []
    )
  }

  private static func durationSeconds(_ value: Double?) -> Double? {
    guard
      let value,
      value.isFinite,
      value >= 0,
      value <= maximumSleepDurationSeconds
    else { return nil }
    return value
  }

  private static func isRestingHeartRateField(_ field: EightSleepMetricField) -> Bool {
    let normalized = field.path.lowercased().filter(\.isLetter)
    return normalized.contains("restingheartrate") || normalized.hasSuffix("rhr")
  }

  private static func decodeMetricFields(
    _ object: [String: JSONValue]
  ) -> [EightSleepMetricField] {
    var valuesByPath: [String: Double] = [:]
    collectMetricFields(in: .object(object), path: [], valuesByPath: &valuesByPath)

    return valuesByPath.keys.sorted().compactMap { path in
      valuesByPath[path].map { EightSleepMetricField(path: path, value: $0) }
    }
  }

  private static func collectMetricFields(
    in value: JSONValue,
    path: [String],
    valuesByPath: inout [String: Double]
  ) {
    switch value {
    case .object(let object):
      for key in object.keys.sorted() {
        guard key.caseInsensitiveCompare("timeseries") != .orderedSame else { continue }
        guard let child = object[key] else { continue }
        collectMetricFields(
          in: child,
          path: path + [sanitizedFieldKey(key)],
          valuesByPath: &valuesByPath
        )
      }
    case .array(let array):
      let arrayPath: [String]
      if let last = path.last {
        arrayPath = Array(path.dropLast()) + [last + "[]"]
      } else {
        arrayPath = ["[]"]
      }
      for child in array {
        collectMetricFields(in: child, path: arrayPath, valuesByPath: &valuesByPath)
      }
    case .number(let number):
      let joinedPath = path.joined(separator: ".")
      let normalizedPath = joinedPath.lowercased()
      let metricTokens = ["heart", "hrv", "respir", "breath", "pulse", "rhr", "resting"]
      if metricTokens.contains(where: normalizedPath.contains),
        !isIdentifierPath(path),
        number.isFinite
      {
        valuesByPath[joinedPath] = number
      }
    case .string(let string):
      guard let number = Double(string), number.isFinite else { return }
      let joinedPath = path.joined(separator: ".")
      let normalizedPath = joinedPath.lowercased()
      let metricTokens = ["heart", "hrv", "respir", "breath", "pulse", "rhr", "resting"]
      if metricTokens.contains(where: normalizedPath.contains), !isIdentifierPath(path) {
        valuesByPath[joinedPath] = number
      }
    case .bool, .null:
      break
    }
  }

  private static func isIdentifierPath(_ path: [String]) -> Bool {
    guard let leaf = path.last else { return false }
    let normalized = leaf.lowercased().filter(\.isLetter)
    return normalized.hasSuffix("id")
      || normalized.hasSuffix("identifier")
      || normalized.hasSuffix("uuid")
  }

  private static func decodeTimeSeries(
    _ sessions: [[String: JSONValue]]
  ) -> [EightSleepTimeSeries] {
    sessions.enumerated().flatMap { sessionIndex, session in
      let sessionID =
        session.firstString(at: [["id"], ["sessionId"]])
        ?? "session-\(sessionIndex + 1)"
      let series = session["timeseries"]?.objectValue ?? [:]

      return series.keys.sorted().compactMap { name -> EightSleepTimeSeries? in
        guard let samples = series[name]?.arrayValue else { return nil }
        let timestamps = samples.compactMap(sampleTimestamp)
        let latestValue = samples.reversed().lazy.compactMap(sampleNumber).first
        let numericSamples = samples.compactMap { sample -> EightSleepTimeSeriesSample? in
          guard
            let timestamp = sampleTimestamp(sample),
            let value = sampleNumber(sample),
            value.isFinite
          else { return nil }
          return EightSleepTimeSeriesSample(timestamp: timestamp, value: value)
        }

        return EightSleepTimeSeries(
          id: "\(sessionID)-\(name)",
          sessionID: sessionID,
          name: name,
          sampleCount: samples.count,
          firstTimestamp: timestamps.first,
          lastTimestamp: timestamps.last,
          latestNumericValue: latestValue,
          numericSamples: numericSamples
        )
      }
    }
  }

  private static func sampleTimestamp(_ sample: JSONValue) -> Date? {
    guard
      let values = sample.arrayValue,
      let rawTimestamp = values.first?.stringValue
    else { return nil }
    return parseDate(rawTimestamp)
  }

  private static func sampleNumber(_ sample: JSONValue) -> Double? {
    guard let values = sample.arrayValue, values.count > 1 else { return nil }
    return values[1].numberValue
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
      return date
    }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
  }
}
