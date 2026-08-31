#if INTERNAL_TOOLS
  import Foundation
  import SleepRelayCore

  enum SavedEightSDNNEstimation: Equatable, Sendable {
    case available(SavedEightSDNNHypothesisResult)
    case unavailable(SavedEightSDNNUnavailableReason)
  }

  enum SavedEightSDNNUnavailableReason: Equatable, Sendable {
    case processing
    case missingSelectedSession
    case missingRMSSD
  }

  enum SavedEightSDNNWarning: Equatable, Hashable, Sendable {
    case unvalidatedModel
    case nightlyRMSSDFallback
    case heartRateSeriesMedianFallback
    case respiratoryRateSeriesMedianFallback
    case nightlyRespiratoryRateFallback
    case insufficientTimestampedWindowsForIQR
    case unknownAggregationWindowAlignment
    case missingRespiratoryModel
    case ambiguousSeries
    case contextualFieldsNotCalibrated
  }

  enum SavedEightSDNNFeature: String, CaseIterable, Equatable, Hashable, Sendable {
    case rmssd
    case heartRate
    case respiratoryRate
    case opaqueHRV
    case sleepStages
    case sleepDuration
    case movement
    case environmentalTemperature
    case shortAwakes
    case nightlyScore
    case restingHeartRate
  }

  struct SavedEightSDNNFeatureCoverage: Equatable, Hashable, Sendable {
    let feature: SavedEightSDNNFeature
    let isAvailable: Bool
    let isUsedByModel: Bool
  }

  struct SavedEightSDNNHypothesisResult: Equatable, Sendable {
    static let algorithmVersion = "saved-respiratory-sinusoid-v0"

    let medianModeledWindowProxyMilliseconds: Double?
    let modeledWindowIQRLowerMilliseconds: Double?
    let modeledWindowIQRUpperMilliseconds: Double?
    let assumptionRangeLowerMilliseconds: Double
    let assumptionRangeUpperMilliseconds: Double
    let uncorrelatedScenarioMilliseconds: Double
    let moderateCorrelationScenarioMilliseconds: Double
    let highCorrelationScenarioMilliseconds: Double
    let rmssdMedianMilliseconds: Double
    let reportedNightlyRMSSDCurrentMilliseconds: Double?
    let opaqueHRVMedian: Double?
    let rmssdObservationCount: Int
    let modeledWindowCount: Int
    let timestampedModeledWindowCount: Int
    let nearbyHeartRateWindowCount: Int
    let nearbyRespiratoryRateWindowCount: Int
    let rejectedRMSSDTimestampGroupCount: Int
    let featureCoverage: [SavedEightSDNNFeatureCoverage]
    let warnings: Set<SavedEightSDNNWarning>
  }

  enum SavedEightSDNNEstimator {
    private static let heartRateTolerance: TimeInterval = 10 * 60
    private static let respiratoryRateTolerance: TimeInterval = 90 * 60

    static func estimate(_ night: EightSleepNight) -> SavedEightSDNNEstimation {
      guard !night.isProcessing else { return .unavailable(.processing) }
      guard let selectedSessionID = night.latestSessionID else {
        return .unavailable(.missingSelectedSession)
      }

      let currentRMSSD = exactMetric(
        path: "sleepQualityScore.hrv.current",
        in: night,
        validRange: 1...200
      )
      let rmssdSelection = selectedSeries(
        named: "rmssd",
        sessionID: selectedSessionID,
        in: night
      )
      let rmssdSanitization = sanitizedSamples(
        rmssdSelection.samples,
        in: night,
        validRange: 1...200
      )

      let rmssdInputs: [ModelInput]
      let usedNightlyRMSSD: Bool
      if !rmssdSanitization.samples.isEmpty {
        rmssdInputs = rmssdSanitization.samples.map {
          ModelInput(timestamp: $0.timestamp, rmssd: $0.value)
        }
        usedNightlyRMSSD = false
      } else if let currentRMSSD {
        rmssdInputs = [ModelInput(timestamp: nil, rmssd: currentRMSSD)]
        usedNightlyRMSSD = true
      } else {
        return .unavailable(.missingRMSSD)
      }

      let heartRateSelection = selectedSeries(
        named: "heartrate",
        sessionID: selectedSessionID,
        in: night
      )
      let heartRateSamples = sanitizedSamples(
        heartRateSelection.samples,
        in: night,
        validRange: 20...250
      ).samples
      let heartRateSeriesMedian = median(heartRateSamples.map(\.value))

      let respiratorySelection = preferredRespiratorySeries(
        sessionID: selectedSessionID,
        in: night
      )
      let respiratorySamples = sanitizedSamples(
        respiratorySelection.samples,
        in: night,
        validRange: 4...40
      ).samples
      let respiratoryRateSeriesMedian = median(respiratorySamples.map(\.value))
      let nightlyRespiratoryRate = exactMetric(
        path: "sleepQualityScore.respiratoryRate.current",
        in: night,
        validRange: 4...40
      )

      var modeledValues: [Double] = []
      var timestampedModeledValues: [Double] = []
      var nearbyHeartRateWindowCount = 0
      var nearbyRespiratoryRateWindowCount = 0
      var usedHeartRateSeriesMedian = false
      var usedRespiratoryRateSeriesMedian = false
      var usedNightlyRespiratoryRate = false

      for input in rmssdInputs {
        let nearbyHeartRate = input.timestamp.flatMap {
          nearestValue(to: $0, in: heartRateSamples, tolerance: heartRateTolerance)
        }
        let nearbyRespiratoryRate = input.timestamp.flatMap {
          nearestValue(to: $0, in: respiratorySamples, tolerance: respiratoryRateTolerance)
        }
        let heartRate = nearbyHeartRate ?? heartRateSeriesMedian
        let respiratoryRate = nearbyRespiratoryRate
          ?? respiratoryRateSeriesMedian
          ?? nightlyRespiratoryRate

        guard
          let heartRate,
          let respiratoryRate,
          let estimate = respiratorySinusoidEstimate(
            rmssd: input.rmssd,
            heartRate: heartRate,
            respiratoryRate: respiratoryRate
          )
        else { continue }

        modeledValues.append(estimate)
        if input.timestamp != nil { timestampedModeledValues.append(estimate) }
        if nearbyHeartRate != nil {
          nearbyHeartRateWindowCount += 1
        } else {
          usedHeartRateSeriesMedian = true
        }
        if nearbyRespiratoryRate != nil {
          nearbyRespiratoryRateWindowCount += 1
        } else if respiratoryRateSeriesMedian != nil {
          usedRespiratoryRateSeriesMedian = true
        } else {
          usedNightlyRespiratoryRate = true
        }
      }

      let rmssdValues = rmssdInputs.map(\.rmssd)
      guard let rmssdMedian = median(rmssdValues) else {
        return .unavailable(.missingRMSSD)
      }

      let uncorrelated = rmssdMedian / sqrt(2)
      let moderateCorrelation = rmssdMedian
      let highCorrelation = 2 * rmssdMedian
      let modelEstimate = median(modeledValues)
      let quartiles = timestampedModeledValues.count >= 4
        ? quartiles(of: timestampedModeledValues)
        : nil
      let assumptionValues = [
        uncorrelated,
        moderateCorrelation,
        highCorrelation,
        modelEstimate,
      ].compactMap { $0 }.filter { $0.isFinite && $0 > 0 }

      var warnings: Set<SavedEightSDNNWarning> = [
        .unvalidatedModel,
        .contextualFieldsNotCalibrated,
      ]
      if usedNightlyRMSSD { warnings.insert(.nightlyRMSSDFallback) }
      if usedHeartRateSeriesMedian { warnings.insert(.heartRateSeriesMedianFallback) }
      if usedRespiratoryRateSeriesMedian {
        warnings.insert(.respiratoryRateSeriesMedianFallback)
      }
      if usedNightlyRespiratoryRate { warnings.insert(.nightlyRespiratoryRateFallback) }
      if modelEstimate == nil {
        warnings.insert(.missingRespiratoryModel)
      } else if timestampedModeledValues.count < 4 {
        warnings.insert(.insufficientTimestampedWindowsForIQR)
      }
      if !timestampedModeledValues.isEmpty {
        warnings.insert(.unknownAggregationWindowAlignment)
      }
      if rmssdSelection.isAmbiguous || heartRateSelection.isAmbiguous
        || respiratorySelection.isAmbiguous
      {
        warnings.insert(.ambiguousSeries)
      }

      let opaqueHRVSelection = selectedSeries(
        named: "hrv",
        sessionID: selectedSessionID,
        in: night
      )
      let opaqueHRVSamples = sanitizedSamples(
        opaqueHRVSelection.samples,
        in: night,
        validRange: nil
      ).samples

      let features = featureCoverage(
        night: night,
        rmssdIsAvailable: !rmssdInputs.isEmpty,
        heartRateIsAvailable: !heartRateSamples.isEmpty,
        respiratoryRateIsAvailable: !respiratorySamples.isEmpty
          || nightlyRespiratoryRate != nil,
        opaqueHRVIsAvailable: !opaqueHRVSamples.isEmpty,
        modelIsAvailable: modelEstimate != nil,
        selectedSessionID: selectedSessionID
      )

      return .available(
        SavedEightSDNNHypothesisResult(
          medianModeledWindowProxyMilliseconds: modelEstimate,
          modeledWindowIQRLowerMilliseconds: quartiles?.lower,
          modeledWindowIQRUpperMilliseconds: quartiles?.upper,
          assumptionRangeLowerMilliseconds: assumptionValues.min() ?? uncorrelated,
          assumptionRangeUpperMilliseconds: assumptionValues.max() ?? highCorrelation,
          uncorrelatedScenarioMilliseconds: uncorrelated,
          moderateCorrelationScenarioMilliseconds: moderateCorrelation,
          highCorrelationScenarioMilliseconds: highCorrelation,
          rmssdMedianMilliseconds: rmssdMedian,
          reportedNightlyRMSSDCurrentMilliseconds: currentRMSSD,
          opaqueHRVMedian: median(opaqueHRVSamples.map(\.value)),
          rmssdObservationCount: rmssdInputs.count,
          modeledWindowCount: modeledValues.count,
          timestampedModeledWindowCount: timestampedModeledValues.count,
          nearbyHeartRateWindowCount: nearbyHeartRateWindowCount,
          nearbyRespiratoryRateWindowCount: nearbyRespiratoryRateWindowCount,
          rejectedRMSSDTimestampGroupCount: rmssdSanitization.rejectedTimestampGroupCount,
          featureCoverage: features,
          warnings: warnings
        )
      )
    }

    private static func respiratorySinusoidEstimate(
      rmssd: Double,
      heartRate: Double,
      respiratoryRate: Double
    ) -> Double? {
      guard
        rmssd.isFinite,
        heartRate.isFinite,
        respiratoryRate.isFinite,
        rmssd > 0,
        heartRate > 0,
        respiratoryRate > 0
      else { return nil }

      let cyclesPerBeat = respiratoryRate / heartRate
      guard cyclesPerBeat > 0, cyclesPerBeat < 0.5 else { return nil }
      let denominator = 2 * sin(.pi * cyclesPerBeat)
      guard denominator.isFinite, denominator > 0.1 else { return nil }
      let estimate = rmssd / denominator
      guard estimate.isFinite, estimate > 0, estimate <= 500 else { return nil }
      return estimate
    }

    private static func exactMetric(
      path: String,
      in night: EightSleepNight,
      validRange: ClosedRange<Double>
    ) -> Double? {
      guard
        let value = night.metricFields.first(where: { $0.path == path })?.value,
        value.isFinite,
        validRange.contains(value)
      else { return nil }
      return value
    }

    private static func selectedSeries(
      named normalizedName: String,
      sessionID: String,
      in night: EightSleepNight
    ) -> SeriesSelection {
      let matches = night.timeSeries.filter {
        $0.sessionID == sessionID && normalize($0.name) == normalizedName
      }
      guard matches.count == 1, let series = matches.first else {
        return SeriesSelection(samples: [], isAmbiguous: matches.count > 1)
      }
      return SeriesSelection(samples: series.numericSamples, isAmbiguous: false)
    }

    private static func preferredRespiratorySeries(
      sessionID: String,
      in night: EightSleepNight
    ) -> SeriesSelection {
      for name in ["nemeanrespiratoryrate", "respiratoryrate"] {
        let selection = selectedSeries(named: name, sessionID: sessionID, in: night)
        if selection.isAmbiguous || !selection.samples.isEmpty { return selection }
      }
      return SeriesSelection(samples: [], isAmbiguous: false)
    }

    private static func sanitizedSamples(
      _ samples: [EightSleepTimeSeriesSample],
      in night: EightSleepNight,
      validRange: ClosedRange<Double>?
    ) -> SanitizedSamples {
      let filtered = samples.filter { sample in
        guard sample.value.isFinite else { return false }
        if let validRange, !validRange.contains(sample.value) { return false }
        if let start = night.presenceStart, sample.timestamp < start { return false }
        if let end = night.presenceEnd, sample.timestamp >= end { return false }
        return true
      }
      let groups = Dictionary(grouping: filtered, by: \.timestamp)
      var result: [EightSleepTimeSeriesSample] = []
      var rejectedTimestampGroupCount = 0

      for timestamp in groups.keys.sorted() {
        guard let group = groups[timestamp], let first = group.first else { continue }
        if group.allSatisfy({ $0.value == first.value }) {
          result.append(first)
        } else {
          rejectedTimestampGroupCount += 1
        }
      }
      return SanitizedSamples(
        samples: result,
        rejectedTimestampGroupCount: rejectedTimestampGroupCount
      )
    }

    private static func nearestValue(
      to timestamp: Date,
      in samples: [EightSleepTimeSeriesSample],
      tolerance: TimeInterval
    ) -> Double? {
      let candidates = samples.compactMap { sample -> (distance: TimeInterval, value: Double)? in
        let distance = abs(sample.timestamp.timeIntervalSince(timestamp))
        guard distance <= tolerance else { return nil }
        return (distance, sample.value)
      }
      guard let nearestDistance = candidates.map(\.distance).min() else { return nil }
      let nearest = candidates.filter { abs($0.distance - nearestDistance) < 0.001 }
      guard let first = nearest.first else { return nil }
      return nearest.allSatisfy { $0.value == first.value } ? first.value : nil
    }

    private static func featureCoverage(
      night: EightSleepNight,
      rmssdIsAvailable: Bool,
      heartRateIsAvailable: Bool,
      respiratoryRateIsAvailable: Bool,
      opaqueHRVIsAvailable: Bool,
      modelIsAvailable: Bool,
      selectedSessionID: String
    ) -> [SavedEightSDNNFeatureCoverage] {
      let selectedSeries = night.timeSeries.filter { $0.sessionID == selectedSessionID }
      let stageDurations = [
        night.lightSleepSeconds,
        night.deepSleepSeconds,
        night.remSleepSeconds,
      ]
      let hasStages = stageDurations.allSatisfy { value in
        value.map { $0.isFinite && $0 >= 0 } ?? false
      }
      let hasMovement = night.tossAndTurns.map { $0.isFinite && $0 >= 0 } ?? false
        || hasUsableSeries(containing: "tnt", in: selectedSeries, night: night)
      let hasTemperature = hasUsableSeries(
        containing: "temp",
        in: selectedSeries,
        night: night
      )
      let hasShortAwakes = hasUsableSeries(
        containing: "shortawakes",
        in: selectedSeries,
        night: night
      )

      let available: [SavedEightSDNNFeature: Bool] = [
        .rmssd: rmssdIsAvailable,
        .heartRate: heartRateIsAvailable,
        .respiratoryRate: respiratoryRateIsAvailable,
        .opaqueHRV: opaqueHRVIsAvailable,
        .sleepStages: hasStages,
        .sleepDuration: night.sleepDurationSeconds.map { $0.isFinite && $0 > 0 } ?? false,
        .movement: hasMovement,
        .environmentalTemperature: hasTemperature,
        .shortAwakes: hasShortAwakes,
        .nightlyScore: night.score.map(\.isFinite) ?? false,
        .restingHeartRate: night.discoveredRestingHeartRateBPM.map(\.isFinite) ?? false,
      ]

      return SavedEightSDNNFeature.allCases.map { feature in
        SavedEightSDNNFeatureCoverage(
          feature: feature,
          isAvailable: available[feature] ?? false,
          isUsedByModel: feature == .rmssd
            || (modelIsAvailable && (feature == .heartRate || feature == .respiratoryRate))
        )
      }
    }

    private static func hasUsableSeries(
      containing normalizedFragment: String,
      in series: [EightSleepTimeSeries],
      night: EightSleepNight
    ) -> Bool {
      series.contains { item in
        normalize(item.name).contains(normalizedFragment)
          && item.numericSamples.contains { sample in
            guard sample.value.isFinite else { return false }
            if let start = night.presenceStart, sample.timestamp < start { return false }
            if let end = night.presenceEnd, sample.timestamp >= end { return false }
            return true
          }
      }
    }

    private static func median(_ values: [Double]) -> Double? {
      guard !values.isEmpty else { return nil }
      let sorted = values.sorted()
      let midpoint = sorted.count / 2
      if sorted.count.isMultiple(of: 2) {
        return (sorted[midpoint - 1] + sorted[midpoint]) / 2
      }
      return sorted[midpoint]
    }

    private static func quartiles(of values: [Double]) -> (lower: Double, upper: Double)? {
      let sorted = values.sorted()
      guard sorted.count >= 4 else { return nil }
      let midpoint = sorted.count / 2
      let lowerHalf = Array(sorted[..<midpoint])
      let upperHalf = Array(sorted[(sorted.count.isMultiple(of: 2) ? midpoint : midpoint + 1)...])
      guard let lower = median(lowerHalf), let upper = median(upperHalf) else { return nil }
      return (lower, upper)
    }

    private static func normalize(_ value: String) -> String {
      value.lowercased().filter(\.isLetter)
    }

    private struct SeriesSelection {
      let samples: [EightSleepTimeSeriesSample]
      let isAmbiguous: Bool
    }

    private struct SanitizedSamples {
      let samples: [EightSleepTimeSeriesSample]
      let rejectedTimestampGroupCount: Int
    }

    private struct ModelInput {
      let timestamp: Date?
      let rmssd: Double
    }
  }
#endif
