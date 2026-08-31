#if INTERNAL_TOOLS
  import Foundation
  import SleepRelayCore
  import SwiftUI
  import UIKit

  struct SavedEightSDNNEstimationSection: View {
    let night: EightSleepNight

    @State private var copiedReport: String?
    @State private var copyCount = 0

    private var estimation: SavedEightSDNNEstimation {
      SavedEightSDNNEstimator.estimate(night)
    }

    var body: some View {
      Section("Saved-data SDNN estimation lab") {
        Label("Estimated—not measured SDNN", systemImage: "function")
          .font(.headline)

        switch estimation {
        case .unavailable(let reason):
          LabeledContent("Status", value: unavailableLabel(reason))
          Text(
            "The saved Eight data for this night does not contain the minimum inputs for the model. No live request or HealthKit write is attempted."
          )
          .foregroundStyle(.secondary)

        case .available(let estimate):
          availableContent(estimate)
        }

        Text(
          "This read-only lab uses only values already saved in the decoded Eight trends response. Its respiratory-sinusoid model assumes breathing dominates beat-to-beat variation; the displayed point is a saved-data proxy, not whole-night SDNN. Inputs are limited to RMSSD 1–200 ms, HR 20–250 bpm, and respiration 4–40/min; the model also requires a respiration/HR ratio between 0 and 0.5, a sine denominator above 0.1, and an output no greater than 500 ms. The assumption span is not a confidence interval, actual SDNN can fall outside it, and no result is written to Apple Health or sent to Bevel."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }

    @ViewBuilder
    private func availableContent(_ estimate: SavedEightSDNNHypothesisResult) -> some View {
      LabeledContent(
        "Status",
        value: estimate.medianModeledWindowProxyMilliseconds == nil
          ? "Fixed RMSSD scenarios only"
          : "Modeled proxy available"
      )
      LabeledContent(
        "Median modeled SDNN proxy",
        value: formatMilliseconds(estimate.medianModeledWindowProxyMilliseconds)
      )

      if let lower = estimate.modeledWindowIQRLowerMilliseconds,
        let upper = estimate.modeledWindowIQRUpperMilliseconds
      {
        LabeledContent(
          "Temporal proxy IQR (4+ windows)",
          value: "\(formatNumber(lower))–\(formatNumber(upper)) ms"
        )
      }

      LabeledContent(
        "Assumption span",
        value:
          "\(formatNumber(estimate.assumptionRangeLowerMilliseconds))–\(formatNumber(estimate.assumptionRangeUpperMilliseconds)) ms"
      )

      DisclosureGroup("Named assumption scenarios") {
        scenarioRow(
          "Uncorrelated intervals (ρ = 0)",
          value: estimate.uncorrelatedScenarioMilliseconds
        )
        scenarioRow(
          "Moderately correlated (ρ = 0.5)",
          value: estimate.moderateCorrelationScenarioMilliseconds
        )
        scenarioRow(
          "Highly correlated (ρ = 0.875)",
          value: estimate.highCorrelationScenarioMilliseconds
        )

        Text(
          "These are mathematical scenarios for the missing beat-order correlation—not lower and upper physiological bounds."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      DisclosureGroup("Saved Eight inputs") {
        LabeledContent(
          "RMSSD median used",
          value: "\(formatNumber(estimate.rmssdMedianMilliseconds)) ms"
        )
        LabeledContent(
          "Eight nightly current",
          value: formatMilliseconds(estimate.reportedNightlyRMSSDCurrentMilliseconds)
        )
        LabeledContent("Usable RMSSD observations", value: "\(estimate.rmssdObservationCount)")
        LabeledContent("Modeled observations", value: "\(estimate.modeledWindowCount)")
        LabeledContent(
          "Nearby saved HR matches",
          value: "\(estimate.nearbyHeartRateWindowCount)"
        )
        LabeledContent(
          "Nearby saved respiration matches",
          value: "\(estimate.nearbyRespiratoryRateWindowCount)"
        )
        if estimate.rejectedRMSSDTimestampGroupCount > 0 {
          LabeledContent(
            "Conflicting RMSSD timestamps rejected",
            value: "\(estimate.rejectedRMSSDTimestampGroupCount)"
          )
        }
        LabeledContent(
          "Opaque Eight hrv median",
          value: formatUnclassified(estimate.opaqueHRVMedian)
        )
        Text("The undocumented hrv series is displayed separately and never treated as SDNN.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      DisclosureGroup("Relevant saved-field ledger") {
        ForEach(estimate.featureCoverage, id: \.feature) { coverage in
          LabeledContent(featureLabel(coverage.feature)) {
            Text(featureCoverageLabel(coverage))
              .foregroundStyle(coverage.isAvailable ? .primary : .secondary)
          }
        }

        Text(
          "Only RMSSD, heart rate, and respiratory rate are used by the v0 formula. Other retained fields are inventoried but excluded until paired SDNN ground truth can calibrate them."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if !estimate.warnings.isEmpty {
        DisclosureGroup("Model warnings (\(estimate.warnings.count))") {
          ForEach(sortedWarnings(estimate.warnings), id: \.self) { warning in
            Label(
              SavedEightSDNNReport.warningLabel(warning),
              systemImage: "exclamationmark.triangle"
            )
              .font(.caption)
          }
        }
      }

      let report = SavedEightSDNNReport.make(for: night, estimate: estimate)
      Button {
        UIPasteboard.general.string = report
        copiedReport = report
        copyCount += 1
        AccessibilityNotification.Announcement("Saved-data SDNN report copied").post()
      } label: {
        Label(
          copiedReport == report
            ? "Estimation report copied"
            : "Copy report (includes date and measurements)",
          systemImage: copiedReport == report ? "checkmark" : "doc.on.doc"
        )
      }
      .accessibilityIdentifier("developer.savedSDNN.copy")
      .accessibilityHint(
        "Copies the night date, aggregate inputs, model estimates, and warnings without identifiers, exact timestamps, or raw samples."
      )
      .sensoryFeedback(.success, trigger: copyCount)

      ShareLink(
        item: report,
        subject: Text("Sleep Relay saved-data SDNN estimation"),
        message: Text("Experimental model report with measurements")
      ) {
        Label(
          "Share report (includes date and measurements)",
          systemImage: "square.and.arrow.up"
        )
      }
    }

    @ViewBuilder
    private func scenarioRow(_ title: String, value: Double) -> some View {
      LabeledContent(title, value: "\(formatNumber(value)) ms")
    }

    private func unavailableLabel(_ reason: SavedEightSDNNUnavailableReason) -> String {
      switch reason {
      case .processing: "Night still processing"
      case .missingSelectedSession: "No selected session"
      case .missingRMSSD: "No usable RMSSD"
      }
    }

    private func featureLabel(_ feature: SavedEightSDNNFeature) -> String {
      switch feature {
      case .rmssd: "RMSSD"
      case .heartRate: "Heart rate"
      case .respiratoryRate: "Respiratory rate"
      case .opaqueHRV: "Opaque hrv series"
      case .sleepStages: "Sleep-stage totals"
      case .sleepDuration: "Sleep duration"
      case .movement: "Movement / toss-and-turns"
      case .environmentalTemperature: "Bed / room temperature"
      case .shortAwakes: "Short awakes"
      case .nightlyScore: "Nightly score"
      case .restingHeartRate: "Resting heart rate"
      }
    }

    private func featureCoverageLabel(_ coverage: SavedEightSDNNFeatureCoverage) -> String {
      guard coverage.isAvailable else { return "Not available" }
      return coverage.isUsedByModel ? "Available · used" : "Available · context only"
    }

    private func sortedWarnings(
      _ warnings: Set<SavedEightSDNNWarning>
    ) -> [SavedEightSDNNWarning] {
      warnings.sorted {
        SavedEightSDNNReport.warningLabel($0) < SavedEightSDNNReport.warningLabel($1)
      }
    }

    private func formatMilliseconds(_ value: Double?) -> String {
      value.map { "\(formatNumber($0)) ms" } ?? "Unavailable"
    }

    private func formatUnclassified(_ value: Double?) -> String {
      value.map { "\(formatNumber($0)) (unclassified)" } ?? "Unavailable"
    }

    private func formatNumber(_ value: Double) -> String {
      String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
  }
#endif
