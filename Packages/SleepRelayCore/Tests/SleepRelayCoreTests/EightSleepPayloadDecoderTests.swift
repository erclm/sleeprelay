import Foundation
import Testing

@testable import SleepRelayCore

struct EightSleepPayloadDecoderTests {
  @Test
  func decodesKnownMetricsAndTimeSeriesWithoutTreatingHRVScoreAsAValue() throws {
    let data = Data(
      #"""
      {
        "days": [{
          "day": "2026-08-28",
          "presenceStart": "2026-08-28T06:00:00Z",
          "presenceEnd": "2026-08-28T14:00:00Z",
          "processing": false,
          "score": 86,
          "sleepDuration": 27000,
          "lightDuration": 14000,
          "deepDuration": 5000,
          "remDuration": 8000,
          "sleepQualityScore": {
            "heartRate": {"current": 55, "average": 57},
            "hrv": {"current": 48, "score": 92},
            "respiratoryRate": {"current": 14.5, "average": 14.2}
          },
          "sessions": [{
            "id": "session-1",
            "timeseries": {
              "heartRate": [
                ["2026-08-28T06:00:00Z", 58],
                ["2026-08-28T06:05:00Z", 56]
              ]
            }
          }]
        }]
      }
      """#.utf8
    )

    let nights = try EightSleepPayloadDecoder.decodeTrends(data)
    let night = try #require(nights.first)

    #expect(night.id == "session-1")
    #expect(night.day == "2026-08-28")
    #expect(night.score == 86)
    #expect(night.averageHeartRateBPM == 57)
    #expect(night.reportedHRVMilliseconds == 48)
    #expect(night.diagnosticNightlyHRVCurrentMilliseconds == 48)
    #expect(night.averageRespiratoryRate == 14.5)
    #expect(night.explicitRestingHeartRateBPM == 55)
    #expect(night.timeSeries.first?.name == "heartRate")
    #expect(night.timeSeries.first?.sampleCount == 2)
    #expect(night.timeSeries.first?.latestNumericValue == 56)
    #expect(night.timeSeries.first?.numericSamples.count == 2)
    #expect(
      night.metricFields.contains(
        EightSleepMetricField(path: "sleepQualityScore.heartRate.average", value: 57)
      )
    )
  }

  @Test
  func doesNotTreatHRVAverageAsTheCurrentNightlySummary() throws {
    let data = Data(
      #"{"days":[{"day":"2026-08-28","sleepQualityScore":{"hrv":{"average":47}},"sessions":[]}] }"#.utf8
    )

    let night = try #require(EightSleepPayloadDecoder.decodeTrends(data).first)

    #expect(night.reportedHRVMilliseconds == 47)
    #expect(night.diagnosticNightlyHRVCurrentMilliseconds == nil)
  }

  @Test
  func discoversAnUnrecognizedNestedRestingHeartRateFieldWithoutRawPayloadStorage() throws {
    let data = Data(
      #"{"days":[{"day":"2026-08-28","biometrics":{"rhr":55},"sessions":[]}]}"#.utf8
    )

    let night = try #require(EightSleepPayloadDecoder.decodeTrends(data).first)

    #expect(night.explicitRestingHeartRateBPM == 55)
    #expect(night.metricFields == [EightSleepMetricField(path: "biometrics.rhr", value: 55)])
  }

  @Test
  func prefersExplicitMainSessionOverArrayOrder() throws {
    let data = Data(
      #"{"days":[{"day":"2026-08-28","mainSessionId":"main-session","sessions":[{"id":"main-session","timeseries":{}},{"id":"later-array-session","timeseries":{}}]}]}"#.utf8
    )

    let night = try #require(EightSleepPayloadDecoder.decodeTrends(data).first)

    #expect(night.latestSessionID == "main-session")
    #expect(night.id == "main-session")
  }

  @Test
  func rejectsUnsafeDurationsWithoutDroppingValidValues() throws {
    let data = Data(
      #"{"days":[{"day":"2026-08-28","sleepDurationSeconds":"27000","lightDuration":-1,"deepDuration":172801,"remDuration":"1e300","sessions":[]}]}"#.utf8
    )

    let night = try #require(EightSleepPayloadDecoder.decodeTrends(data).first)

    #expect(night.sleepDurationSeconds == 27_000)
    #expect(night.lightSleepSeconds == nil)
    #expect(night.deepSleepSeconds == nil)
    #expect(night.remSleepSeconds == nil)
  }

  @Test
  func rejectsPayloadWithoutDays() {
    #expect(throws: EightSleepAPIError.invalidPayload) {
      try EightSleepPayloadDecoder.decodeTrends(Data(#"{"result":{}}"#.utf8))
    }
  }
}
