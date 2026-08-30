import SleepRelayCore
import SwiftUI

struct BackfillHistoryView: View {
  let model: AppModel
  @Bindable var healthModel: HealthCoverageModel

  @State private var review: BackfillReviewDestination?
  @State private var shouldBeginBackfillAfterDismiss = false

  var body: some View {
    Form {
      Section("Safe scope") {
        Label("Eight reported resting heart rate only", systemImage: "heart.text.square")
        Label("Existing RHR sources are skipped", systemImage: "checkmark.shield")
        Label("HRV is never converted from RMSSD to SDNN", systemImage: "waveform.path.ecg")
        Text(
          "Sleep Relay checks available Eight history from 2015 through today. It does not rewrite sleep, heart-rate, or respiratory data that Eight Sleep already exports."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("Ongoing sync") {
        Toggle("Auto-sync new missing RHR", isOn: $healthModel.isAutomaticSyncEnabled)
        Text(
          "After Apple Health permission is granted, Sleep Relay checks when the app refreshes on a new local sleep day. There is no hourly timer."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)

        if let date = healthModel.lastAutomaticSyncDate {
          LabeledContent("Last automatic check") {
            Text(date, format: .dateTime.month().day().hour().minute())
          }
          if healthModel.lastAutomaticSyncAddedCount > 0 {
            LabeledContent(
              "Added last check",
              value: "\(healthModel.lastAutomaticSyncAddedCount)"
            )
          }
        }
      }

      historySection
      healthAuditSection

      Section {
        Text(
          "HealthKit may return no samples when read access is denied. Sleep Relay still uses stable sync IDs so it will not duplicate its own writes."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Backfill History")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $review, onDismiss: beginPendingBackfill) { destination in
      switch destination {
      case .write(let audit):
        BackfillReviewView(audit: audit) {
          shouldBeginBackfillAfterDismiss = true
        }
      }
    }
  }

  @ViewBuilder
  private var historySection: some View {
    Section("Eight Sleep history") {
      switch model.historyState {
      case .idle:
        Button("Audit and Backfill History") {
          startAudit()
        }
        .buttonStyle(.borderedProminent)

      case .loading(let completed, let total):
        ProgressView(value: Double(completed), total: Double(max(total, 1))) {
          Text("Fetching Eight history…")
        } currentValueLabel: {
          Text("\(completed) of \(total) date ranges")
        }

      case .loaded(let fetchedAt, let sourceNightCount, _, _):
        Label("Loaded \(sourceNightCount) nights", systemImage: "checkmark.circle")
          .foregroundStyle(.green)
        LabeledContent("Fetched") {
          Text(fetchedAt, format: .dateTime.month().day().hour().minute())
        }
        Button("Run Audit Again") {
          startAudit()
        }

      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
        Button("Try Again") {
          startAudit()
        }
      }
    }
  }

  @ViewBuilder
  private var healthAuditSection: some View {
    switch healthModel.backfillState {
    case .idle:
      EmptyView()

    case .auditing:
      Section("Apple Health audit") {
        HStack {
          ProgressView()
          Text("Checking existing RHR sources…")
        }
      }

    case .ready(let audit):
      auditSection(audit)
      Section {
        if audit.readyCount > 0 {
          Button("Review \(audit.readyCount) Missing RHR Imports") {
            review = .write(audit)
          }
          .buttonStyle(.borderedProminent)
        } else {
          Label("No missing RHR samples are ready to add", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

    case .writing(let completed, let total):
      Section("Adding to Apple Health") {
        ProgressView(value: Double(completed), total: Double(max(total, 1))) {
          Text("Writing missing RHR samples…")
        } currentValueLabel: {
          Text("\(completed) of \(total)")
        }
      }

    case .completed(let audit, let result):
      Section("Backfill complete") {
        Label("Added \(result.addedCount) RHR samples", systemImage: "checkmark.circle.fill")
          .foregroundStyle(result.failedCount == 0 ? .green : .orange)
        LabeledContent("Skipped safely", value: "\(result.skippedCount)")
        if result.failedCount > 0 {
          LabeledContent("Could not add", value: "\(result.failedCount)")
            .foregroundStyle(.red)
        }
      }
      auditSection(audit)

    case .failed(let message):
      Section("Apple Health audit") {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
        Button("Run Audit Again") {
          auditLoadedHistory()
        }
      }
    }
  }

  private func auditSection(_ audit: RestingHeartRateBackfillAudit) -> some View {
    Section("Audit results") {
      LabeledContent("Eight nights checked", value: "\(audit.sourceNightCount)")
      LabeledContent("Missing RHR ready to add", value: "\(audit.readyCount)")
      LabeledContent("Already written by Sleep Relay", value: "\(audit.alreadyWrittenCount)")
      LabeledContent("Eight RHR already present", value: "\(audit.eightAlreadyPresentCount)")
      LabeledContent("Other RHR source present", value: "\(audit.otherSourceCount)")
      LabeledContent("No validated RHR candidate", value: "\(audit.invalidNightCount)")
    }
  }

  private func startAudit() {
    Task {
      await model.loadAllHistory()
      auditLoadedHistory()
    }
  }

  private func auditLoadedHistory() {
    guard
      case .loaded(_, let sourceNightCount, let invalidNightCount, let candidates) =
        model.historyState
    else { return }
    Task {
      await healthModel.auditBackfill(
        candidates: candidates,
        sourceNightCount: sourceNightCount,
        invalidNightCount: invalidNightCount
      )
    }
  }

  private func beginPendingBackfill() {
    guard shouldBeginBackfillAfterDismiss else { return }
    shouldBeginBackfillAfterDismiss = false
    // Let the SwiftUI sheet finish dismissing before HealthKit presents its
    // authorization controller. Presenting both at once can terminate the app.
    Task {
      await Task.yield()
      await healthModel.performBackfill()
    }
  }
}

private enum BackfillReviewDestination: Identifiable {
  case write(RestingHeartRateBackfillAudit)

  var id: String { "rhr-backfill-review" }
}

private struct BackfillReviewView: View {
  let audit: RestingHeartRateBackfillAudit
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Proposed import") {
          LabeledContent("Apple Health type", value: "Resting Heart Rate")
          LabeledContent("Samples to add", value: "\(audit.readyCount)")
          LabeledContent("Existing-source nights skipped", value: "\(audit.otherSourceCount)")
          LabeledContent("Invalid or unavailable nights", value: "\(audit.invalidNightCount)")
        }

        Section("Safety") {
          Label("Only Eight's reported RHR", systemImage: "heart.text.square")
          Label("Stable ID prevents repeat writes", systemImage: "checkmark.shield")
          Label("No HRV conversion or write", systemImage: "waveform.path.ecg")
        }
      }
      .navigationTitle("Review Backfill")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add \(audit.readyCount) Samples") {
            onConfirm()
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

#Preview {
  NavigationStack {
    BackfillHistoryView(model: .preview, healthModel: .emptyPreview)
  }
}
