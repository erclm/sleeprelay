import Foundation
import Testing

@testable import SleepRelayCore

struct RestingHeartRateLabTests {
  @Test
  func calculatesTimestampBasedResearchCandidateAndSanitizesReport() {
    let start = Date(timeIntervalSince1970: 1_788_038_400)
    let samples = [60.0, 58, 55, 54, 56, 59].enumerated().map { index, value in
      EightSleepTimeSeriesSample(
        timestamp: start.addingTimeInterval(Double(index) * 5 * 60),
        value: value
      )
    }
    let night = makeNight(start: start, samples: samples)

    let analysis = RestingHeartRateLab.analyze(night)

    #expect(analysis.sampleCount == 6)
    #expect(analysis.minimumBPM == 54)
    #expect(analysis.medianBPM == 57)
    #expect(analysis.typicalCadenceSeconds == 300)
    #expect(analysis.experimentalLowWindowMedianBPM == 55.5)

    let report = RestingHeartRateLab.sanitizedReport(
      for: night,
      officialEightRestingHeartRateBPM: 57
    )
    #expect(report.contains("Official Eight app RHR (manual): 57 bpm"))
    #expect(report.contains("sleepQualityScore.heartRate.average"))
    #expect(!report.contains("session-secret"))
    #expect(!report.contains("user@example.com"))
    #expect(!report.contains("2026-08-28T"))
  }

  @Test
  func refusesCandidateWhenTimestampCoverageIsInsufficient() {
    let start = Date(timeIntervalSince1970: 1_788_038_400)
    let samples = [
      EightSleepTimeSeriesSample(timestamp: start, value: 55),
      EightSleepTimeSeriesSample(timestamp: start.addingTimeInterval(60), value: 54),
    ]
    let analysis = RestingHeartRateLab.analyze(makeNight(start: start, samples: samples))

    #expect(analysis.experimentalLowWindowMedianBPM == nil)
    #expect(analysis.explanation.contains("no 15-minute window"))
  }

  private func makeNight(
    start: Date,
    samples: [EightSleepTimeSeriesSample]
  ) -> EightSleepNight {
    EightSleepNight(
      id: "night-secret",
      day: "2026-08-28",
      presenceStart: start,
      presenceEnd: start.addingTimeInterval(8 * 60 * 60),
      isProcessing: false,
      score: 80,
      sleepDurationSeconds: 7 * 60 * 60,
      averageHeartRateBPM: 57,
      explicitRestingHeartRateBPM: nil,
      reportedHRVMilliseconds: 40,
      averageRespiratoryRate: 15,
      tossAndTurns: 10,
      lightSleepSeconds: nil,
      deepSleepSeconds: nil,
      remSleepSeconds: nil,
      availableFields: ["day", "sessions"],
      metricFields: [
        EightSleepMetricField(path: "sleepQualityScore.heartRate.average", value: 57)
      ],
      timeSeries: [
        EightSleepTimeSeries(
          id: "series-secret",
          sessionID: "session-secret",
          name: "heartRate",
          sampleCount: samples.count,
          firstTimestamp: samples.first?.timestamp,
          lastTimestamp: samples.last?.timestamp,
          latestNumericValue: samples.last?.value,
          numericSamples: samples
        )
      ],
      latestSessionID: "session-secret",
      intervalProbe: nil
    )
  }
}
