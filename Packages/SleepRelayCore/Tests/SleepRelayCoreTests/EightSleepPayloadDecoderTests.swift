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
            "heartRate": {"average": 57},
            "hrv": {"current": 48, "score": 92},
            "respiratoryRate": {"average": 14.2}
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
    #expect(night.averageRespiratoryRate == 14.2)
    #expect(night.explicitRestingHeartRateBPM == nil)
    #expect(night.timeSeries.first?.name == "heartRate")
    #expect(night.timeSeries.first?.sampleCount == 2)
    #expect(night.timeSeries.first?.latestNumericValue == 56)
  }

  @Test
  func rejectsPayloadWithoutDays() {
    #expect(throws: EightSleepAPIError.invalidPayload) {
      try EightSleepPayloadDecoder.decodeTrends(Data(#"{"result":{}}"#.utf8))
    }
  }
}
