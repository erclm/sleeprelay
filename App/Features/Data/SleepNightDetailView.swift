import SleepRelayCore
import SwiftUI

struct SleepNightDetailView: View {
  let night: EightSleepNight
  let healthModel: HealthCoverageModel
  @State private var healthSheet: RestingHeartRateSheetDestination?
  @State private var pendingHealthAction: PendingRestingHeartRateAction?

  var body: some View {
    List {
      Section("Night") {
        MetricRow("Date", value: night.day)
        optionalMetric("Score", value: night.score, suffix: "")
        if let duration = night.sleepDurationSeconds {
          MetricRow("Sleep duration", value: durationText(duration))
        }
        MetricRow("Processing", value: night.isProcessing ? "Yes" : "No")
      }

      Section("Eight Sleep metrics") {
        optionalMetric(
          "Eight HR average field", value: night.averageHeartRateBPM, suffix: " bpm")
        optionalMetric(
          "Eight reported RHR", value: night.discoveredRestingHeartRateBPM, suffix: " bpm")
        optionalMetric("Eight HRV (RMSSD)", value: night.reportedHRVMilliseconds, suffix: " ms")
        optionalMetric(
          "Nightly respiratory rate", value: night.averageRespiratoryRate, suffix: " /min")
        optionalMetric("Tosses and turns", value: night.tossAndTurns, suffix: "")
      }

      RestingHeartRateSyncSection(
        night: night,
        model: healthModel,
        presentReview: { healthSheet = $0 }
      )

      Section {
        Label(
          "Only Eight's reported RHR can write to Apple Health. All other metrics remain read-only, including HRV.",
          systemImage: "hand.raised"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Sleep stages") {
        optionalDuration("Light", seconds: night.lightSleepSeconds)
        optionalDuration("Deep", seconds: night.deepSleepSeconds)
        optionalDuration("REM", seconds: night.remSleepSeconds)
      }
    }
    .navigationTitle(night.day)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $healthSheet, onDismiss: performPendingHealthAction) { destination in
      switch destination {
      case .write(let candidate, let decision):
        RestingHeartRateWriteReview(
          candidate: candidate,
          decision: decision
        ) {
          pendingHealthAction = .write(allowAdditionalSource: decision.hasOtherSources)
          healthSheet = nil
        }
      case .delete(let candidate):
        RestingHeartRateDeleteReview(candidate: candidate) {
          pendingHealthAction = .delete
          healthSheet = nil
        }
      }
    }
  }

  private func performPendingHealthAction() {
    guard let action = pendingHealthAction else { return }
    pendingHealthAction = nil

    // HealthKit presents its own authorization UI. Start it only after SwiftUI has
    // completed dismissing our review sheet so the two modal transitions never overlap.
    Task { @MainActor in
      await Task.yield()
      switch action {
      case .write(let allowAdditionalSource):
        await healthModel.writeRestingHeartRate(
          for: night,
          allowAdditionalSource: allowAdditionalSource
        )
      case .delete:
        await healthModel.deleteRestingHeartRate(for: night)
      }
    }
  }

  @ViewBuilder
  private func optionalMetric(_ title: String, value: Double?, suffix: String) -> some View {
    if let value {
      MetricRow(
        title,
        value: value.formatted(.number.precision(.fractionLength(0...2))) + suffix
      )
    } else {
      MetricRow(title, value: "Not present")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func optionalDuration(_ title: String, seconds: Double?) -> some View {
    if let seconds {
      MetricRow(title, value: durationText(seconds))
    } else {
      MetricRow(title, value: "Not present")
        .foregroundStyle(.secondary)
    }
  }
}

private enum PendingRestingHeartRateAction {
  case write(allowAdditionalSource: Bool)
  case delete
}

private struct MetricRow: View {
  let title: String
  let value: String

  init(_ title: String, value: String) {
    self.title = title
    self.value = value
  }

  var body: some View {
    LabeledContent(title, value: value)
  }
}

#Preview {
  NavigationStack {
    SleepNightDetailView(
      night: FixtureEightSleepProvider.snapshot.nights[0],
      healthModel: .preview
    )
  }
}
