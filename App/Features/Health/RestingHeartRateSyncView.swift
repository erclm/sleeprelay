import SleepRelayCore
import SwiftUI

struct RestingHeartRateSyncSection: View {
  let night: EightSleepNight
  @Bindable var model: HealthCoverageModel
  let presentReview: (RestingHeartRateSheetDestination) -> Void

  var body: some View {
    Section {
      switch model.restingHeartRateState(for: night) {
      case .idle, .loading:
        HStack {
          ProgressView()
          Text("Checking visible RHR sources…")
        }

      case .loaded(let candidate, let decision):
        LabeledContent("Eight reported RHR") {
          Text(candidate.valueBPM, format: .number.precision(.fractionLength(0...1)))
          + Text(" bpm")
        }

        switch decision {
        case .ready:
          Label("No overlapping RHR sample is visible", systemImage: "checkmark.circle")
            .foregroundStyle(.green)
          Button("Review RHR import") {
            presentReview(.write(candidate: candidate, decision: decision))
          }
          .buttonStyle(.borderedProminent)

        case .otherSourcesPresent(let sources):
          Label(
            "Existing source: \(sources.formatted(.list(type: .and)))",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.orange)
          Button("Review additional RHR source") {
            presentReview(.write(candidate: candidate, decision: decision))
          }

        case .eightAlreadyPresent:
          Label("Eight Sleep already has an overlapping RHR sample", systemImage: "checkmark.shield")
            .foregroundStyle(.green)
          Text("Sleep Relay will not add a duplicate.")
            .font(.footnote)
            .foregroundStyle(.secondary)

        case .alreadyWritten:
          Label("Synced by Sleep Relay", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
          Button("Remove Sleep Relay sample", role: .destructive) {
            presentReview(.delete(candidate: candidate))
          }
        }

        Text(
          "Apple may hide samples when read access is denied. Sleep Relay uses a stable sync ID and never changes another app's samples."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)

      case .writing(let candidate):
        progressRow("Writing \(format(candidate.valueBPM)) bpm…")

      case .deleting:
        progressRow("Removing Sleep Relay's sample…")

      case .unavailable(let message):
        Label(message, systemImage: "heart.slash")
          .foregroundStyle(.secondary)

      case .failed(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
        Button("Check Again") {
          Task { await model.loadRestingHeartRateStatus(for: night) }
        }
      }
    } header: {
      Text("Apple Health RHR")
    } footer: {
      Text(
        "This writes only Eight's reported resting heart rate. Eight HRV is RMSSD, while Apple Health accepts SDNN, so no HRV is written."
      )
    }
    .task(id: night.id) {
      await model.loadRestingHeartRateStatus(for: night)
    }
  }

  private func progressRow(_ title: String) -> some View {
    HStack {
      ProgressView()
      Text(title)
    }
  }

  private func format(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }
}

enum RestingHeartRateSheetDestination: Identifiable {
  case write(
    candidate: RestingHeartRateSyncCandidate,
    decision: RestingHeartRateSyncDecision
  )
  case delete(candidate: RestingHeartRateSyncCandidate)

  var id: String {
    switch self {
    case .write(let candidate, _): "write-\(candidate.id)"
    case .delete(let candidate): "delete-\(candidate.id)"
    }
  }
}

struct RestingHeartRateWriteReview: View {
  let candidate: RestingHeartRateSyncCandidate
  let decision: RestingHeartRateSyncDecision
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Proposed Apple Health sample") {
          LabeledContent("Type", value: "Resting Heart Rate")
          LabeledContent("Value") {
            Text(candidate.valueBPM, format: .number.precision(.fractionLength(0...1)))
            + Text(" bpm")
          }
          LabeledContent("Date") {
            Text(candidate.endDate, format: .dateTime.weekday().month().day().hour().minute())
          }
          LabeledContent("Health source", value: "Sleep Relay")
        }

        if case .otherSourcesPresent(let sources) = decision {
          Section("Existing data") {
            Label(
              "Apple Health already shows RHR from \(sources.formatted(.list(type: .and))).",
              systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
            Text(
              "Continuing adds Eight's reported value as another source. It does not replace or delete the existing sample."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        }

        Section("What is and is not written") {
          Label("One resting-heart-rate sample", systemImage: "heart.text.square")
          Label("No sleep, heart-rate, or respiratory samples", systemImage: "minus.circle")
          Label("No HRV: RMSSD is not SDNN", systemImage: "waveform.path.ecg")
        }
      }
      .navigationTitle("Review RHR Import")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(decision.hasOtherSources ? "Add Anyway" : "Add to Health") {
            onConfirm()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

struct RestingHeartRateDeleteReview: View {
  let candidate: RestingHeartRateSyncCandidate
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Remove Sleep Relay's \(candidate.valueBPM.formatted(.number.precision(.fractionLength(0...1)))) bpm resting-heart-rate sample for \(candidate.day)?"
          )
          Text("Samples written by Eight Sleep, Google Health, WHOOP, or any other app are untouched.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Remove RHR Sample")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Remove", role: .destructive) {
            onConfirm()
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}

extension RestingHeartRateSyncDecision {
  var hasOtherSources: Bool {
    if case .otherSourcesPresent = self { return true }
    return false
  }
}
