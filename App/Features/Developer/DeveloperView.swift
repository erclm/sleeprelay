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

    private var livePiezoResult: LivePiezoProbeResult? {
      guard case .complete(let result) = livePiezoProbeState else { return nil }
      return result
    }

    private var livePiezoSummary: LivePiezoProbeSummary? {
      livePiezoResult?.streamSummary
    }

    private var livePiezoStatusLabel: String {
      switch livePiezoProbeState {
      case .idle: "Not run"
      case .running: "Running in foreground"
      case .complete(let result): result.outcomeLabel
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
            ProgressView("Authenticating, resolving the household Pod, and reading live events…")

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

          if let result = livePiezoResult {
            LabeledContent("Identity source", value: result.preferredIdentitySource.label)
            LabeledContent("Generation category", value: result.preferredGeneration.label)
            LabeledContent("Household vs night ID", value: result.identityRelationship.label)
            LabeledContent("Live requests", value: "\(result.liveRequestCount)")

            if let summary = result.streamSummary {
              LabeledContent("Piezo events", value: "\(summary.piezoEventCount)")
              LabeledContent("Sample elements", value: "\(summary.totalSampleElementCount)")
              LabeledContent("Stream stopped", value: summary.stopReason.label)
            } else if let lastAttempt = result.attempts.last {
              LabeledContent("Live endpoint", value: lastAttempt.liveStatus.label)
            }

            Button {
              UIPasteboard.general.string = result.sanitizedReport
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
              item: result.sanitizedReport,
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
            "Keep the Pod awake, online, and unoccupied enough to avoid large motion. This compares the selected household Pod with this night's session, validates the Pod through Eight's device endpoint, and makes at most one read-only foreground live request. It never starts a Pod mode, runs in the background, saves raw samples, or writes Apple Health."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)

          Text(
            "Observed sample blocks only prove that piezo arrays are accessible. They do not prove sample rate, waveform meaning, beat accuracy, or fitness for calculating Apple Health SDNN."
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
    case complete(LivePiezoProbeResult)
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

  enum LivePiezoIdentitySource: String, Equatable, Sendable {
    case householdCurrentPod
    case trendsSession
    case unresolved

    var label: String {
      switch self {
      case .householdCurrentPod: "Selected household Pod"
      case .trendsSession: "Selected night's session"
      case .unresolved: "Unresolved"
      }
    }
  }

  enum LivePiezoPodGeneration: String, Equatable, Sendable {
    case pod1
    case pod2
    case pod3
    case pod4
    case pod5
    case pod6
    case conflicting
    case unknown
    case unavailable

    var label: String {
      switch self {
      case .pod1: "Pod 1"
      case .pod2: "Pod 2"
      case .pod3: "Pod 3"
      case .pod4: "Pod 4"
      case .pod5: "Pod 5"
      case .pod6: "Pod 6"
      case .conflicting: "Conflicting signals"
      case .unknown: "Unknown"
      case .unavailable: "Unavailable"
      }
    }

    static func classify(_ modelString: String?) -> LivePiezoPodGeneration {
      guard let modelString else { return .unavailable }
      let normalized = modelString
        .lowercased()
        .replacingOccurrences(of: "_", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: " ", with: "")
      if normalized == "pod6" { return .pod6 }
      if normalized == "pod5" { return .pod5 }
      if normalized == "pod4" || normalized == "pod4ultra" { return .pod4 }
      if normalized == "pod3" { return .pod3 }
      if normalized == "pod2" || normalized == "pod2pro" { return .pod2 }
      if normalized == "pod" || normalized == "pod1" { return .pod1 }
      return normalized.isEmpty ? .unavailable : .unknown
    }
  }

  enum LivePiezoIdentityRelationship: String, Equatable, Sendable {
    case same
    case different
    case unavailable

    var label: String {
      switch self {
      case .same: "Same identifier"
      case .different: "Different identifiers"
      case .unavailable: "Unavailable"
      }
    }
  }

  enum LivePiezoHouseholdStatus: String, Equatable, Sendable {
    case available
    case notFound
    case forbidden
    case unauthorized
    case rateLimited
    case rejected
    case networkError
    case invalidPayload

    var label: String {
      switch self {
      case .available: "Available"
      case .notFound: "HTTP 404"
      case .forbidden: "HTTP 403"
      case .unauthorized: "HTTP 401"
      case .rateLimited: "HTTP 429"
      case .rejected: "Other HTTP error"
      case .invalidPayload: "Unexpected payload"
      case .networkError: "Network error"
      }
    }

    var allowsTrendsFallback: Bool {
      switch self {
      case .notFound, .invalidPayload, .networkError:
        true
      case .available, .forbidden, .unauthorized, .rateLimited, .rejected:
        false
      }
    }
  }

  enum LivePiezoDeviceDetailStatus: String, Equatable, Sendable {
    case available
    case unavailable
    case identityMismatch
    case rejected
    case invalidPayload
    case networkError

    var label: String {
      switch self {
      case .available: "Available"
      case .unavailable: "Unavailable"
      case .identityMismatch: "Identifier mismatch"
      case .rejected: "HTTP error"
      case .invalidPayload: "Unexpected payload"
      case .networkError: "Network error"
      }
    }
  }

  enum LivePiezoOnlineStatus: String, Equatable, Sendable {
    case online
    case offline
    case unavailable

    var label: String {
      switch self {
      case .online: "Online"
      case .offline: "Offline"
      case .unavailable: "Unavailable"
      }
    }
  }

  enum LivePiezoEndpointStatus: String, Equatable, Sendable {
    case notAttempted
    case available
    case notFound
    case forbidden
    case unauthorized
    case rateLimited
    case rejected
    case networkError

    var label: String {
      switch self {
      case .notAttempted: "Not attempted"
      case .available: "HTTP 2xx"
      case .notFound: "HTTP 404"
      case .forbidden: "HTTP 403"
      case .unauthorized: "HTTP 401"
      case .rateLimited: "HTTP 429"
      case .rejected: "Other HTTP error"
      case .networkError: "Network error"
      }
    }
  }

  struct LivePiezoProbeAttempt: Equatable, Sendable {
    let identitySource: LivePiezoIdentitySource
    let relationshipToTrends: LivePiezoIdentityRelationship
    let generation: LivePiezoPodGeneration
    let onlineStatus: LivePiezoOnlineStatus
    let deviceDetailStatus: LivePiezoDeviceDetailStatus
    let liveStatus: LivePiezoEndpointStatus
    let streamSummary: LivePiezoProbeSummary?
  }

  struct LivePiezoProbeResult: Equatable, Sendable {
    let householdStatus: LivePiezoHouseholdStatus
    let selectedDeviceSetFound: Bool
    let householdDeviceCount: Int
    let selectedSetDeviceCount: Int
    let selectedSetPodCandidateCount: Int
    let preferredIdentitySource: LivePiezoIdentitySource
    let preferredGeneration: LivePiezoPodGeneration
    let identityRelationship: LivePiezoIdentityRelationship
    let attempts: [LivePiezoProbeAttempt]

    var streamSummary: LivePiezoProbeSummary? {
      attempts.lazy.compactMap(\.streamSummary).first
    }

    var liveRequestCount: Int {
      attempts.lazy.filter { $0.liveStatus != .notAttempted }.count
    }

    var outcomeLabel: String {
      if let streamSummary {
        return streamSummary.sampleBlocksObserved
          ? "Sample blocks available"
          : "Endpoint responded; no sample blocks"
      }
      guard let lastAttempt = attempts.last else { return "Not attempted" }
      return lastAttempt.liveStatus == .notAttempted ? "Not attempted" : "Unavailable"
    }

    var sanitizedReport: String {
      let attemptLines = attempts.enumerated().map { index, attempt in
        """
        - Candidate \(index + 1)
          identity source: \(attempt.identitySource.label)
          relationship to selected-night identity: \(attempt.relationshipToTrends.label)
          Pod generation category: \(attempt.generation.label)
          Pod online category: \(attempt.onlineStatus.label)
          device-details response: \(attempt.deviceDetailStatus.label)
          live endpoint response: \(attempt.liveStatus.label)
        """
      }.joined(separator: "\n")
      let streamSection = streamSummary?.sanitizedStreamSection ?? """
        Stream result
        - No successful live stream was returned by the bounded candidates.
        """

      return """
      Sleep Relay live piezo identity probe - sanitized
      Format: live-piezo-probe-v2
      Scope: one foreground identity discovery and at most one bounded live-stream attempt using an identifier returned for this authenticated account
      Contains: fixed identity relationships, Pod generation and online categories, response categories, counts, and aggregate stream diagnostics when available
      Excludes: sleep day, identifiers, names, firmware versions, credentials, tokens, URLs, response text, absolute timestamps, and raw sensor values

      Status: \(outcomeLabel)

      Identity discovery
      - Household summary: \(householdStatus.label)
      - Current device set found: \(selectedDeviceSetFound ? "yes" : "no")
      - Household devices: \(householdDeviceCount)
      - Selected-set devices: \(selectedSetDeviceCount)
      - Selected-set Pod candidates: \(selectedSetPodCandidateCount)
      - Preferred identity source: \(preferredIdentitySource.label)
      - Observed generation category: \(preferredGeneration.label)
      - Household Pod versus selected-night identity: \(identityRelationship.label)

      Candidate checks
      \(attemptLines.isEmpty ? "- None" : attemptLines)

      \(streamSection)

      Interpretation
      Eight's official Android Test Drive uses a physical Pod identifier from onboarding state and invokes this live route only in Pod 4 and Pod 5 UI flows. That UI gate is not a documented endpoint contract, so this probe makes at most one read request for any validated, online household Pod. The household's selected Pod is the closest current account-level resolver; that mapping is an inference, so an HTTP 404 does not prove raw data is absent on the Pod. It means this identity, account, generation, device state, or current server behavior did not expose the private route during this run.

      Privacy check
      This report is produced from in-memory categories and counts. Sleep Relay does not retain device or user identifiers, household names, firmware versions, raw samples, absolute event timestamps, credentials, access tokens, request URLs, or response bodies. Counts are sanitized diagnostics, not anonymous data.
      """
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
    let usableSampleBlockCount: Int
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

    var sampleBlocksObserved: Bool {
      usableSampleBlockCount > 0
    }

    var sanitizedStreamSection: String {
      """
      Stream result
      - Endpoint status: HTTP 2xx
      - Piezo sample blocks observed: \(sampleBlocksObserved ? "yes" : "no")
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
      - Piezo events with at least one finite sample: \(usableSampleBlockCount)

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
      An HTTP 2xx establishes only that the endpoint responded. A positive sample-block result establishes only that piezo arrays were accessible during this foreground run. Timestamp spacing and element throughput do not establish the sensor sample rate. This report cannot establish beat timing, an HRV formula, or Apple Health SDNN accuracy.

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
    case household = "household identity discovery"
    case deviceDetails = "Pod details validation"
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
      let specialization: String?
    }

    private struct ResolvedTrendsDevice: Sendable {
      let id: String
      let isExplicitPod: Bool
    }

    private struct HouseholdSummaryPayload: Decodable, Sendable {
      let currentSetID: String?
      let households: [Household]?

      enum CodingKeys: String, CodingKey {
        case currentSetID = "currentSet"
        case households
      }
    }

    private struct Household: Decodable, Sendable {
      let sets: [HouseholdDeviceSet]?
    }

    private struct HouseholdDeviceSet: Decodable, Sendable {
      let id: String?
      let devices: [HouseholdDevice]?

      enum CodingKeys: String, CodingKey {
        case id = "setId"
        case devices
      }
    }

    private struct HouseholdDevice: Decodable, Sendable {
      let id: String?
      let specialization: String?

      enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case specialization
      }
    }

    private struct DeviceResponseWrapper: Decodable, Sendable {
      let result: DeviceDetails
    }

    private struct DeviceDetails: Decodable, Sendable {
      let deviceID: String?
      let modelString: String?
      let online: Bool?
      let features: [String]?
      let sensors: [DeviceSensor]?

      enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case modelString
        case online
        case features
        case sensors
      }
    }

    private struct DeviceSensor: Decodable, Sendable {
      let generation: Int?

      enum CodingKeys: String, CodingKey {
        case generation = "version"
      }
    }

    private struct HouseholdDiscovery: Sendable {
      let status: LivePiezoHouseholdStatus
      let selectedDeviceSetFound: Bool
      let householdDeviceCount: Int
      let selectedSetDeviceCount: Int
      let selectedSetPodCandidateCount: Int
      let selectedPodID: String?
      let relationshipToTrends: LivePiezoIdentityRelationship

      static func unavailable(_ status: LivePiezoHouseholdStatus) -> HouseholdDiscovery {
        HouseholdDiscovery(
          status: status,
          selectedDeviceSetFound: false,
          householdDeviceCount: 0,
          selectedSetDeviceCount: 0,
          selectedSetPodCandidateCount: 0,
          selectedPodID: nil,
          relationshipToTrends: .unavailable
        )
      }
    }

    private struct DeviceDetailResult: Sendable {
      let status: LivePiezoDeviceDetailStatus
      let generation: LivePiezoPodGeneration
      let onlineStatus: LivePiezoOnlineStatus
      let echoedIdentityMatches: Bool
    }

    private struct LiveStreamReadResult: Sendable {
      let status: LivePiezoEndpointStatus
      let summary: LivePiezoProbeSummary?
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

    func run(forSleepDay sleepDay: String) async throws -> LivePiezoProbeResult {
      try Task.checkCancellation()
      let requestSession = makeSession(
        requestTimeout: 20,
        resourceTimeout: 30
      )
      defer { requestSession.invalidateAndCancel() }

      let authentication = try await authenticate(using: requestSession)
      try Task.checkCancellation()
      let trendsDevice: ResolvedTrendsDevice?
      do {
        trendsDevice = try await resolveTrendsDevice(
          forSleepDay: sleepDay,
          authentication: authentication,
          using: requestSession
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        trendsDevice = nil
      }
      try Task.checkCancellation()
      let householdDiscovery: HouseholdDiscovery
      do {
        householdDiscovery = try await discoverHouseholdPod(
          userID: authentication.userID,
          trendsDeviceID: trendsDevice?.id,
          accessToken: authentication.accessToken,
          using: requestSession
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        householdDiscovery = .unavailable(.networkError)
      }

      let selectedID: String?
      let identitySource: LivePiezoIdentitySource
      let relationship: LivePiezoIdentityRelationship
      if let householdID = householdDiscovery.selectedPodID {
        selectedID = householdID
        identitySource = .householdCurrentPod
        relationship = householdDiscovery.relationshipToTrends
      } else if householdDiscovery.status.allowsTrendsFallback,
        let trendsDevice,
        trendsDevice.isExplicitPod
      {
        selectedID = trendsDevice.id
        identitySource = .trendsSession
        relationship = .same
      } else {
        selectedID = nil
        identitySource = .unresolved
        relationship = householdDiscovery.relationshipToTrends
      }

      var attempts: [LivePiezoProbeAttempt] = []
      if let selectedID {
        try Task.checkCancellation()
        let detail: DeviceDetailResult
        do {
          detail = try await fetchDeviceDetails(
            deviceID: selectedID,
            accessToken: authentication.accessToken,
            using: requestSession
          )
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          try Task.checkCancellation()
          detail = DeviceDetailResult(
            status: .networkError,
            generation: .unavailable,
            onlineStatus: .unavailable,
            echoedIdentityMatches: false
          )
        }

        let liveResult: LiveStreamReadResult
        if detail.status == .available,
          detail.echoedIdentityMatches,
          detail.onlineStatus == .online
        {
          try Task.checkCancellation()
          do {
            liveResult = try await readLiveStream(
              deviceID: selectedID,
              accessToken: authentication.accessToken
            )
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            try Task.checkCancellation()
            liveResult = LiveStreamReadResult(status: .networkError, summary: nil)
          }
        } else {
          liveResult = LiveStreamReadResult(status: .notAttempted, summary: nil)
        }

        attempts.append(
          LivePiezoProbeAttempt(
            identitySource: identitySource,
            relationshipToTrends: relationship,
            generation: detail.generation,
            onlineStatus: detail.onlineStatus,
            deviceDetailStatus: detail.status,
            liveStatus: liveResult.status,
            streamSummary: liveResult.summary
          )
        )
      }

      return LivePiezoProbeResult(
        householdStatus: householdDiscovery.status,
        selectedDeviceSetFound: householdDiscovery.selectedDeviceSetFound,
        householdDeviceCount: householdDiscovery.householdDeviceCount,
        selectedSetDeviceCount: householdDiscovery.selectedSetDeviceCount,
        selectedSetPodCandidateCount: householdDiscovery.selectedSetPodCandidateCount,
        preferredIdentitySource: identitySource,
        preferredGeneration: attempts.first?.generation ?? .unavailable,
        identityRelationship: householdDiscovery.relationshipToTrends,
        attempts: attempts
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

    private func resolveTrendsDevice(
      forSleepDay sleepDay: String,
      authentication: AuthenticationPayload,
      using session: URLSession
    ) async throws -> ResolvedTrendsDevice {
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
      let mainDevice: TrendsDevice?
      if let mainID = selectedDay.mainSessionID,
        let device = sessions.first(where: { $0.id == mainID })?.device,
        let id = device.id,
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        mainDevice = device
      } else {
        mainDevice = nil
      }
      let fallbackDevice = sessions.reversed().lazy.compactMap(\.device).first(where: {
        guard let id = $0.id else { return false }
        return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
      guard let device = mainDevice ?? fallbackDevice, let rawDeviceID = device.id else {
        throw LivePiezoProbeError.deviceMissing
      }
      let deviceID = try Self.validatedPathIdentifier(rawDeviceID)
      let specialization = device.specialization?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      return ResolvedTrendsDevice(
        id: deviceID,
        isExplicitPod: specialization == "pod"
      )
    }

    private func discoverHouseholdPod(
      userID: String,
      trendsDeviceID: String?,
      accessToken: String,
      using session: URLSession
    ) async throws -> HouseholdDiscovery {
      let safeUserID = try Self.validatedPathIdentifier(userID)
      let url = URL(string: "https://app-api.8slp.net/v1/")!
        .appendingPathComponent("household")
        .appendingPathComponent("users")
        .appendingPathComponent(safeUserID)
        .appendingPathComponent("summary")
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("SleepRelay-Nightly/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await session.data(for: request)
      let http = try requireHTTPResponse(response, stage: .household)
      let status: LivePiezoHouseholdStatus
      switch http.statusCode {
      case 200..<300: status = .available
      case 401: status = .unauthorized
      case 403: status = .forbidden
      case 404: status = .notFound
      case 429: status = .rateLimited
      default: status = .rejected
      }
      guard status == .available else {
        return .unavailable(status)
      }
      guard let payload = try? JSONDecoder().decode(HouseholdSummaryPayload.self, from: data) else {
        return .unavailable(.invalidPayload)
      }

      return try Self.resolveHouseholdPod(
        in: payload,
        trendsDeviceID: trendsDeviceID
      )
    }

    private static func resolveHouseholdPod(
      in payload: HouseholdSummaryPayload,
      trendsDeviceID: String?
    ) throws -> HouseholdDiscovery {
      let allSets = (payload.households ?? []).flatMap { $0.sets ?? [] }
      let allDevices = allSets.flatMap { $0.devices ?? [] }
      let currentSetID = normalizedID(payload.currentSetID)
      let currentSetMatches: [HouseholdDeviceSet]
      if let currentSetID {
        currentSetMatches = allSets.filter { normalizedID($0.id) == currentSetID }
      } else {
        currentSetMatches = []
      }
      let selectedSet: HouseholdDeviceSet?
      selectedSet = currentSetMatches.count == 1 ? currentSetMatches[0] : nil
      let selectedDevices = selectedSet?.devices ?? []
      let allPods = uniqueValidPodDevices(allDevices)
      let globallyValidPodIDs = Set(allPods.compactMap { normalizedID($0.id) })
      let selectedPods = uniqueValidPodDevices(selectedDevices).filter {
        guard let id = normalizedID($0.id) else { return false }
        return globallyValidPodIDs.contains(id)
      }

      let selectedPod: HouseholdDevice?
      if selectedPods.count == 1 {
        selectedPod = selectedPods[0]
      } else if currentSetMatches.isEmpty,
        let trendsDeviceID,
        let trendsMatch = allPods.first(where: { device in
          normalizedID(device.id) == trendsDeviceID
        })
      {
        selectedPod = trendsMatch
      } else if currentSetMatches.isEmpty, allPods.count == 1 {
        selectedPod = allPods[0]
      } else {
        selectedPod = nil
      }

      let selectedPodID: String?
      if let rawSelectedPodID = selectedPod?.id {
        selectedPodID = try validatedPathIdentifier(rawSelectedPodID)
      } else {
        selectedPodID = nil
      }
      let relationship: LivePiezoIdentityRelationship
      if let selectedPodID, let trendsDeviceID {
        relationship = selectedPodID == trendsDeviceID ? .same : .different
      } else {
        relationship = .unavailable
      }
      return HouseholdDiscovery(
        status: .available,
        selectedDeviceSetFound: selectedSet != nil,
        householdDeviceCount: Set(allDevices.compactMap { normalizedID($0.id) }).count,
        selectedSetDeviceCount: Set(selectedDevices.compactMap { normalizedID($0.id) }).count,
        selectedSetPodCandidateCount: selectedPods.count,
        selectedPodID: selectedPodID,
        relationshipToTrends: relationship
      )
    }

    private func fetchDeviceDetails(
      deviceID: String,
      accessToken: String,
      using session: URLSession
    ) async throws -> DeviceDetailResult {
      let url = configuration.clientAPIBaseURL
        .appendingPathComponent("devices")
        .appendingPathComponent(deviceID)
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      request.setValue("SleepRelay-Nightly/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await session.data(for: request)
      let http = try requireHTTPResponse(response, stage: .deviceDetails)
      guard (200..<300).contains(http.statusCode) else {
        return DeviceDetailResult(
          status: http.statusCode == 404 ? .unavailable : .rejected,
          generation: .unavailable,
          onlineStatus: .unavailable,
          echoedIdentityMatches: false
        )
      }
      guard let payload = try? JSONDecoder().decode(DeviceResponseWrapper.self, from: data) else {
        return DeviceDetailResult(
          status: .invalidPayload,
          generation: .unavailable,
          onlineStatus: .unavailable,
          echoedIdentityMatches: false
        )
      }
      let echoedID = payload.result.deviceID.flatMap { try? Self.validatedPathIdentifier($0) }
      guard echoedID == deviceID else {
        return DeviceDetailResult(
          status: .identityMismatch,
          generation: .unavailable,
          onlineStatus: .unavailable,
          echoedIdentityMatches: false
        )
      }
      let onlineStatus: LivePiezoOnlineStatus
      switch payload.result.online {
      case true: onlineStatus = .online
      case false: onlineStatus = .offline
      case nil: onlineStatus = .unavailable
      }
      return DeviceDetailResult(
        status: .available,
        generation: classifyGeneration(payload.result),
        onlineStatus: onlineStatus,
        echoedIdentityMatches: true
      )
    }

    private static func uniqueValidPodDevices(_ devices: [HouseholdDevice]) -> [HouseholdDevice] {
      var order: [String] = []
      var grouped: [String: [HouseholdDevice]] = [:]
      for device in devices {
        guard let id = device.id, let validated = try? validatedPathIdentifier(id) else { continue }
        if grouped[validated] == nil { order.append(validated) }
        grouped[validated, default: []].append(device)
      }
      return order.compactMap { deviceID in
        guard let group = grouped[deviceID] else { return nil }
        let specializations = Set(group.map {
          $0.specialization?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "missing"
        })
        guard specializations == Set(["pod"]) else { return nil }
        return group[0]
      }
    }

    static func validateHouseholdResolverSelection() -> Bool {
      guard
        LivePiezoHouseholdStatus.notFound.allowsTrendsFallback,
        LivePiezoHouseholdStatus.invalidPayload.allowsTrendsFallback,
        LivePiezoHouseholdStatus.networkError.allowsTrendsFallback,
        !LivePiezoHouseholdStatus.available.allowsTrendsFallback,
        !LivePiezoHouseholdStatus.unauthorized.allowsTrendsFallback,
        !LivePiezoHouseholdStatus.forbidden.allowsTrendsFallback,
        !LivePiezoHouseholdStatus.rateLimited.allowsTrendsFallback,
        !LivePiezoHouseholdStatus.rejected.allowsTrendsFallback
      else {
        return false
      }

      func device(_ id: String?, _ specialization: String?) -> HouseholdDevice {
        HouseholdDevice(id: id, specialization: specialization)
      }
      func set(_ id: String?, _ devices: [HouseholdDevice]) -> HouseholdDeviceSet {
        HouseholdDeviceSet(id: id, devices: devices)
      }
      func resolve(
        currentSetID: String?,
        sets: [HouseholdDeviceSet],
        trendsDeviceID: String?
      ) -> HouseholdDiscovery? {
        let payload = HouseholdSummaryPayload(
          currentSetID: currentSetID,
          households: [Household(sets: sets)]
        )
        return try? resolveHouseholdPod(
          in: payload,
          trendsDeviceID: trendsDeviceID
        )
      }

      let privatePodID = "private-pod-identifier-7f31"
      let privateSetID = "private-current-set-4c92"
      guard
        let uniquePod = resolve(
          currentSetID: " \(privateSetID) ",
          sets: [
            set(privateSetID, [
              device(" \(privatePodID) ", "PoD"),
              device(privatePodID, "pod"),
              device("private-cover-identifier", "cover"),
            ])
          ],
          trendsDeviceID: "different-night-pod"
        ),
        uniquePod.selectedDeviceSetFound,
        uniquePod.householdDeviceCount == 2,
        uniquePod.selectedSetDeviceCount == 2,
        uniquePod.selectedSetPodCandidateCount == 1,
        uniquePod.selectedPodID == privatePodID,
        uniquePod.relationshipToTrends == .different
      else {
        return false
      }

      guard
        let ambiguous = resolve(
          currentSetID: "selected-set",
          sets: [set("selected-set", [device("pod-a", "pod"), device("pod-b", "pod")])],
          trendsDeviceID: "pod-b"
        ),
        ambiguous.selectedDeviceSetFound,
        ambiguous.selectedSetPodCandidateCount == 2,
        ambiguous.selectedPodID == nil,
        ambiguous.relationshipToTrends == .unavailable
      else {
        return false
      }

      guard
        let conflicting = resolve(
          currentSetID: "selected-set",
          sets: [
            set("selected-set", [
              device("same-device", "pod"),
              device("same-device", "cover"),
            ])
          ],
          trendsDeviceID: "same-device"
        ),
        conflicting.selectedDeviceSetFound,
        conflicting.selectedSetDeviceCount == 1,
        conflicting.selectedSetPodCandidateCount == 0,
        conflicting.selectedPodID == nil
      else {
        return false
      }

      guard
        let invalid = resolve(
          currentSetID: "selected-set",
          sets: [
            set("selected-set", [
              device("bad/path", "pod"),
              device("bad?query", "pod"),
              device("bad#fragment", "pod"),
              device(".", "pod"),
              device("..", "pod"),
              device("bad\\path", "pod"),
              device("bad\ncontrol", "pod"),
              device("valid-cover", "cover"),
            ])
          ],
          trendsDeviceID: "bad/path"
        ),
        invalid.selectedDeviceSetFound,
        invalid.selectedSetPodCandidateCount == 0,
        invalid.selectedPodID == nil
      else {
        return false
      }

      guard
        let crossSetConflict = resolve(
          currentSetID: "selected-set",
          sets: [
            set("selected-set", [device("conflicted-device", "pod")]),
            set("other-set", [device("conflicted-device", "pillow")]),
          ],
          trendsDeviceID: "conflicted-device"
        ),
        crossSetConflict.selectedDeviceSetFound,
        crossSetConflict.selectedSetPodCandidateCount == 0,
        crossSetConflict.selectedPodID == nil,
        crossSetConflict.relationshipToTrends == .unavailable
      else {
        return false
      }

      guard
        let fallback = resolve(
          currentSetID: "missing-set",
          sets: [set("other-set", [device("fallback-a", "pod"), device("fallback-b", "pod")])],
          trendsDeviceID: "fallback-b"
        ),
        !fallback.selectedDeviceSetFound,
        fallback.selectedPodID == "fallback-b",
        fallback.relationshipToTrends == .same
      else {
        return false
      }

      guard
        let duplicated = resolve(
          currentSetID: "duplicated-set",
          sets: [
            set("duplicated-set", [device("duplicate-a", "pod")]),
            set("duplicated-set", [device("duplicate-b", "pod")]),
          ],
          trendsDeviceID: "duplicate-b"
        ),
        !duplicated.selectedDeviceSetFound,
        duplicated.selectedPodID == nil,
        duplicated.relationshipToTrends == .unavailable
      else {
        return false
      }

      let privacyResult = LivePiezoProbeResult(
        householdStatus: uniquePod.status,
        selectedDeviceSetFound: uniquePod.selectedDeviceSetFound,
        householdDeviceCount: uniquePod.householdDeviceCount,
        selectedSetDeviceCount: uniquePod.selectedSetDeviceCount,
        selectedSetPodCandidateCount: uniquePod.selectedSetPodCandidateCount,
        preferredIdentitySource: .householdCurrentPod,
        preferredGeneration: .unavailable,
        identityRelationship: uniquePod.relationshipToTrends,
        attempts: []
      )
      let report = privacyResult.sanitizedReport
      return !report.contains(privatePodID)
        && !report.contains(privateSetID)
        && !report.contains("private-cover-identifier")
        && !report.contains("different-night-pod")
        && !report.contains("https://app-api.8slp.net")
    }

    private func classifyGeneration(_ details: DeviceDetails) -> LivePiezoPodGeneration {
      if let sensorGeneration = details.sensors?.first?.generation {
        switch sensorGeneration {
        case 1: return .pod1
        case 2: return .pod2
        case 3: return .pod3
        case 4: return .pod4
        case 5: return .pod5
        case 6: return .pod6
        default: return .unknown
        }
      }
      let modelClassification = LivePiezoPodGeneration.classify(details.modelString)
      let normalizedFeatures = Set((details.features ?? []).map {
        $0.lowercased()
          .replacingOccurrences(of: "_", with: "")
          .replacingOccurrences(of: "-", with: "")
          .replacingOccurrences(of: " ", with: "")
      })
      let hasButtons = normalizedFeatures.contains("buttoncontrols")
      let hasTaps = normalizedFeatures.contains("tapcontrols")
      let featureClassification: LivePiezoPodGeneration = if hasButtons == hasTaps {
        .unavailable
      } else {
        hasButtons ? .pod5 : .pod4
      }
      let modelIsKnown = ![.unknown, .unavailable].contains(modelClassification)
      let featureIsKnown = featureClassification != .unavailable
      if modelIsKnown, featureIsKnown, modelClassification != featureClassification {
        return .conflicting
      }
      if modelIsKnown { return modelClassification }
      if featureIsKnown { return featureClassification }
      return modelClassification
    }

    private static func normalizedID(_ rawValue: String?) -> String? {
      guard let rawValue else { return nil }
      let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }

    private static func validatedPathIdentifier(_ rawValue: String) throws -> String {
      guard let value = normalizedID(rawValue) else {
        throw LivePiezoProbeError.deviceMissing
      }
      guard
        value.utf8.count <= 512,
        value != ".",
        value != "..",
        !value.contains("/"),
        !value.contains("\\"),
        !value.contains("?"),
        !value.contains("#"),
        !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
      else {
        throw LivePiezoProbeError.invalidDeviceReference
      }
      return value
    }

    private func readLiveStream(
      deviceID: String,
      accessToken: String
    ) async throws -> LiveStreamReadResult {
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
      let liveRequest = request

      let liveSession = makeSession(
        requestTimeout: TimeInterval(Self.requestInactivityTimeoutSeconds),
        resourceTimeout: 40
      )
      defer { liveSession.invalidateAndCancel() }
      let accumulator = LivePiezoProbeAccumulator()

      let (bytes, response) = try await withTaskCancellationHandler {
        try await liveSession.bytes(for: liveRequest)
      } onCancel: {
        liveSession.invalidateAndCancel()
      }
      let http = try requireHTTPResponse(response, stage: .liveStream)
      switch http.statusCode {
      case 200..<300:
        break
      case 401:
        return LiveStreamReadResult(status: .unauthorized, summary: nil)
      case 403:
        return LiveStreamReadResult(status: .forbidden, summary: nil)
      case 404:
        return LiveStreamReadResult(status: .notFound, summary: nil)
      case 429:
        return LiveStreamReadResult(status: .rateLimited, summary: nil)
      default:
        return LiveStreamReadResult(status: .rejected, summary: nil)
      }
      await accumulator.recordSuccessfulResponse(
        contentType: http.value(forHTTPHeaderField: "Content-Type")
      )

      let stopReason = try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(
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
      return LiveStreamReadResult(
        status: .available,
        summary: try await accumulator.makeSummary(stopReason: stopReason)
      )
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
    private var usableSampleBlockCount = 0
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
      if finiteCount > 0 { usableSampleBlockCount += 1 }
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
        usableSampleBlockCount: usableSampleBlockCount,
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
      guard LivePiezoProbeClient.validateHouseholdResolverSelection() else {
        return false
      }

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
        summary.usableSampleBlockCount == 2,
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
        summary.sanitizedStreamSection.contains("Stream result"),
        !summary.sanitizedStreamSection.contains("2026-08-30T12:00:00"),
        !summary.sanitizedStreamSection.contains(firstLine)
      else {
        return false
      }

      let result = LivePiezoProbeResult(
        householdStatus: .available,
        selectedDeviceSetFound: true,
        householdDeviceCount: 2,
        selectedSetDeviceCount: 2,
        selectedSetPodCandidateCount: 1,
        preferredIdentitySource: .householdCurrentPod,
        preferredGeneration: .pod5,
        identityRelationship: .different,
        attempts: [
          LivePiezoProbeAttempt(
            identitySource: .householdCurrentPod,
            relationshipToTrends: .different,
            generation: .pod5,
            onlineStatus: .online,
            deviceDetailStatus: .available,
            liveStatus: .available,
            streamSummary: summary
          )
        ]
      )
      guard
        result.sanitizedReport.contains("Format: live-piezo-probe-v2"),
        result.sanitizedReport.contains("Pod 5"),
        result.sanitizedReport.contains("Different identifiers"),
        result.liveRequestCount == 1,
        result.outcomeLabel == "Sample blocks available",
        !result.sanitizedReport.contains("2026-08-30T12:00:00"),
        !result.sanitizedReport.contains(firstLine)
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
      let noBlocksResult = LivePiezoProbeResult(
        householdStatus: .available,
        selectedDeviceSetFound: true,
        householdDeviceCount: 1,
        selectedSetDeviceCount: 1,
        selectedSetPodCandidateCount: 1,
        preferredIdentitySource: .householdCurrentPod,
        preferredGeneration: .pod5,
        identityRelationship: .same,
        attempts: [
          LivePiezoProbeAttempt(
            identitySource: .householdCurrentPod,
            relationshipToTrends: .same,
            generation: .pod5,
            onlineStatus: .online,
            deviceDetailStatus: .available,
            liveStatus: .available,
            streamSummary: oversizedSummary
          )
        ]
      )
      return oversizedSummary.nonemptyLineCount == 1
        && oversizedSummary.oversizedLineCount == 1
        && oversizedSummary.piezoEventCount == 0
        && !oversizedSummary.sampleBlocksObserved
        && noBlocksResult.outcomeLabel == "Endpoint responded; no sample blocks"
        && noBlocksResult.sanitizedReport.contains("Piezo sample blocks observed: no")
    }
  }

  #Preview {
    NavigationStack {
      DeveloperView(model: .preview)
    }
  }
#endif
