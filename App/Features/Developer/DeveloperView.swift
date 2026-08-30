#if INTERNAL_TOOLS
  import CoreFoundation
  import Foundation
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
                  Text("Copy-safe payload shapes, relationship audit, RHR lab, and probes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        Section {
          Label(
            "Payload structure and relationship reports are sanitized. All Developer diagnostics are read-only.",
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var officialEightRHR = ""
    @State private var copiedStructureReport: String?
    @State private var structureCopyCount = 0
    @State private var copiedRelationshipReport: String?
    @State private var relationshipCopyCount = 0
    @State private var livePiezoProbeState: LivePiezoProbeViewState = .idle
    @State private var livePiezoProbeTask: Task<Void, Never>?
    @State private var livePiezoProbeGeneration = 0
    @State private var livePiezoCopyCount = 0

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

    private var relationshipReport: String {
      EightSleepSeriesRelationshipReport.sanitizedReport(for: night)
    }

    private var seriesRelationships: [EightSleepSeriesRelationship] {
      night.intervalProbe?.seriesRelationships ?? []
    }

    private var nightlyHRVConsistency: [EightSleepNightlyHRVConsistency] {
      night.intervalProbe?.nightlyHRVConsistency ?? []
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

    private var relationshipAuditStatus: String {
      if let probe = night.intervalProbe {
        switch probe.status {
        case .available:
          return probe.seriesRelationships.isEmpty
            ? "Not captured in this refresh"
            : "Available"
        case .unavailable:
          return probe.status.label
        }
      }
      return night.latestSessionID == nil
        ? "Not requested: no session reference"
        : "Not included in this refresh"
    }

    private var livePiezoSummary: LivePiezoProbeSummary? {
      guard case .complete(let summary) = livePiezoProbeState else { return nil }
      return summary
    }

    private var livePiezoStatusLabel: String {
      switch livePiezoProbeState {
      case .idle: "Not run"
      case .running: "Running in foreground"
      case .complete: "Complete"
      case .cancelled: "Cancelled"
      case .failed: "Failed"
      }
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

        Section("Series relationship audit") {
          LabeledContent("Status", value: relationshipAuditStatus)

          if seriesRelationships.isEmpty {
            Text(
              "No relationship summary was retained. Pull to refresh here; background refresh intentionally skips this audit."
            )
            .foregroundStyle(.secondary)
          } else {
            Button {
              UIPasteboard.general.string = relationshipReport
              copiedRelationshipReport = relationshipReport
              relationshipCopyCount += 1
              AccessibilityNotification.Announcement("Sanitized relationship audit copied").post()
            } label: {
              Label(
                copiedRelationshipReport == relationshipReport
                  ? "Relationship audit copied"
                  : "Copy relationship audit",
                systemImage: copiedRelationshipReport == relationshipReport
                  ? "checkmark"
                  : "doc.on.doc"
              )
            }
            .accessibilityIdentifier("developer.seriesRelationship.copy")
            .accessibilityHint(
              "Copies fixed comparison labels, counts, and categorical relationships without timestamps or measurements."
            )
            .sensoryFeedback(.success, trigger: relationshipCopyCount)

            ShareLink(
              item: relationshipReport,
              subject: Text("Sleep Relay sanitized series relationship audit"),
              message: Text("Value-free Eight Sleep series comparison")
            ) {
              Label("Share relationship audit", systemImage: "square.and.arrow.up")
            }

            ForEach(seriesRelationships) { relationship in
              VStack(alignment: .leading, spacing: 5) {
                Text(relationship.comparison.label)
                  .font(.headline)
                Text(EightSleepSeriesRelationshipReport.summaryDescription(relationship))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 2)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel(relationship.comparison.label)
              .accessibilityValue(
                EightSleepSeriesRelationshipReport.summaryDescription(relationship)
              )
            }

            LabeledContent(
              "HRV algorithm versions",
              value: night.intervalProbe?.algorithmVersionRelationship.label ?? "not captured"
            )

            if !nightlyHRVConsistency.isEmpty {
              DisclosureGroup("Nightly HRV consistency checks") {
                ForEach(nightlyHRVConsistency) { consistency in
                  VStack(alignment: .leading, spacing: 5) {
                    Text(consistency.series.label)
                      .font(.headline)
                    Text(
                      EightSleepSeriesRelationshipReport.nightlySummaryDescription(consistency)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  .padding(.vertical, 2)
                }
              }
            }

            Text(
              "Left and right follow each title's order. Simple aggregate matches are only consistent on this one night; they do not identify Eight's formula. The fixed-schema report retains no raw timestamps or measurements. Counts can approximate recording coverage. Trends and intervals are sequential requests, so differences can also reflect reprocessing."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        }

        Section("Live Pod piezo probe") {
          LabeledContent("Status", value: livePiezoStatusLabel)

          if case .running = livePiezoProbeState {
            ProgressView("Authenticating, resolving this night's Pod, and reading live events…")

            Button("Cancel probe", role: .cancel) {
              cancelLivePiezoProbe()
            }
          } else {
            Button {
              startLivePiezoProbe()
            } label: {
              Label("Run 15-second probe", systemImage: "waveform.path.ecg")
            }
            .accessibilityIdentifier("developer.livePiezo.run")
          }

          if let summary = livePiezoSummary {
            LabeledContent("Piezo events", value: "\(summary.piezoEventCount)")
            LabeledContent("Sample elements", value: "\(summary.totalSampleElementCount)")
            LabeledContent("Stream stopped", value: summary.stopReason.label)

            Button {
              UIPasteboard.general.string = summary.sanitizedReport
              livePiezoCopyCount += 1
              AccessibilityNotification.Announcement("Sanitized live piezo report copied").post()
            } label: {
              Label("Copy sanitized probe report", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("developer.livePiezo.copy")
            .accessibilityHint(
              "Copies aggregate counts and timing relationships without sensor values, timestamps, or identifiers."
            )
            .sensoryFeedback(.success, trigger: livePiezoCopyCount)

            ShareLink(
              item: summary.sanitizedReport,
              subject: Text("Sleep Relay sanitized live piezo probe"),
              message: Text("Aggregate-only Eight Sleep live sensor diagnostic")
            ) {
              Label("Share sanitized probe report", systemImage: "square.and.arrow.up")
            }
          }

          if case .failed(let message) = livePiezoProbeState {
            Text(message)
              .foregroundStyle(.red)
          }

          Text(
            "Keep the Pod awake, online, and unoccupied enough to avoid large motion. This makes one read-only foreground request to Eight's private live stream after resolving the Pod from this sleep day. It never starts a Pod mode, runs in the background, saves raw samples, or writes Apple Health."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)

          Text(
            "A successful stream only proves that sample blocks are accessible. It does not prove their sample rate, waveform meaning, beat accuracy, or fitness for calculating Apple Health SDNN."
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
      .onChange(of: relationshipReport) { _, _ in
        copiedRelationshipReport = nil
      }
      .onDisappear {
        if case .running = livePiezoProbeState {
          cancelLivePiezoProbe()
        }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase != .active else { return }
        if case .running = livePiezoProbeState {
          cancelLivePiezoProbe()
        }
      }
    }

    private func startLivePiezoProbe() {
      livePiezoProbeTask?.cancel()
      livePiezoProbeGeneration += 1
      let generation = livePiezoProbeGeneration
      livePiezoProbeState = .running
      livePiezoProbeTask = Task { @MainActor in
        defer {
          if livePiezoProbeGeneration == generation {
            livePiezoProbeTask = nil
          }
        }
        do {
          let summary = try await model.probeLivePiezo(for: night)
          try Task.checkCancellation()
          guard livePiezoProbeGeneration == generation else { return }
          livePiezoProbeState = .complete(summary)
        } catch is CancellationError {
          if livePiezoProbeGeneration == generation {
            livePiezoProbeState = .cancelled
          }
        } catch {
          guard livePiezoProbeGeneration == generation else { return }
          livePiezoProbeState = Task.isCancelled
            ? .cancelled
            : .failed(LivePiezoProbeError.safeMessage(for: error))
        }
      }
    }

    private func cancelLivePiezoProbe() {
      livePiezoProbeGeneration += 1
      livePiezoProbeTask?.cancel()
      livePiezoProbeTask = nil
      livePiezoProbeState = .cancelled
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

  private enum LivePiezoProbeViewState {
    case idle
    case running
    case complete(LivePiezoProbeSummary)
    case cancelled
    case failed(String)
  }

  enum LivePiezoProbeStopReason: String, Equatable, Sendable {
    case durationReached
    case serverClosed
    case safetyLimit

    var label: String {
      switch self {
      case .durationReached: "15-second limit reached"
      case .serverClosed: "Server closed the stream"
      case .safetyLimit: "Local event safety limit reached"
      }
    }
  }

  enum LivePiezoContentTypeCategory: String, Equatable, Sendable {
    case eventStream
    case json
    case missing
    case other

    var label: String {
      switch self {
      case .eventStream: "text/event-stream"
      case .json: "JSON"
      case .missing: "missing"
      case .other: "other"
      }
    }

    static func classify(_ value: String?) -> LivePiezoContentTypeCategory {
      guard let normalized = value?.lowercased(), !normalized.isEmpty else {
        return .missing
      }
      if normalized.contains("text/event-stream") { return .eventStream }
      if normalized.contains("json") { return .json }
      return .other
    }
  }

  struct LivePiezoProbeSummary: Equatable, Sendable {
    let stopReason: LivePiezoProbeStopReason
    let contentTypeCategory: LivePiezoContentTypeCategory
    let nonemptyLineCount: Int
    let jsonCandidateLineCount: Int
    let sensorEventCount: Int
    let piezoEventCount: Int
    let otherSensorEventCount: Int
    let malformedLineCount: Int
    let oversizedLineCount: Int
    let malformedPiezoEventCount: Int
    let oversizedSampleEventCount: Int
    let totalSampleElementCount: Int
    let minimumSamplesPerEvent: Int?
    let medianSamplesPerEvent: Double?
    let maximumSamplesPerEvent: Int?
    let nonfiniteSampleEventCount: Int
    let invalidSampleEventCount: Int
    let constantSampleEventCount: Int
    let timestampObservationCount: Int
    let missingOrInvalidTimestampCount: Int
    let positiveTimestampGapCount: Int
    let nonpositiveTimestampGapCount: Int
    let medianTimestampGapMilliseconds: Double?
    let timestampSpanSeconds: Double?
    let approximateSampleElementsPerSecond: Double?

    var sanitizedReport: String {
      """
      Sleep Relay live piezo probe - sanitized
      Format: live-piezo-probe-v1
      Scope: one bounded foreground connection to the private Eight Sleep live sensor endpoint
      Contains: transport categories, fixed event and sample counts, and relative timing aggregates
      Excludes: sleep day, identifiers, credentials, tokens, URLs, response text, absolute timestamps, and raw sensor values

      Status: Available
      Stop reason: \(stopReason.label)

      Transport
      - HTTP category: 2xx success
      - Content type category: \(contentTypeCategory.label)

      Stream parsing
      - Nonempty lines: \(nonemptyLineCount)
      - JSON candidate lines: \(jsonCandidateLineCount)
      - Decoded sensor events: \(sensorEventCount)
      - Piezo events: \(piezoEventCount)
      - Other sensor events: \(otherSensorEventCount)
      - Malformed candidate lines: \(malformedLineCount)
      - Lines rejected by the one-megabyte limit: \(oversizedLineCount)
      - Piezo events without a sample array: \(malformedPiezoEventCount)
      - Piezo events rejected by the per-event sample limit: \(oversizedSampleEventCount)

      Piezo sample blocks
      - Total sample elements: \(totalSampleElementCount)
      - Samples per event minimum: \(integerDescription(minimumSamplesPerEvent))
      - Samples per event median: \(decimalDescription(medianSamplesPerEvent, places: 1))
      - Samples per event maximum: \(integerDescription(maximumSamplesPerEvent))
      - Events containing a nonfinite sample: \(nonfiniteSampleEventCount)
      - Events containing an invalid sample value: \(invalidSampleEventCount)
      - Constant events: \(constantSampleEventCount)

      Relative event timing
      - Parsed piezo timestamps: \(timestampObservationCount)
      - Missing or invalid piezo timestamps: \(missingOrInvalidTimestampCount)
      - Positive sequential gaps: \(positiveTimestampGapCount)
      - Nonpositive sequential gaps: \(nonpositiveTimestampGapCount)
      - Median positive timestamp gap: \(decimalDescription(medianTimestampGapMilliseconds, places: 3)) ms
      - Timestamp span: \(decimalDescription(timestampSpanSeconds, places: 3)) sec
      - Approximate sample-element throughput: \(decimalDescription(approximateSampleElementsPerSecond, places: 1)) elements/sec

      Interpretation
      A successful response establishes only that live sample blocks were accessible during this foreground run. Timestamp spacing and element throughput do not establish the sensor sample rate. This report cannot establish beat timing, an HRV formula, or Apple Health SDNN accuracy.

      Privacy check
      This report is produced from in-memory aggregates. Sleep Relay does not retain raw samples, absolute event timestamps, device or user identifiers, credentials, access tokens, request URLs, or response bodies.
      """
    }

    private func integerDescription(_ value: Int?) -> String {
      value.map(String.init) ?? "unavailable"
    }

    private func decimalDescription(_ value: Double?, places: Int) -> String {
      guard let value, value.isFinite else { return "unavailable" }
      return String(
        format: "%.*f",
        locale: Locale(identifier: "en_US_POSIX"),
        places,
        value
      )
    }
  }

  enum LivePiezoProbeRequestStage: String, Sendable {
    case authentication = "authentication"
    case trends = "selected-day trends"
    case liveStream = "live stream"
  }

  enum LivePiezoProbeError: Error, LocalizedError, Sendable {
    case missingConfiguration
    case missingCredentials
    case invalidCredentials
    case invalidResponse(LivePiezoProbeRequestStage)
    case invalidPayload(LivePiezoProbeRequestStage)
    case selectedDayMissing
    case sessionMissing
    case deviceMissing
    case invalidDeviceReference
    case successfulLiveResponseMissing
    case unauthorized(LivePiezoProbeRequestStage)
    case forbidden(LivePiezoProbeRequestStage)
    case notFound(LivePiezoProbeRequestStage)
    case rateLimited(LivePiezoProbeRequestStage)
    case http(LivePiezoProbeRequestStage, Int)

    var errorDescription: String? {
      switch self {
      case .missingConfiguration:
        "The Nightly build is missing its local Eight Sleep client configuration."
      case .missingCredentials:
        "Connect Eight Sleep first. No active or saved login was available for this foreground probe."
      case .invalidCredentials:
        "Eight Sleep rejected the saved login while preparing the live probe. Reconnect the account and try again."
      case .invalidResponse(let stage):
        "Eight Sleep returned a non-HTTP response during \(stage.rawValue)."
      case .invalidPayload(let stage):
        "Eight Sleep returned an unexpected payload during \(stage.rawValue)."
      case .selectedDayMissing:
        "The fresh trends response did not include the selected sleep day. Refresh Eight data and try again."
      case .sessionMissing:
        "The selected sleep day did not contain a main or fallback session."
      case .deviceMissing:
        "The selected sleep session did not contain a Pod device reference."
      case .invalidDeviceReference:
        "Eight Sleep returned a device reference that was not safe to place in a request path."
      case .successfulLiveResponseMissing:
        "The live endpoint did not return a validated successful response before the connection deadline. Confirm the Pod is awake and online, then try again."
      case .unauthorized(let stage):
        "Eight Sleep rejected the temporary session during \(stage.rawValue) (HTTP 401). Reconnect and try again."
      case .forbidden(let stage):
        "Eight Sleep denied access during \(stage.rawValue) (HTTP 403). This account, Pod, or app version may not have live-stream access."
      case .notFound(let stage):
        "Eight Sleep reported that \(stage.rawValue) was unavailable (HTTP 404). The private endpoint or Pod generation may differ."
      case .rateLimited(let stage):
        "Eight Sleep rate limited \(stage.rawValue) (HTTP 429). Wait before trying again."
      case .http(let stage, let status):
        "Eight Sleep returned HTTP \(status) during \(stage.rawValue)."
      }
    }

    static func safeMessage(for error: Error) -> String {
      if let probeError = error as? LivePiezoProbeError {
        return probeError.errorDescription ?? "The live piezo probe failed."
      }
      if let urlError = error as? URLError {
        switch urlError.code {
        case .cancelled:
          return "The live piezo probe was cancelled."
        case .notConnectedToInternet:
          return "The iPhone is offline. Connect to the internet and try the live probe again."
        case .timedOut:
          return "The Eight Sleep request timed out. Confirm the Pod is awake and online, then try again."
        case .networkConnectionLost:
          return "The network connection ended before the live probe completed."
        default:
          return "A network error stopped the live piezo probe before a sanitized report could be produced."
        }
      }
      return "The live piezo probe failed before a sanitized report could be produced."
    }
  }

  struct LivePiezoProbeClient: Sendable {
    private struct AuthenticationPayload: Decodable, Sendable {
      let accessToken: String
      let userID: String

      enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userID = "userId"
      }
    }

    private struct TrendsPayload: Decodable, Sendable {
      let days: [TrendsDay]
    }

    private struct TrendsDay: Decodable, Sendable {
      let day: String?
      let mainSessionID: String?
      let sessions: [TrendsSession]?

      enum CodingKeys: String, CodingKey {
        case day
        case mainSessionID = "mainSessionId"
        case sessions
      }
    }

    private struct TrendsSession: Decodable, Sendable {
      let id: String?
      let device: TrendsDevice?
    }

    private struct TrendsDevice: Decodable, Sendable {
      let id: String?
    }

    private static let probeDurationSeconds = 15
    private static let requestInactivityTimeoutSeconds = 20
    private static let maximumLineByteCount = 1_048_576
    private let configuration: EightSleepAPIConfiguration
    private let credentials: EightSleepCredentials

    init(
      configuration: EightSleepAPIConfiguration,
      credentials: EightSleepCredentials
    ) {
      self.configuration = configuration
      self.credentials = credentials
    }

    func run(forSleepDay sleepDay: String) async throws -> LivePiezoProbeSummary {
      try Task.checkCancellation()
      let requestSession = makeSession(
        requestTimeout: 20,
        resourceTimeout: 30
      )
      defer { requestSession.invalidateAndCancel() }

      let authentication = try await authenticate(using: requestSession)
      try Task.checkCancellation()
      let deviceID = try await resolveDeviceID(
        forSleepDay: sleepDay,
        authentication: authentication,
        using: requestSession
      )
      try Task.checkCancellation()
      return try await readLiveStream(
        deviceID: deviceID,
        accessToken: authentication.accessToken
      )
    }

    private func authenticate(using session: URLSession) async throws -> AuthenticationPayload {
      var components = URLComponents()
      components.queryItems = [
        URLQueryItem(name: "grant_type", value: "password"),
        URLQueryItem(name: "username", value: credentials.email),
        URLQueryItem(name: "password", value: credentials.password),
        URLQueryItem(name: "client_id", value: configuration.clientID),
        URLQueryItem(name: "client_secret", value: configuration.clientSecret),
      ]

      var request = URLRequest(url: configuration.authURL)
      request.httpMethod = "POST"
      request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
      request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("SleepRelay-Nightly/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await session.data(for: request)
      let http = try requireHTTPResponse(response, stage: .authentication)
      switch http.statusCode {
      case 200..<300:
        break
      case 400, 401:
        throw LivePiezoProbeError.invalidCredentials
      case 403:
        throw LivePiezoProbeError.forbidden(.authentication)
      case 404:
        throw LivePiezoProbeError.notFound(.authentication)
      case 429:
        throw LivePiezoProbeError.rateLimited(.authentication)
      default:
        throw LivePiezoProbeError.http(.authentication, http.statusCode)
      }

      guard
        let payload = try? JSONDecoder().decode(AuthenticationPayload.self, from: data),
        !payload.accessToken.isEmpty,
        !payload.userID.isEmpty
      else {
        throw LivePiezoProbeError.invalidPayload(.authentication)
      }
      return payload
    }

    private func resolveDeviceID(
      forSleepDay sleepDay: String,
      authentication: AuthenticationPayload,
      using session: URLSession
    ) async throws -> String {
      let trendsURL = configuration.clientAPIBaseURL
        .appendingPathComponent("users")
        .appendingPathComponent(authentication.userID)
        .appendingPathComponent("trends")
      guard var components = URLComponents(url: trendsURL, resolvingAgainstBaseURL: false) else {
        throw LivePiezoProbeError.invalidResponse(.trends)
      }
      components.queryItems = [
        URLQueryItem(name: "tz", value: TimeZone.autoupdatingCurrent.identifier),
        URLQueryItem(name: "from", value: sleepDay),
        URLQueryItem(name: "to", value: sleepDay),
        URLQueryItem(name: "include-main", value: "false"),
        URLQueryItem(name: "include-all-sessions", value: "true"),
        URLQueryItem(name: "model-version", value: "v2"),
      ]
      guard let url = components.url else {
        throw LivePiezoProbeError.invalidResponse(.trends)
      }

      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue(
        "Bearer \(authentication.accessToken)",
        forHTTPHeaderField: "Authorization"
      )
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("SleepRelay-Nightly/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await session.data(for: request)
      let http = try requireHTTPResponse(response, stage: .trends)
      try requireSuccess(http.statusCode, stage: .trends)

      guard let payload = try? JSONDecoder().decode(TrendsPayload.self, from: data) else {
        throw LivePiezoProbeError.invalidPayload(.trends)
      }
      guard
        let selectedDay = payload.days.first(where: { $0.day == sleepDay })
          ?? (payload.days.count == 1 ? payload.days[0] : nil)
      else {
        throw LivePiezoProbeError.selectedDayMissing
      }

      let sessions = selectedDay.sessions ?? []
      guard !sessions.isEmpty else {
        throw LivePiezoProbeError.sessionMissing
      }
      let mainDeviceID = selectedDay.mainSessionID.flatMap { mainID in
        sessions.first(where: { $0.id == mainID })?.device?.id
      }.flatMap { id in
        id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : id
      }
      let fallbackDeviceID = sessions.reversed().lazy.compactMap(\.device?.id).first(where: {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
      guard let rawDeviceID = mainDeviceID ?? fallbackDeviceID else {
        throw LivePiezoProbeError.deviceMissing
      }
      let deviceID = rawDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !deviceID.isEmpty else {
        throw LivePiezoProbeError.deviceMissing
      }
      guard
        deviceID.utf8.count <= 512,
        !deviceID.contains("/"),
        !deviceID.contains("?"),
        !deviceID.contains("#")
      else {
        throw LivePiezoProbeError.invalidDeviceReference
      }
      return deviceID
    }

    private func readLiveStream(
      deviceID: String,
      accessToken: String
    ) async throws -> LivePiezoProbeSummary {
      let baseURL = URL(string: "https://app-api.8slp.net/v1/")!
      let url = baseURL
        .appendingPathComponent("devices")
        .appendingPathComponent(deviceID)
        .appendingPathComponent("live")

      var request = URLRequest(
        url: url,
        timeoutInterval: TimeInterval(Self.requestInactivityTimeoutSeconds)
      )
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
      request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
      request.setValue("SleepRelay-Nightly/0.1", forHTTPHeaderField: "User-Agent")
      let liveRequest = request

      let liveSession = makeSession(
        requestTimeout: TimeInterval(Self.requestInactivityTimeoutSeconds),
        resourceTimeout: 40
      )
      defer { liveSession.invalidateAndCancel() }
      let accumulator = LivePiezoProbeAccumulator()

      let stopReason = try await withTaskCancellationHandler {
        let (bytes, response) = try await liveSession.bytes(for: liveRequest)
        let http = try requireHTTPResponse(response, stage: .liveStream)
        try requireSuccess(http.statusCode, stage: .liveStream)
        await accumulator.recordSuccessfulResponse(
          contentType: http.value(forHTTPHeaderField: "Content-Type")
        )

        return try await withThrowingTaskGroup(
          of: LivePiezoProbeStopReason.self,
          returning: LivePiezoProbeStopReason.self
        ) { group in
          group.addTask {
            var lineBytes = Data()
            lineBytes.reserveCapacity(4_096)
            for try await byte in bytes {
              try Task.checkCancellation()
              if byte == 0x0A {
                let line = String(decoding: lineBytes, as: UTF8.self)
                lineBytes.removeAll(keepingCapacity: true)
                if await accumulator.ingest(line) {
                  return .safetyLimit
                }
              } else if lineBytes.count < Self.maximumLineByteCount {
                lineBytes.append(byte)
              } else {
                await accumulator.recordOversizedLine()
                return .safetyLimit
              }
            }

            if !lineBytes.isEmpty {
              let line = String(decoding: lineBytes, as: UTF8.self)
              if await accumulator.ingest(line) {
                return .safetyLimit
              }
            }
            return .serverClosed
          }
          group.addTask {
            try await Task.sleep(for: .seconds(Self.probeDurationSeconds))
            return .durationReached
          }
          defer { group.cancelAll() }
          guard let first = try await group.next() else {
            return .serverClosed
          }
          if first != .serverClosed {
            liveSession.invalidateAndCancel()
          }
          return first
        }
      } onCancel: {
        liveSession.invalidateAndCancel()
      }

      try Task.checkCancellation()
      return try await accumulator.makeSummary(stopReason: stopReason)
    }

    private func makeSession(
      requestTimeout: TimeInterval,
      resourceTimeout: TimeInterval
    ) -> URLSession {
      let sessionConfiguration = URLSessionConfiguration.ephemeral
      sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
      sessionConfiguration.urlCache = nil
      sessionConfiguration.timeoutIntervalForRequest = requestTimeout
      sessionConfiguration.timeoutIntervalForResource = resourceTimeout
      sessionConfiguration.waitsForConnectivity = false
      return URLSession(configuration: sessionConfiguration)
    }

    private func requireHTTPResponse(
      _ response: URLResponse,
      stage: LivePiezoProbeRequestStage
    ) throws -> HTTPURLResponse {
      guard let response = response as? HTTPURLResponse else {
        throw LivePiezoProbeError.invalidResponse(stage)
      }
      return response
    }

    private func requireSuccess(
      _ statusCode: Int,
      stage: LivePiezoProbeRequestStage
    ) throws {
      switch statusCode {
      case 200..<300:
        return
      case 401:
        throw LivePiezoProbeError.unauthorized(stage)
      case 403:
        throw LivePiezoProbeError.forbidden(stage)
      case 404:
        throw LivePiezoProbeError.notFound(stage)
      case 429:
        throw LivePiezoProbeError.rateLimited(stage)
      default:
        throw LivePiezoProbeError.http(stage, statusCode)
      }
    }
  }

  private actor LivePiezoProbeAccumulator {
    private static let maximumNonemptyLines = 10_000
    private static let maximumPiezoEvents = 5_000
    private static let maximumSampleElements = 5_000_000
    private static let maximumSampleElementsPerEvent = 100_000

    private var didReceiveSuccessfulResponse = false
    private var contentTypeCategory: LivePiezoContentTypeCategory = .missing
    private var nonemptyLineCount = 0
    private var jsonCandidateLineCount = 0
    private var sensorEventCount = 0
    private var piezoEventCount = 0
    private var otherSensorEventCount = 0
    private var malformedLineCount = 0
    private var oversizedLineCount = 0
    private var malformedPiezoEventCount = 0
    private var oversizedSampleEventCount = 0
    private var totalSampleElementCount = 0
    private var samplesPerEvent: [Int] = []
    private var nonfiniteSampleEventCount = 0
    private var invalidSampleEventCount = 0
    private var constantSampleEventCount = 0
    private var timestampObservationCount = 0
    private var missingOrInvalidTimestampCount = 0
    private var positiveTimestampGaps: [Double] = []
    private var nonpositiveTimestampGapCount = 0
    private var previousTimestamp: Date?
    private var minimumTimestamp: Date?
    private var maximumTimestamp: Date?
    private let fractionalTimestampFormatter: ISO8601DateFormatter
    private let standardTimestampFormatter: ISO8601DateFormatter

    init() {
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      fractionalTimestampFormatter = fractional

      let standard = ISO8601DateFormatter()
      standard.formatOptions = [.withInternetDateTime]
      standardTimestampFormatter = standard
    }

    func recordSuccessfulResponse(contentType: String?) {
      didReceiveSuccessfulResponse = true
      contentTypeCategory = .classify(contentType)
    }

    func recordOversizedLine() {
      nonemptyLineCount += 1
      oversizedLineCount += 1
    }

    /// Returns true when local aggregate limits have been reached.
    func ingest(_ rawLine: String) -> Bool {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { return reachedSafetyLimit }
      nonemptyLineCount += 1

      let jsonText: Substring
      if line.first == "{" {
        jsonText = line[...]
      } else if line.hasPrefix("data:") {
        let payload = line.dropFirst(5).drop(while: { $0.isWhitespace })
        guard payload.first == "{" else { return reachedSafetyLimit }
        jsonText = payload
      } else {
        return reachedSafetyLimit
      }

      jsonCandidateLineCount += 1
      guard
        let data = String(jsonText).data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let event = object as? [String: Any],
        let rawType = event["type"] as? String,
        !rawType.isEmpty
      else {
        malformedLineCount += 1
        return reachedSafetyLimit
      }

      sensorEventCount += 1
      guard rawType.caseInsensitiveCompare("PIEZO") == .orderedSame else {
        otherSensorEventCount += 1
        return reachedSafetyLimit
      }
      piezoEventCount += 1

      guard let samples = event["samples"] as? [Any] else {
        malformedPiezoEventCount += 1
        recordTimestamp(event["timestamp"])
        return reachedSafetyLimit
      }

      totalSampleElementCount += samples.count
      samplesPerEvent.append(samples.count)
      guard samples.count <= Self.maximumSampleElementsPerEvent else {
        oversizedSampleEventCount += 1
        recordTimestamp(event["timestamp"])
        return true
      }
      var finiteMinimum: Double?
      var finiteMaximum: Double?
      var finiteCount = 0
      var containsNonfinite = false
      var containsInvalid = false

      for sample in samples {
        let number: Double?
        if let value = sample as? NSNumber {
          if CFGetTypeID(value) == CFBooleanGetTypeID() {
            number = nil
            containsInvalid = true
          } else {
            number = value.doubleValue
          }
        } else if let text = sample as? String, let value = Double(text) {
          number = value
        } else {
          number = nil
          containsInvalid = true
        }

        guard let number else { continue }
        guard number.isFinite else {
          containsNonfinite = true
          continue
        }
        finiteCount += 1
        finiteMinimum = min(finiteMinimum ?? number, number)
        finiteMaximum = max(finiteMaximum ?? number, number)
      }

      if containsNonfinite { nonfiniteSampleEventCount += 1 }
      if containsInvalid { invalidSampleEventCount += 1 }
      if finiteCount >= 2,
        finiteCount == samples.count,
        finiteMinimum == finiteMaximum
      {
        constantSampleEventCount += 1
      }

      recordTimestamp(event["timestamp"])
      return reachedSafetyLimit
    }

    func makeSummary(
      stopReason: LivePiezoProbeStopReason
    ) throws -> LivePiezoProbeSummary {
      guard didReceiveSuccessfulResponse else {
        throw LivePiezoProbeError.successfulLiveResponseMissing
      }
      let sortedSampleCounts = samplesPerEvent.sorted()
      let sortedGaps = positiveTimestampGaps.sorted()
      let timestampSpan = timestampSpanSeconds
      let throughput: Double?
      if let timestampSpan, timestampSpan > 0 {
        throughput = Double(totalSampleElementCount) / timestampSpan
      } else {
        throughput = nil
      }

      let summary = LivePiezoProbeSummary(
        stopReason: stopReason,
        contentTypeCategory: contentTypeCategory,
        nonemptyLineCount: nonemptyLineCount,
        jsonCandidateLineCount: jsonCandidateLineCount,
        sensorEventCount: sensorEventCount,
        piezoEventCount: piezoEventCount,
        otherSensorEventCount: otherSensorEventCount,
        malformedLineCount: malformedLineCount,
        oversizedLineCount: oversizedLineCount,
        malformedPiezoEventCount: malformedPiezoEventCount,
        oversizedSampleEventCount: oversizedSampleEventCount,
        totalSampleElementCount: totalSampleElementCount,
        minimumSamplesPerEvent: sortedSampleCounts.first,
        medianSamplesPerEvent: median(sortedSampleCounts.map(Double.init)),
        maximumSamplesPerEvent: sortedSampleCounts.last,
        nonfiniteSampleEventCount: nonfiniteSampleEventCount,
        invalidSampleEventCount: invalidSampleEventCount,
        constantSampleEventCount: constantSampleEventCount,
        timestampObservationCount: timestampObservationCount,
        missingOrInvalidTimestampCount: missingOrInvalidTimestampCount,
        positiveTimestampGapCount: positiveTimestampGaps.count,
        nonpositiveTimestampGapCount: nonpositiveTimestampGapCount,
        medianTimestampGapMilliseconds: median(sortedGaps).map { $0 * 1_000 },
        timestampSpanSeconds: timestampSpan,
        approximateSampleElementsPerSecond: throughput
      )

      // Drop the only absolute timestamps before returning the aggregate report.
      previousTimestamp = nil
      minimumTimestamp = nil
      maximumTimestamp = nil
      return summary
    }

    private var reachedSafetyLimit: Bool {
      nonemptyLineCount >= Self.maximumNonemptyLines
        || piezoEventCount >= Self.maximumPiezoEvents
        || totalSampleElementCount >= Self.maximumSampleElements
    }

    private var timestampSpanSeconds: Double? {
      guard let minimumTimestamp, let maximumTimestamp else { return nil }
      let span = maximumTimestamp.timeIntervalSince(minimumTimestamp)
      return span.isFinite && span >= 0 ? span : nil
    }

    private func recordTimestamp(_ rawValue: Any?) {
      guard let timestamp = parseTimestamp(rawValue) else {
        missingOrInvalidTimestampCount += 1
        return
      }
      timestampObservationCount += 1
      if let previousTimestamp {
        let gap = timestamp.timeIntervalSince(previousTimestamp)
        if gap.isFinite, gap > 0 {
          positiveTimestampGaps.append(gap)
        } else {
          nonpositiveTimestampGapCount += 1
        }
      }
      previousTimestamp = timestamp
      minimumTimestamp = min(minimumTimestamp ?? timestamp, timestamp)
      maximumTimestamp = max(maximumTimestamp ?? timestamp, timestamp)
    }

    private func parseTimestamp(_ rawValue: Any?) -> Date? {
      if let text = rawValue as? String {
        if let date = fractionalTimestampFormatter.date(from: text)
          ?? standardTimestampFormatter.date(from: text)
        {
          return date
        }
        if let numeric = Double(text) {
          return dateFromNumericTimestamp(numeric)
        }
        return nil
      }
      if let value = rawValue as? NSNumber,
        CFGetTypeID(value) != CFBooleanGetTypeID()
      {
        return dateFromNumericTimestamp(value.doubleValue)
      }
      return nil
    }

    private func dateFromNumericTimestamp(_ value: Double) -> Date? {
      guard value.isFinite else { return nil }
      let seconds = abs(value) >= 1_000_000_000_000 ? value / 1_000 : value
      guard seconds.isFinite else { return nil }
      return Date(timeIntervalSince1970: seconds)
    }

    private func median(_ sortedValues: [Double]) -> Double? {
      guard !sortedValues.isEmpty else { return nil }
      let middle = sortedValues.count / 2
      if sortedValues.count.isMultiple(of: 2) {
        return (sortedValues[middle - 1] + sortedValues[middle]) / 2
      }
      return sortedValues[middle]
    }
  }

  enum LivePiezoProbeValidation {
    static func run() async -> Bool {
      let unvalidatedAccumulator = LivePiezoProbeAccumulator()
      do {
        _ = try await unvalidatedAccumulator.makeSummary(stopReason: .durationReached)
        return false
      } catch LivePiezoProbeError.successfulLiveResponseMissing {
        // A timeout before validated HTTP response headers must never produce
        // a report that claims the endpoint was available.
      } catch {
        return false
      }

      let accumulator = LivePiezoProbeAccumulator()
      await accumulator.recordSuccessfulResponse(
        contentType: "text/event-stream; charset=utf-8"
      )
      let firstLine =
        #"{"type":"PIEZO","samples":[0.5,"NaN",true,0.25],"timestamp":"2026-08-30T12:00:00.000Z"}"#
      let secondLine =
        #"data: {"type":"piezo","samples":[2,2,2],"timestamp":"2026-08-30T12:00:00.020Z"}"#
      let otherLine = #"{"type":"BUTTON","timestamp":"2026-08-30T12:00:00.030Z"}"#
      let malformedLine = #"{"type":"#

      guard await accumulator.ingest(firstLine) == false else { return false }
      guard await accumulator.ingest(secondLine) == false else { return false }
      guard await accumulator.ingest(otherLine) == false else { return false }
      guard await accumulator.ingest(malformedLine) == false else { return false }

      let summary: LivePiezoProbeSummary
      do {
        summary = try await accumulator.makeSummary(stopReason: .serverClosed)
      } catch {
        return false
      }
      guard
        summary.contentTypeCategory == .eventStream,
        summary.nonemptyLineCount == 4,
        summary.jsonCandidateLineCount == 4,
        summary.sensorEventCount == 3,
        summary.piezoEventCount == 2,
        summary.otherSensorEventCount == 1,
        summary.malformedLineCount == 1,
        summary.oversizedLineCount == 0,
        summary.totalSampleElementCount == 7,
        summary.minimumSamplesPerEvent == 3,
        summary.medianSamplesPerEvent == 3.5,
        summary.maximumSamplesPerEvent == 4,
        summary.nonfiniteSampleEventCount == 1,
        summary.invalidSampleEventCount == 1,
        summary.constantSampleEventCount == 1,
        summary.timestampObservationCount == 2,
        summary.positiveTimestampGapCount == 1,
        summary.nonpositiveTimestampGapCount == 0,
        abs((summary.medianTimestampGapMilliseconds ?? 0) - 20) < 0.01,
        abs((summary.timestampSpanSeconds ?? 0) - 0.02) < 0.0001,
        summary.sanitizedReport.contains("Format: live-piezo-probe-v1"),
        !summary.sanitizedReport.contains("2026-08-30T12:00:00"),
        !summary.sanitizedReport.contains(firstLine)
      else {
        return false
      }

      let oversizedAccumulator = LivePiezoProbeAccumulator()
      await oversizedAccumulator.recordSuccessfulResponse(contentType: nil)
      await oversizedAccumulator.recordOversizedLine()
      guard
        let oversizedSummary = try? await oversizedAccumulator.makeSummary(
          stopReason: .safetyLimit
        )
      else {
        return false
      }
      return oversizedSummary.nonemptyLineCount == 1
        && oversizedSummary.oversizedLineCount == 1
        && oversizedSummary.piezoEventCount == 0
    }
  }

  #Preview {
    NavigationStack {
      DeveloperView(model: .preview)
    }
  }
#endif
