import Foundation

public enum EightSleepPayloadDecoder {
  public static func decodeTrends(_ data: Data) throws -> [EightSleepNight] {
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    guard
      let object = root.objectValue,
      let days = object["days"]?.arrayValue
    else {
      throw EightSleepAPIError.invalidPayload
    }

    return days.enumerated().compactMap { index, value in
      guard let day = value.objectValue else { return nil }
      return decodeNight(day, fallbackIndex: index)
    }
  }

  private static func decodeNight(
    _ object: [String: JSONValue],
    fallbackIndex: Int
  ) -> EightSleepNight {
    let day = object.firstString(at: [["day"]]) ?? "Unknown night"
    let sessions = object["sessions"]?.arrayValue ?? []
    let sessionObjects = sessions.compactMap(\.objectValue)
    let sessionID = sessionObjects.reversed().lazy.compactMap {
      $0.firstString(at: [["id"], ["sessionId"]])
    }.first
    let identifier =
      object.firstString(at: [["id"], ["sessionId"]])
      ?? sessionID
      ?? "\(day)-\(fallbackIndex)"

    return EightSleepNight(
      id: identifier,
      day: day,
      presenceStart: parseDate(object.firstString(at: [["presenceStart"]])),
      presenceEnd: parseDate(object.firstString(at: [["presenceEnd"]])),
      isProcessing: object["processing"]?.boolValue ?? false,
      score: object.firstNumber(at: [["score"]]),
      sleepDurationSeconds: object.firstNumber(at: [
        ["sleepDurationSeconds"],
        ["sleepDuration"],
      ]),
      averageHeartRateBPM: object.firstNumber(at: [
        ["sleepQualityScore", "heartRate", "average"],
        ["heartRate"],
      ]),
      explicitRestingHeartRateBPM: object.firstNumber(at: [
        ["restingHeartRate"],
        ["restingHeartRateBpm"],
        ["sleepQualityScore", "restingHeartRate", "average"],
      ]),
      reportedHRVMilliseconds: object.firstNumber(at: [
        ["sleepQualityScore", "hrv", "current"],
        ["sleepQualityScore", "hrv", "average"],
      ]),
      averageRespiratoryRate: object.firstNumber(at: [
        ["sleepQualityScore", "respiratoryRate", "average"],
        ["respiratoryRate"],
      ]),
      tossAndTurns: object.firstNumber(at: [["tnt"]]),
      lightSleepSeconds: object.firstNumber(at: [["lightDuration"]]),
      deepSleepSeconds: object.firstNumber(at: [["deepDuration"]]),
      remSleepSeconds: object.firstNumber(at: [["remDuration"]]),
      availableFields: object.keys.sorted(),
      timeSeries: decodeTimeSeries(sessionObjects)
    )
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

        return EightSleepTimeSeries(
          id: "\(sessionID)-\(name)",
          sessionID: sessionID,
          name: name,
          sampleCount: samples.count,
          firstTimestamp: timestamps.first,
          lastTimestamp: timestamps.last,
          latestNumericValue: latestValue
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
