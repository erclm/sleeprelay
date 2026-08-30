import SleepRelayCore
import SwiftUI

struct SleepNightDetailView: View {
  let night: EightSleepNight
  let healthModel: HealthCoverageModel
  @State private var officialEightRHR = ""
  @State private var healthSheet: RestingHeartRateSheetDestination?
  @State private var pendingHealthAction: PendingRestingHeartRateAction?

  private var analysis: RestingHeartRateLabAnalysis {
    RestingHeartRateLab.analyze(night)
  }

  private var officialEightRHRValue: Double? {
    Double(officialEightRHR.replacingOccurrences(of: ",", with: "."))
  }

  private var sanitizedReport: String {
    RestingHeartRateLab.sanitizedReport(
      for: night,
      officialEightRestingHeartRateBPM: officialEightRHRValue
    )
  }

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

      Section("Candidate metrics") {
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

      Section("RHR Lab") {
        LabeledContent("Official Eight app RHR") {
          TextField("Optional", text: $officialEightRHR)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 100)
        }

        optionalMetric("Series minimum", value: analysis.minimumBPM, suffix: " bpm")
        optionalMetric("Series median", value: analysis.medianBPM, suffix: " bpm")
        optionalMetric(
          "Experimental 15-min low median",
          value: analysis.experimentalLowWindowMedianBPM,
          suffix: " bpm"
        )

        if let official = officialEightRHRValue,
          let candidate = analysis.experimentalLowWindowMedianBPM
        {
          optionalMetric("Candidate difference", value: candidate - official, suffix: " bpm")
        }

        Text(analysis.explanation)
          .font(.footnote)
          .foregroundStyle(.secondary)

        ShareLink(
          item: sanitizedReport,
          subject: Text("Sleep Relay RHR Lab — \(night.day)"),
          message: Text("Sanitized Sleep Relay metric report")
        ) {
          Label("Share sanitized report", systemImage: "square.and.arrow.up")
        }
      }

      Section {
        Label(
          "Only a confirmed RHR import can write to Apple Health. All other metrics remain read-only.",
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

      Section("Available API fields") {
        ForEach(night.availableFields, id: \.self) { field in
          Text(field)
            .font(.system(.body, design: .monospaced))
        }
      }

      Section("Matched metric paths") {
        let fields = night.metricFields + (night.intervalProbe?.metricFields ?? [])
        if fields.isEmpty {
          Text("No matched numeric metric paths were found.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
            LabeledContent {
              Text(field.value, format: .number.precision(.fractionLength(0...2)))
            } label: {
              Text(field.path)
                .font(.system(.caption, design: .monospaced))
            }
          }
        }
      }

      Section("Intervals endpoint probe") {
        if let probe = night.intervalProbe {
          LabeledContent("Status", value: probe.status.label)
          LabeledContent("Discovered field paths", value: "\(probe.fieldPaths.count)")

          if probe.series.isEmpty {
            Text("No matched numeric series were summarized.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(probe.series) { series in
              VStack(alignment: .leading, spacing: 4) {
                Text(series.path)
                  .font(.system(.caption, design: .monospaced))
                Text(
                  "\(series.sampleCount) values · min \(format(series.minimum)) · median \(format(series.median)) · max \(format(series.maximum))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
            }
          }
        } else {
          Text("Not requested because this night did not expose a session ID.")
            .foregroundStyle(.secondary)
        }
      }

      Section("Time series") {
        if night.timeSeries.isEmpty {
          Text("No series were embedded in the trends response.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(night.timeSeries) { series in
            VStack(alignment: .leading, spacing: 4) {
              Text(series.name)
                .font(.headline)
              Text("\(series.sampleCount) samples")
                .font(.caption)
                .foregroundStyle(.secondary)
              if let latest = series.latestNumericValue {
                Text(
                  "Latest numeric value: \(latest, format: .number.precision(.fractionLength(0 ... 2)))"
                )
                .font(.caption)
              }
            }
            .padding(.vertical, 2)
          }
        }
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

  private func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
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
