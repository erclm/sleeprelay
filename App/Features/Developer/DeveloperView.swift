#if INTERNAL_TOOLS
  import SleepRelayCore
  import SwiftUI

  struct DeveloperView: View {
    let model: AppModel

    var body: some View {
      List {
        Section("Build") {
          LabeledContent("Channel", value: buildValue("SleepRelayBuildChannel"))
          LabeledContent("Version", value: buildValue("CFBundleShortVersionString"))
          LabeledContent("Build", value: buildValue("CFBundleVersion"))
          LabeledContent("Commit", value: shortCommit)
        }

        Section("Runtime") {
          LabeledContent(
            "Eight provider",
            value: model.isProviderConfigured ? "Configured" : "Missing"
          )
          LabeledContent("Connection", value: connectionLabel)
          LabeledContent("Loaded nights", value: "\(model.nights.count)")
          if case .connected(let lastUpdated) = model.connectionState {
            LabeledContent("Last refresh") {
              Text(lastUpdated, format: .dateTime.month().day().hour().minute().second())
            }
          }
        }

        Section("Night diagnostics") {
          if model.nights.isEmpty {
            Text("Connect Eight Sleep to inspect sanitized diagnostics.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.nights) { night in
              NavigationLink {
                DeveloperNightDetailView(night: night)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(night.day)
                    .font(.headline)
                  Text("RHR lab, API fields, probes, and time-series summaries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        Section {
          Label(
            "Diagnostics are sanitized and cannot write to Apple Health.",
            systemImage: "hand.raised"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Developer")
    }

    private var connectionLabel: String {
      switch model.connectionState {
      case .disconnected: "Disconnected"
      case .connecting: "Connecting"
      case .connected: "Connected"
      case .failed: "Failed"
      }
    }

    private var shortCommit: String {
      String(buildValue("SleepRelayGitCommit").prefix(12))
    }

    private func buildValue(_ key: String) -> String {
      guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
        return "Unknown"
      }
      let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.isEmpty || cleaned.contains("$(") ? "Unknown" : cleaned
    }
  }

  private struct DeveloperNightDetailView: View {
    let night: EightSleepNight
    @State private var officialEightRHR = ""

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
        Section("Decoded values") {
          optionalMetric("Average sleeping HR", value: night.averageHeartRateBPM, suffix: " bpm")
          optionalMetric(
            "Eight reported RHR",
            value: night.discoveredRestingHeartRateBPM,
            suffix: " bpm"
          )
          optionalMetric("Eight HRV (RMSSD)", value: night.reportedHRVMilliseconds, suffix: " ms")
          optionalMetric("Respiratory rate", value: night.averageRespiratoryRate, suffix: " /min")
        }

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
                    "Latest numeric value: \(latest, format: .number.precision(.fractionLength(0...2)))"
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
        LabeledContent(
          title,
          value: value.formatted(.number.precision(.fractionLength(0...2))) + suffix
        )
      } else {
        LabeledContent(title, value: "Not present")
          .foregroundStyle(.secondary)
      }
    }

    private func format(_ value: Double) -> String {
      value.formatted(.number.precision(.fractionLength(0...2)))
    }
  }

  #Preview {
    NavigationStack {
      DeveloperView(model: .preview)
    }
  }
#endif
