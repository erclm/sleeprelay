import Foundation

public struct EightSleepCredentials: Sendable {
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

  public init(from: String, to: String, timeZoneIdentifier: String) {
    self.from = from
    self.to = to
    self.timeZoneIdentifier = timeZoneIdentifier
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
  public let timeSeries: [EightSleepTimeSeries]

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
    timeSeries: [EightSleepTimeSeries]
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
    self.timeSeries = timeSeries
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

  public init(
    id: String,
    sessionID: String,
    name: String,
    sampleCount: Int,
    firstTimestamp: Date?,
    lastTimestamp: Date?,
    latestNumericValue: Double?
  ) {
    self.id = id
    self.sessionID = sessionID
    self.name = name
    self.sampleCount = sampleCount
    self.firstTimestamp = firstTimestamp
    self.lastTimestamp = lastTimestamp
    self.latestNumericValue = latestNumericValue
  }
}
