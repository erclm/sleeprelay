import SleepRelayCore
import SwiftUI

struct SleepNightDetailView: View {
  let night: EightSleepNight

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
        optionalMetric("Average sleeping HR", value: night.averageHeartRateBPM, suffix: " bpm")
        optionalMetric(
          "Explicit RHR field", value: night.explicitRestingHeartRateBPM, suffix: " bpm")
        optionalMetric("Eight HRV (RMSSD)", value: night.reportedHRVMilliseconds, suffix: " ms")
        optionalMetric("Respiratory rate", value: night.averageRespiratoryRate, suffix: " /min")
        optionalMetric("Tosses and turns", value: night.tossAndTurns, suffix: "")
      }

      Section {
        Label("Nothing on this screen is written to Apple Health.", systemImage: "hand.raised")
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

      Section("Time series") {
        if night.timeSeries.isEmpty {
          Text("No series were embedded in the trends response.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(night.timeSeries) { series in
            VStack(alignment: .leading, spacing: 4) {
              Text(series.name)
                .font(.headline)
              Text("\(series.sampleCount) samples · session \(series.sessionID)")
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
    SleepNightDetailView(night: FixtureEightSleepProvider.snapshot.nights[0])
  }
}
