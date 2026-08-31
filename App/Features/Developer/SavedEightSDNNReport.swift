#if INTERNAL_TOOLS
  import Foundation
  import SleepRelayCore

  enum SavedEightSDNNReport {
    static func make(
      for night: EightSleepNight,
      estimate: SavedEightSDNNHypothesisResult
    ) -> String {
      var lines = [
        "Sleep Relay saved-data SDNN hypothesis — measurements included",
        "Format: saved-sdnn-hypothesis-v1",
        "Night: \(night.day)",
        "Algorithm: \(SavedEightSDNNHypothesisResult.algorithmVersion)",
        "Status: Experimental estimate; not measured SDNN",
        "Live data used: no",
        "Apple Health writes: disabled",
        "",
        "Model output",
        "- Median modeled SDNN proxy: \(formatMilliseconds(estimate.medianModeledWindowProxyMilliseconds))",
        "- Temporal proxy IQR (requires 4+ timestamped windows): \(formatRange(estimate.modeledWindowIQRLowerMilliseconds, estimate.modeledWindowIQRUpperMilliseconds))",
        "- Assumption span: \(formatNumber(estimate.assumptionRangeLowerMilliseconds))–\(formatNumber(estimate.assumptionRangeUpperMilliseconds)) ms",
        "- Uncorrelated scenario: \(formatNumber(estimate.uncorrelatedScenarioMilliseconds)) ms",
        "- Moderate-correlation scenario: \(formatNumber(estimate.moderateCorrelationScenarioMilliseconds)) ms",
        "- High-correlation scenario: \(formatNumber(estimate.highCorrelationScenarioMilliseconds)) ms",
        "",
        "Saved inputs",
        "- RMSSD median used: \(formatNumber(estimate.rmssdMedianMilliseconds)) ms",
        "- Eight nightly current RMSSD: \(formatMilliseconds(estimate.reportedNightlyRMSSDCurrentMilliseconds))",
        "- Usable RMSSD observations: \(estimate.rmssdObservationCount)",
        "- Modeled observations: \(estimate.modeledWindowCount)",
        "- Nearby saved heart-rate matches: \(estimate.nearbyHeartRateWindowCount)",
        "- Nearby saved respiratory-rate matches: \(estimate.nearbyRespiratoryRateWindowCount)",
        "- Opaque Eight hrv median: \(formatUnclassified(estimate.opaqueHRVMedian))",
        "",
        "Warnings",
      ]
      let warnings = estimate.warnings.sorted { warningLabel($0) < warningLabel($1) }
      lines.append(contentsOf: warnings.isEmpty ? ["- none"] : warnings.map {
        "- \(warningLabel($0))"
      })
      lines.append(contentsOf: [
        "",
        "Interpretation",
        "The respiratory model assumes breathing dominates beat-to-beat variability. Its point is the median of available modeled proxy values: timestamped values are window proxies, while a nightly-current fallback is a one-point summary hypothesis. It is not whole-night SDNN. The temporal IQR describes variation among timestamped model outputs, not estimation uncertainty. Nearby timestamps do not prove Eight used matching physiological windows. The model accepts RMSSD 1–200 ms, HR 20–250 bpm, and respiration 4–40/min, and requires 0 < respiration/HR < 0.5, a sine denominator above 0.1, and output no greater than 500 ms. The scenario span changes the missing adjacent-interval correlation assumption. It is not a confidence interval or a measured SDNN range, and actual SDNN can fall outside it.",
        "",
        "Privacy",
        "Contains the sleep day, aggregate Eight measurements, and derived estimates. Excludes account, user, device, and session identifiers; credentials; exact timestamps; and raw samples.",
      ])
      return lines.joined(separator: "\n")
    }

    static func warningLabel(_ warning: SavedEightSDNNWarning) -> String {
      switch warning {
      case .unvalidatedModel:
        "No paired RR/ECG ground truth has validated this model"
      case .nightlyRMSSDFallback:
        "The RMSSD time series was unavailable; the exact nightly current was used once"
      case .heartRateSeriesMedianFallback:
        "Some windows used the selected session's heart-rate median"
      case .respiratoryRateSeriesMedianFallback:
        "Some windows used the selected session's respiratory-rate median"
      case .nightlyRespiratoryRateFallback:
        "Some windows used the exact nightly respiratory-rate current"
      case .insufficientTimestampedWindowsForIQR:
        "Fewer than four timestamped model outputs; temporal IQR withheld"
      case .unknownAggregationWindowAlignment:
        "Nearby timestamps do not establish matching Eight aggregation windows"
      case .missingRespiratoryModel:
        "No respiratory model output; only fixed scenarios are available"
      case .ambiguousSeries:
        "At least one duplicate same-name series was rejected"
      case .contextualFieldsNotCalibrated:
        "Context fields are inventoried but not assigned invented effects"
      }
    }

    static func formatMilliseconds(_ value: Double?) -> String {
      value.map { "\(formatNumber($0)) ms" } ?? "Unavailable"
    }

    static func formatUnclassified(_ value: Double?) -> String {
      value.map { "\(formatNumber($0)) (unclassified)" } ?? "Unavailable"
    }

    static func formatRange(_ lower: Double?, _ upper: Double?) -> String {
      guard let lower, let upper else { return "Unavailable" }
      return "\(formatNumber(lower))–\(formatNumber(upper)) ms"
    }

    static func formatNumber(_ value: Double) -> String {
      String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
  }
#endif
