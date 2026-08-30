import SleepRelayCore
import SwiftUI

struct SleepDataView: View {
  let model: AppModel
  let healthModel: HealthCoverageModel

  var body: some View {
    Group {
      if model.nights.isEmpty {
        ContentUnavailableView {
          Label("No Eight Sleep data", systemImage: "bed.double")
        } description: {
          Text(
            "Connect your account to fetch the last seven nights. Only an RHR import you explicitly confirm can write to Apple Health."
          )
        } actions: {
          Button("Go to Connect") {
            model.selectedTab = .connect
          }
        }
      } else {
        List(model.nights) { night in
          NavigationLink(value: night) {
            NightRow(night: night)
          }
        }
        .navigationDestination(for: EightSleepNight.self) { night in
          SleepNightDetailView(night: night, healthModel: healthModel)
        }
        .refreshable {
          await model.refresh()
        }
      }
    }
    .navigationTitle("Eight Data")
    .toolbar {
      if !model.nights.isEmpty {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Task { await model.refresh() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
        }
      }
    }
  }
}

private struct NightRow: View {
  let night: EightSleepNight

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(night.day)
          .font(.headline)
        Spacer()
        if let score = night.score {
          Text("Score \(score, format: .number.precision(.fractionLength(0)))")
            .font(.subheadline.weight(.semibold))
        }
      }

      HStack(spacing: 12) {
        if let duration = night.sleepDurationSeconds {
          Label(durationText(duration), systemImage: "moon.zzz")
        }
        if let heartRate = night.averageHeartRateBPM {
          Label(
            "\(heartRate, format: .number.precision(.fractionLength(0))) bpm", systemImage: "heart")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

func durationText(_ seconds: Double) -> String {
  guard
    seconds.isFinite,
    seconds >= 0,
    let totalMinutes = Int(exactly: (seconds / 60).rounded(.towardZero))
  else {
    return "Unavailable"
  }
  return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
}
