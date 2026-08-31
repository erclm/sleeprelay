#if INTERNAL_TOOLS
  import Foundation
  import SleepRelayCore

  enum SavedEightSDNNEstimatorValidation {
    private static let baseDate = Date(timeIntervalSince1970: 1_900_000_000)

    static func run() -> Bool {
      validatesNonDegenerateFormula()
        && validatesTemporalIQRBoundary()
        && ignoresUnverifiedNightlyHeartRateAverage()
        && validatesNearestSampleRules()
        && validatesAbstentionAndFixedScenarios()
        && validatesFeatureAvailability()
        && validatesUnavailableStates()
        && validatesReportPrivacyBoundary()
    }

    private static func validatesNonDegenerateFormula() -> Bool {
      guard let result = availableResult(
        makeNight(
          rmssd: [(0, 40)],
          heartRate: [(0, 60)],
          respiratoryRate: [(0, 6)]
        )
      ) else { return false }

      // 40 / (2 * sin(pi * 6 / 60)) = 64.721359...
      return approximatelyEqual(result.medianModeledWindowProxyMilliseconds, 64.72135955)
        && result.timestampedModeledWindowCount == 1
        && result.modeledWindowIQRLowerMilliseconds == nil
        && result.modeledWindowIQRUpperMilliseconds == nil
        && result.warnings.contains(.insufficientTimestampedWindowsForIQR)
    }

    private static func validatesTemporalIQRBoundary() -> Bool {
      let offsets: [TimeInterval] = [0, 300, 600, 900]
      guard let result = availableResult(
        makeNight(
          rmssd: zip(offsets, [40.0, 44.0, 48.0, 52.0]).map { ($0.0, $0.1) },
          heartRate: offsets.map { ($0, 60) },
          respiratoryRate: offsets.map { ($0, 6) }
        )
      ) else { return false }

      return result.timestampedModeledWindowCount == 4
        && result.modeledWindowIQRLowerMilliseconds != nil
        && result.modeledWindowIQRUpperMilliseconds != nil
        && !result.warnings.contains(.insufficientTimestampedWindowsForIQR)
    }

    private static func ignoresUnverifiedNightlyHeartRateAverage() -> Bool {
      guard let result = availableResult(
        makeNight(
          averageHeartRateBPM: 60,
          nightlyRespiratoryRate: 6,
          rmssd: [(0, 40)],
          heartRate: nil,
          respiratoryRate: nil
        )
      ) else { return false }

      return result.medianModeledWindowProxyMilliseconds == nil
        && result.modeledWindowCount == 0
        && result.warnings.contains(.missingRespiratoryModel)
        && feature(.heartRate, in: result)?.isAvailable == false
    }

    private static func validatesNearestSampleRules() -> Bool {
      guard let toleranceEdge = availableResult(
        makeNight(
          rmssd: [(0, 40)],
          heartRate: [(600, 60)],
          respiratoryRate: [(5_400, 6)]
        )
      ) else { return false }

      guard let tiedNearest = availableResult(
        makeNight(
          rmssd: [(0, 40)],
          heartRate: [(-60, 50), (60, 70)],
          respiratoryRate: [(0, 6)]
        )
      ) else { return false }

      return toleranceEdge.nearbyHeartRateWindowCount == 1
        && toleranceEdge.nearbyRespiratoryRateWindowCount == 1
        && tiedNearest.nearbyHeartRateWindowCount == 0
        && tiedNearest.warnings.contains(.heartRateSeriesMedianFallback)
        && approximatelyEqual(tiedNearest.medianModeledWindowProxyMilliseconds, 64.72135955)
    }

    private static func validatesAbstentionAndFixedScenarios() -> Bool {
      guard let result = availableResult(
        makeNight(
          rmssd: [(0, 200)],
          heartRate: [(0, 200)],
          respiratoryRate: [(0, 4)]
        )
      ) else { return false }

      return result.medianModeledWindowProxyMilliseconds == nil
        && result.warnings.contains(.missingRespiratoryModel)
        && approximatelyEqual(result.uncorrelatedScenarioMilliseconds, 200 / sqrt(2))
        && approximatelyEqual(result.moderateCorrelationScenarioMilliseconds, 200)
        && approximatelyEqual(result.highCorrelationScenarioMilliseconds, 400)
    }

    private static func validatesFeatureAvailability() -> Bool {
      guard let result = availableResult(
        makeNight(
          rmssd: [(0, 40)],
          heartRate: [(0, 60)],
          respiratoryRate: [(0, 6)],
          lightSleepSeconds: 1_000,
          deepSleepSeconds: nil,
          remSleepSeconds: 500,
          additionalSeries: [
            makeSeries(name: "tnt", values: [], sessionID: "secret-session"),
            makeSeries(name: "tempBedC", values: [], sessionID: "secret-session"),
            makeSeries(name: "shortAwakes", values: [], sessionID: "secret-session"),
          ]
        )
      ) else { return false }

      return feature(.sleepStages, in: result)?.isAvailable == false
        && feature(.movement, in: result)?.isAvailable == false
        && feature(.environmentalTemperature, in: result)?.isAvailable == false
        && feature(.shortAwakes, in: result)?.isAvailable == false
    }

    private static func validatesUnavailableStates() -> Bool {
      let noSession = makeNight(
        latestSessionID: nil,
        rmssd: [(0, 40)],
        heartRate: [(0, 60)],
        respiratoryRate: [(0, 6)]
      )
      let noRMSSD = makeNight(
        nightlyRMSSD: nil,
        rmssd: nil,
        heartRate: [(0, 60)],
        respiratoryRate: [(0, 6)]
      )

      guard case .unavailable(.missingSelectedSession) = SavedEightSDNNEstimator.estimate(noSession)
      else { return false }
      guard case .unavailable(.missingRMSSD) = SavedEightSDNNEstimator.estimate(noRMSSD)
      else { return false }
      return true
    }

    private static func validatesReportPrivacyBoundary() -> Bool {
      let secretNightID = "night-private-alpha"
      let secretSessionID = "session-private-beta"
      let night = makeNight(
        id: secretNightID,
        day: "2026-08-30",
        latestSessionID: secretSessionID,
        nightlyRMSSD: 41.555,
        rmssd: [(0, 40.123_456_7), (300, 42.987_654_3)],
        heartRate: [(0, 60), (300, 61)],
        respiratoryRate: [(0, 6), (300, 7)]
      )
      guard let result = availableResult(night) else { return false }

      let report = SavedEightSDNNReport.make(for: night, estimate: result)
      let formatter = ISO8601DateFormatter()
      let exactTimestamp = formatter.string(from: baseDate)

      return report.contains("Night: 2026-08-30")
        && report.contains("measurements included")
        && report.contains("Median modeled SDNN proxy")
        && !report.contains(secretNightID)
        && !report.contains(secretSessionID)
        && !report.contains(exactTimestamp)
        && !report.contains("40.1234567")
        && !report.contains("42.9876543")
    }

    private static func availableResult(
      _ night: EightSleepNight
    ) -> SavedEightSDNNHypothesisResult? {
      guard case .available(let result) = SavedEightSDNNEstimator.estimate(night) else {
        return nil
      }
      return result
    }

    private static func feature(
      _ feature: SavedEightSDNNFeature,
      in result: SavedEightSDNNHypothesisResult
    ) -> SavedEightSDNNFeatureCoverage? {
      result.featureCoverage.first { $0.feature == feature }
    }

    private static func approximatelyEqual(
      _ lhs: Double?,
      _ rhs: Double,
      tolerance: Double = 0.000_1
    ) -> Bool {
      guard let lhs else { return false }
      return abs(lhs - rhs) <= tolerance
    }

    private static func makeNight(
      id: String = "secret-night",
      day: String = "2026-08-30",
      latestSessionID: String? = "secret-session",
      averageHeartRateBPM: Double? = nil,
      nightlyRMSSD: Double? = 40,
      nightlyRespiratoryRate: Double? = nil,
      rmssd: [(TimeInterval, Double)]?,
      heartRate: [(TimeInterval, Double)]?,
      respiratoryRate: [(TimeInterval, Double)]?,
      lightSleepSeconds: Double? = 1_000,
      deepSleepSeconds: Double? = 1_000,
      remSleepSeconds: Double? = 1_000,
      additionalSeries: [EightSleepTimeSeries] = []
    ) -> EightSleepNight {
      let sessionID = latestSessionID ?? "unselected-session"
      var series = additionalSeries
      if let rmssd {
        series.append(makeSeries(name: "rmssd", values: rmssd, sessionID: sessionID))
      }
      if let heartRate {
        series.append(
          makeSeries(name: "heartRate", values: heartRate, sessionID: sessionID)
        )
      }
      if let respiratoryRate {
        series.append(
          makeSeries(
            name: "nemeanRespiratoryRate",
            values: respiratoryRate,
            sessionID: sessionID
          )
        )
      }

      var metrics: [EightSleepMetricField] = []
      if let nightlyRMSSD {
        metrics.append(
          EightSleepMetricField(path: "sleepQualityScore.hrv.current", value: nightlyRMSSD)
        )
      }
      if let nightlyRespiratoryRate {
        metrics.append(
          EightSleepMetricField(
            path: "sleepQualityScore.respiratoryRate.current",
            value: nightlyRespiratoryRate
          )
        )
      }

      return EightSleepNight(
        id: id,
        day: day,
        presenceStart: baseDate.addingTimeInterval(-1_000),
        presenceEnd: baseDate.addingTimeInterval(8_000),
        isProcessing: false,
        score: 80,
        sleepDurationSeconds: 7_200,
        averageHeartRateBPM: averageHeartRateBPM,
        explicitRestingHeartRateBPM: nil,
        reportedHRVMilliseconds: nightlyRMSSD,
        averageRespiratoryRate: nightlyRespiratoryRate,
        tossAndTurns: nil,
        lightSleepSeconds: lightSleepSeconds,
        deepSleepSeconds: deepSleepSeconds,
        remSleepSeconds: remSleepSeconds,
        availableFields: [],
        metricFields: metrics,
        timeSeries: series,
        latestSessionID: latestSessionID,
        intervalProbe: nil
      )
    }

    private static func makeSeries(
      name: String,
      values: [(TimeInterval, Double)],
      sessionID: String
    ) -> EightSleepTimeSeries {
      let samples = values.map { offset, value in
        EightSleepTimeSeriesSample(
          timestamp: baseDate.addingTimeInterval(offset),
          value: value
        )
      }
      return EightSleepTimeSeries(
        id: "\(sessionID)-\(name)",
        sessionID: sessionID,
        name: name,
        sampleCount: samples.count,
        firstTimestamp: samples.map(\.timestamp).min(),
        lastTimestamp: samples.map(\.timestamp).max(),
        latestNumericValue: samples.last?.value,
        numericSamples: samples
      )
    }
  }
#endif
