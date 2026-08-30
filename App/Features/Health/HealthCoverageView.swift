import SleepRelayCore
import SwiftUI

struct HealthCoverageView: View {
  @Bindable var model: HealthCoverageModel

  var body: some View {
    Group {
      switch model.state {
      case .unavailable:
        ContentUnavailableView(
          "Health Data Unavailable",
          systemImage: "heart.slash",
          description: Text("HealthKit is not available on this device.")
        )
      case .notRequested:
        permissionIntro
      case .loading:
        ProgressView("Reading visible coverage…")
      case .loaded(let lastUpdated, let coverage):
        coverageList(lastUpdated: lastUpdated, coverage: coverage)
      case .failed(let message):
        ContentUnavailableView {
          Label("Health Audit Failed", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await model.requestReadAccessAndLoad() }
          }
        }
      }
    }
    .navigationTitle("Health Coverage")
  }

  private var permissionIntro: some View {
    ContentUnavailableView {
      Label("Audit Apple Health", systemImage: "heart.text.square")
    } description: {
      Text(
        "Sleep Relay can run a read-only audit of recent sleep, heart-rate, respiratory-rate, resting-heart-rate, and HRV SDNN coverage. RHR imports are reviewed separately from an Eight night."
      )
    } actions: {
      Button("Allow Read-Only Access") {
        Task { await model.requestReadAccessAndLoad() }
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("health.allowReadAccess")
    }
  }

  private func coverageList(
    lastUpdated: Date,
    coverage: [HealthMetricCoverage]
  ) -> some View {
    List {
      Section {
        Picker("Lookback", selection: $model.lookbackDays) {
          Text("7 days").tag(7)
          Text("14 days").tag(14)
          Text("30 days").tag(30)
        }
        .pickerStyle(.segmented)

        LabeledContent("Last checked") {
          Text(lastUpdated, format: .dateTime.month().day().hour().minute())
        }
      } header: {
        Text("Audit Range")
      } footer: {
        Text("Change the range, then refresh to run a new read-only query.")
      }

      ForEach(coverage) { item in
        Section {
          NavigationLink(value: item) {
            MetricCoverageRow(coverage: item)
          }
        } header: {
          Label(item.metric.title, systemImage: item.metric.systemImage)
        }
      }

      Section("Important") {
        Label("This coverage refresh is read-only", systemImage: "checkmark.shield")
        Text(
          "No visible samples can mean there is no data, read access was denied, or access is limited. Sleep Relay cannot distinguish those cases and will not treat an empty result as proof that data is missing. Only a separately confirmed RHR import can write or remove Sleep Relay's own sample."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .navigationDestination(for: HealthMetricCoverage.self) { item in
      HealthMetricCoverageDetailView(coverage: item)
    }
    .refreshable {
      await model.refresh()
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await model.refresh() }
        } label: {
          Label("Refresh Health coverage", systemImage: "arrow.clockwise")
        }
        .accessibilityIdentifier("health.refresh")
      }
    }
  }
}

private struct MetricCoverageRow: View {
  let coverage: HealthMetricCoverage

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        if coverage.hasVisibleSamples {
          Text("\(coverage.sampleCount) visible samples")
            .font(.headline)
          Text("\(coverage.sources.count) sources across \(nightCount) sleep nights")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("No visible samples")
            .font(.headline)
          Text("Empty results are permission-ambiguous")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      Image(systemName: coverage.hasVisibleSamples ? "checkmark.circle" : "questionmark.circle")
        .foregroundStyle(coverage.hasVisibleSamples ? Color.green : Color.orange)
    }
    .padding(.vertical, 2)
  }

  private var nightCount: Int {
    Set(coverage.nights.map(\.nightDate)).count
  }
}

private struct HealthMetricCoverageDetailView: View {
  let coverage: HealthMetricCoverage

  var body: some View {
    List {
      if coverage.sources.isEmpty {
        Section {
          ContentUnavailableView(
            "No Visible Samples",
            systemImage: "questionmark.circle",
            description: Text(
              "This does not prove the metric is missing; read access may be denied or limited."
            )
          )
        }
      } else {
        Section("Observed Sources") {
          ForEach(coverage.sources) { source in
            SourceCoverageRow(coverage: source)
          }
        }

        Section("Sleep Nights") {
          ForEach(coverage.nights) { night in
            NightCoverageRow(coverage: night)
          }
        }
      }
    }
    .navigationTitle(coverage.metric.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct SourceCoverageRow: View {
  let coverage: HealthSourceCoverage

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(coverage.source.name)
          .font(.headline)
        Spacer()
        Text("\(coverage.sampleCount)")
          .font(.subheadline.monospacedDigit())
      }
      Text(coverage.source.bundleIdentifier)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      if let version = coverage.source.version, !version.isEmpty {
        Text("Version \(version) · \(coverage.nightCount) nights")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct NightCoverageRow: View {
  let coverage: HealthNightCoverage

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(coverage.nightDate, format: .dateTime.weekday().month().day())
          .font(.headline)
        Spacer()
        Text("\(coverage.sampleCount) samples")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(coverage.source.name)
        .font(.subheadline)
      Text(
        "\(coverage.firstSampleStart.formatted(date: .omitted, time: .shortened))–\(coverage.lastSampleEnd.formatted(date: .omitted, time: .shortened))"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

extension HealthMetricIdentifier {
  fileprivate var title: String {
    switch self {
    case .sleepAnalysis: "Sleep Analysis"
    case .heartRate: "Heart Rate"
    case .respiratoryRate: "Respiratory Rate"
    case .restingHeartRate: "Resting Heart Rate"
    case .heartRateVariabilitySDNN: "HRV (SDNN)"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .sleepAnalysis: "bed.double"
    case .heartRate: "heart"
    case .respiratoryRate: "lungs"
    case .restingHeartRate: "heart.text.square"
    case .heartRateVariabilitySDNN: "waveform.path.ecg"
    }
  }
}

#Preview("Coverage") {
  NavigationStack {
    HealthCoverageView(model: .preview)
  }
}

#Preview("No visible samples") {
  NavigationStack {
    HealthCoverageView(model: .emptyPreview)
  }
}
