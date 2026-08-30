import Foundation

public struct EightSleepCredentials: Codable, Equatable, Sendable {
  public let email: String
  public let password: String

  public init(email: String, password: String) {
    self.email = email
    self.password = password
  }
}

public struct EightSleepFetchRequest: Equatable, Sendable {
  public let from: String
  public let to: String
  public let timeZoneIdentifier: String
  public let includeIntervalProbes: Bool

  public init(
    from: String,
    to: String,
    timeZoneIdentifier: String,
    includeIntervalProbes: Bool = true
  ) {
    self.from = from
    self.to = to
    self.timeZoneIdentifier = timeZoneIdentifier
    self.includeIntervalProbes = includeIntervalProbes
  }
}

public struct EightSleepSnapshot: Equatable, Sendable {
  public let fetchedAt: Date
  public let nights: [EightSleepNight]

  public init(fetchedAt: Date, nights: [EightSleepNight]) {
    self.fetchedAt = fetchedAt
    self.nights = nights
  }
}

public struct EightSleepNight: Identifiable, Hashable, Sendable {
  public let id: String
  public let day: String
  public let presenceStart: Date?
  public let presenceEnd: Date?
  public let isProcessing: Bool
  public let score: Double?
  public let sleepDurationSeconds: Double?
  public let averageHeartRateBPM: Double?
  public let explicitRestingHeartRateBPM: Double?
  public let reportedHRVMilliseconds: Double?
  public let averageRespiratoryRate: Double?
  public let tossAndTurns: Double?
  public let lightSleepSeconds: Double?
  public let deepSleepSeconds: Double?
  public let remSleepSeconds: Double?
  public let availableFields: [String]
  public let metricFields: [EightSleepMetricField]
  public let timeSeries: [EightSleepTimeSeries]
  public let latestSessionID: String?
  public internal(set) var intervalProbe: EightSleepIntervalProbe?

  public var discoveredRestingHeartRateBPM: Double? {
    explicitRestingHeartRateBPM
      ?? intervalProbe?.metricFields.first(where: { field in
        let normalized = field.path.lowercased().filter(\.isLetter)
        return normalized.contains("restingheartrate") || normalized.hasSuffix("rhr")
      })?.value
  }

  public init(
    id: String,
    day: String,
    presenceStart: Date?,
    presenceEnd: Date?,
    isProcessing: Bool,
    score: Double?,
    sleepDurationSeconds: Double?,
    averageHeartRateBPM: Double?,
    explicitRestingHeartRateBPM: Double?,
    reportedHRVMilliseconds: Double?,
    averageRespiratoryRate: Double?,
    tossAndTurns: Double?,
    lightSleepSeconds: Double?,
    deepSleepSeconds: Double?,
    remSleepSeconds: Double?,
    availableFields: [String],
    metricFields: [EightSleepMetricField],
    timeSeries: [EightSleepTimeSeries],
    latestSessionID: String?,
    intervalProbe: EightSleepIntervalProbe?
  ) {
    self.id = id
    self.day = day
    self.presenceStart = presenceStart
    self.presenceEnd = presenceEnd
    self.isProcessing = isProcessing
    self.score = score
    self.sleepDurationSeconds = sleepDurationSeconds
    self.averageHeartRateBPM = averageHeartRateBPM
    self.explicitRestingHeartRateBPM = explicitRestingHeartRateBPM
    self.reportedHRVMilliseconds = reportedHRVMilliseconds
    self.averageRespiratoryRate = averageRespiratoryRate
    self.tossAndTurns = tossAndTurns
    self.lightSleepSeconds = lightSleepSeconds
    self.deepSleepSeconds = deepSleepSeconds
    self.remSleepSeconds = remSleepSeconds
    self.availableFields = availableFields
    self.metricFields = metricFields
    self.timeSeries = timeSeries
    self.latestSessionID = latestSessionID
    self.intervalProbe = intervalProbe
  }
}

public struct EightSleepMetricField: Identifiable, Hashable, Sendable {
  public var id: String { path }

  public let path: String
  public let value: Double

  public init(path: String, value: Double) {
    self.path = path
    self.value = value
  }
}

public struct EightSleepTimeSeriesSample: Hashable, Sendable {
  public let timestamp: Date
  public let value: Double

  public init(timestamp: Date, value: Double) {
    self.timestamp = timestamp
    self.value = value
  }
}

public struct EightSleepTimeSeries: Identifiable, Hashable, Sendable {
  public let id: String
  public let sessionID: String
  public let name: String
  public let sampleCount: Int
  public let firstTimestamp: Date?
  public let lastTimestamp: Date?
  public let latestNumericValue: Double?
  public let numericSamples: [EightSleepTimeSeriesSample]

  public init(
    id: String,
    sessionID: String,
    name: String,
    sampleCount: Int,
    firstTimestamp: Date?,
    lastTimestamp: Date?,
    latestNumericValue: Double?,
    numericSamples: [EightSleepTimeSeriesSample]
  ) {
    self.id = id
    self.sessionID = sessionID
    self.name = name
    self.sampleCount = sampleCount
    self.firstTimestamp = firstTimestamp
    self.lastTimestamp = lastTimestamp
    self.latestNumericValue = latestNumericValue
    self.numericSamples = numericSamples
  }
}

public enum EightSleepIntervalProbeStatus: Equatable, Hashable, Sendable {
  case available
  case unavailable(reason: String)

  public var label: String {
    switch self {
    case .available: "Available"
    case .unavailable(let reason): reason
    }
  }
}

public struct EightSleepSeriesSummary: Identifiable, Hashable, Sendable {
  public var id: String { path }

  public let path: String
  public let sampleCount: Int
  public let minimum: Double
  public let median: Double
  public let maximum: Double

  public init(
    path: String,
    sampleCount: Int,
    minimum: Double,
    median: Double,
    maximum: Double
  ) {
    self.path = path
    self.sampleCount = sampleCount
    self.minimum = minimum
    self.median = median
    self.maximum = maximum
  }
}

public struct EightSleepIntervalProbe: Hashable, Sendable {
  public let status: EightSleepIntervalProbeStatus
  public let fieldPaths: [String]
  public let metricFields: [EightSleepMetricField]
  public let series: [EightSleepSeriesSummary]

  public init(
    status: EightSleepIntervalProbeStatus,
    fieldPaths: [String],
    metricFields: [EightSleepMetricField],
    series: [EightSleepSeriesSummary]
  ) {
    self.status = status
    self.fieldPaths = fieldPaths
    self.metricFields = metricFields
    self.series = series
  }

  public static func unavailable(_ reason: String) -> EightSleepIntervalProbe {
    EightSleepIntervalProbe(
      status: .unavailable(reason: reason),
      fieldPaths: [],
      metricFields: [],
      series: []
    )
  }
}
