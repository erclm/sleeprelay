import Foundation

public actor FixtureEightSleepProvider: EightSleepProviding {
  public init() {}

  public func connect(
    credentials: EightSleepCredentials,
    request: EightSleepFetchRequest
  ) async throws -> EightSleepSnapshot {
    Self.snapshot
  }

  public func refresh(request: EightSleepFetchRequest) async throws -> EightSleepSnapshot {
    Self.snapshot
  }

  public func disconnect() {}

  public static let snapshot = EightSleepSnapshot(
    fetchedAt: Date(timeIntervalSince1970: 1_787_990_400),
    nights: [
      EightSleepNight(
        id: "fixture-night",
        day: "2026-08-28",
        presenceStart: Date(timeIntervalSince1970: 1_788_038_400),
        presenceEnd: Date(timeIntervalSince1970: 1_788_067_200),
        isProcessing: false,
        score: 86,
        sleepDurationSeconds: 27_240,
        averageHeartRateBPM: 57,
        explicitRestingHeartRateBPM: nil,
        reportedHRVMilliseconds: 48,
        averageRespiratoryRate: 14.2,
        tossAndTurns: 19,
        lightSleepSeconds: 14_400,
        deepSleepSeconds: 5_400,
        remSleepSeconds: 7_440,
        availableFields: [
          "day", "presenceEnd", "presenceStart", "processing", "score",
          "sessions", "sleepDuration", "sleepQualityScore",
        ],
        timeSeries: [
          EightSleepTimeSeries(
            id: "fixture-heartRate",
            sessionID: "fixture-session",
            name: "heartRate",
            sampleCount: 92,
            firstTimestamp: Date(timeIntervalSince1970: 1_788_038_400),
            lastTimestamp: Date(timeIntervalSince1970: 1_788_066_000),
            latestNumericValue: 55
          ),
          EightSleepTimeSeries(
            id: "fixture-hrv",
            sessionID: "fixture-session",
            name: "hrv",
            sampleCount: 31,
            firstTimestamp: Date(timeIntervalSince1970: 1_788_038_400),
            lastTimestamp: Date(timeIntervalSince1970: 1_788_066_000),
            latestNumericValue: 51
          ),
        ]
      )
    ]
  )
}
