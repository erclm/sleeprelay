#if INTERNAL_TOOLS
  import SleepRelayCore
  import SwiftUI
  import UIKit

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
                DeveloperNightDetailView(model: model, initialNight: night)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(night.day)
                    .font(.headline)
                  Text("Copy-safe payload shapes, RHR lab, probes, and series summaries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        Section {
          Label(
            "Payload structure reports are sanitized. All Developer diagnostics are read-only.",
            systemImage: "hand.raised"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Developer")
      .refreshable {
        await model.refresh()
      }
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
    let model: AppModel
    let initialNight: EightSleepNight
    @State private var officialEightRHR = ""
    @State private var copiedStructureReport: String?
    @State private var structureCopyCount = 0

    private var night: EightSleepNight {
      model.nights.first(where: { $0.id == initialNight.id })
        ?? model.nights.first(where: { $0.day == initialNight.day })
        ?? initialNight
    }

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

    private var structureReport: String {
      EightSleepDiagnosticReport.sanitizedStructureReport(for: night)
    }

    private var intervalStructureStatus: String {
      if let probe = night.intervalProbe {
        switch probe.status {
        case .available:
          return probe.pathSummaries.isEmpty ? "Not captured in this refresh" : "Available"
        case .unavailable:
          return probe.status.label
        }
      }
      return night.latestSessionID == nil
        ? "Not requested: no session reference"
        : "Not included in this refresh"
    }

    private var trendsStructureStatus: String {
      night.trendsPathSummaries.isEmpty ? "Not captured in this refresh" : "Available"
    }

    var body: some View {
      List {
        Section("Value-free payload audit") {
          Button {
            UIPasteboard.general.string = structureReport
            copiedStructureReport = structureReport
            structureCopyCount += 1
            AccessibilityNotification.Announcement("Sanitized structure copied").post()
          } label: {
            Label(
              copiedStructureReport == structureReport
                ? "Sanitized structure copied"
                : "Copy sanitized structure",
              systemImage: copiedStructureReport == structureReport ? "checkmark" : "doc.on.doc"
            )
          }
          .accessibilityIdentifier("developer.payloadStructure.copy")
          .accessibilityHint(
            "Copies field names, JSON kinds, counts, and broad relative cadence without primitive response values."
          )
          .sensoryFeedback(.success, trigger: structureCopyCount)

          ShareLink(
            item: structureReport,
            subject: Text("Sleep Relay sanitized payload structure"),
            message: Text("Structure-only Eight Sleep diagnostics")
          ) {
            Label("Share sanitized structure", systemImage: "square.and.arrow.up")
          }

          Text(
            "The copied report contains no primitive response values, night date, exact timestamps, exact cadence, raw samples, credentials, or response text. Recognized identifiers are redacted; inspect the remaining private-schema field names before sharing."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        PayloadStructureSection(
          title: "Trends payload structure",
          status: trendsStructureStatus,
          summaries: night.trendsPathSummaries
        )

        PayloadStructureSection(
          title: "Intervals payload structure",
          status: intervalStructureStatus,
          summaries: night.intervalProbe?.pathSummaries ?? []
        )

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
            Label(
              "Share RHR report (includes date and measurements)",
              systemImage: "square.and.arrow.up"
            )
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
            Text(intervalStructureStatus)
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
      .refreshable {
        await model.refresh()
      }
      .onChange(of: structureReport) { _, _ in
        copiedStructureReport = nil
      }
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

  private struct PayloadStructureSection: View {
    let title: String
    let status: String
    let summaries: [EightSleepProbePathSummary]

    var body: some View {
      Section(title) {
        LabeledContent("Status", value: status)
        LabeledContent("Sanitized paths", value: "\(summaries.count)")

        if summaries.isEmpty {
          Text(
            "No structural paths were retained. Pull to refresh here; background refresh intentionally skips this audit."
          )
            .foregroundStyle(.secondary)
        } else {
          NavigationLink {
            PayloadStructureListView(title: title, summaries: summaries)
          } label: {
            Label("Browse paths and shapes", systemImage: "list.bullet.rectangle")
          }
        }
      }
    }
  }

  private struct PayloadStructureListView: View {
    let title: String
    let summaries: [EightSleepProbePathSummary]

    var body: some View {
      List(summaries) { summary in
        VStack(alignment: .leading, spacing: 5) {
          Text(verbatim: summary.path)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
          Text(EightSleepDiagnosticReport.summaryDescription(summary))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .textSelection(.enabled)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  #Preview {
    NavigationStack {
      DeveloperView(model: .preview)
    }
  }
#endif
