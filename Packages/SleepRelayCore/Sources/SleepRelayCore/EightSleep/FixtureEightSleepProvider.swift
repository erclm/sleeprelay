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
        metricFields: [
          EightSleepMetricField(path: "sleepQualityScore.heartRate.average", value: 57),
          EightSleepMetricField(path: "sleepQualityScore.hrv.current", value: 48),
          EightSleepMetricField(path: "sleepQualityScore.respiratoryRate.average", value: 14.2),
        ],
        timeSeries: [
          EightSleepTimeSeries(
            id: "fixture-heartRate",
            sessionID: "fixture-session",
            name: "heartRate",
            sampleCount: 92,
            firstTimestamp: Date(timeIntervalSince1970: 1_788_038_400),
            lastTimestamp: Date(timeIntervalSince1970: 1_788_066_000),
            latestNumericValue: 55,
            numericSamples: [
              EightSleepTimeSeriesSample(
                timestamp: Date(timeIntervalSince1970: 1_788_038_400), value: 58),
              EightSleepTimeSeriesSample(
                timestamp: Date(timeIntervalSince1970: 1_788_038_700), value: 56),
              EightSleepTimeSeriesSample(
                timestamp: Date(timeIntervalSince1970: 1_788_039_000), value: 55),
              EightSleepTimeSeriesSample(
                timestamp: Date(timeIntervalSince1970: 1_788_039_300), value: 57),
            ]
          ),
          EightSleepTimeSeries(
            id: "fixture-hrv",
            sessionID: "fixture-session",
            name: "hrv",
            sampleCount: 31,
            firstTimestamp: Date(timeIntervalSince1970: 1_788_038_400),
            lastTimestamp: Date(timeIntervalSince1970: 1_788_066_000),
            latestNumericValue: 51,
            numericSamples: []
          ),
        ],
        latestSessionID: "fixture-session",
        intervalProbe: EightSleepIntervalProbe(
          status: .available,
          fieldPaths: ["intervals[].heartRate", "summary.hrv"],
          metricFields: [
            EightSleepMetricField(path: "summary.heartRate.average", value: 57)
          ],
          series: [
            EightSleepSeriesSummary(
              path: "intervals[].heartRate",
              sampleCount: 4,
              minimum: 55,
              median: 56.5,
              maximum: 58
            )
          ]
        )
      )
    ]
  )
}
