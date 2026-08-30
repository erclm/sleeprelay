import Foundation
import SleepRelayCore

@MainActor
final class FixtureHealthCoverageProvider: HealthCoverageProviding {
  let isHealthDataAvailable: Bool
  let sleepRelayBundleIdentifier = "app.sleeprelay.ios"
  private var samples: [HealthCoverageSampleRecord]
  private var restingHeartRateSamples: [RestingHeartRateHealthSample]

  init(
    isHealthDataAvailable: Bool = true,
    samples: [HealthCoverageSampleRecord] = FixtureHealthCoverageProvider.samples,
    restingHeartRateSamples: [RestingHeartRateHealthSample] =
      FixtureHealthCoverageProvider.restingHeartRateSamples
  ) {
    self.isHealthDataAvailable = isHealthDataAvailable
    self.samples = samples
    self.restingHeartRateSamples = restingHeartRateSamples
  }

  func requestReadAuthorization() async throws {}

  func fetchSamples(from startDate: Date, to endDate: Date) async throws
    -> [HealthCoverageSampleRecord]
  {
    samples.filter { $0.startDate >= startDate && $0.startDate < endDate }
  }

  func requestRestingHeartRateWriteAuthorization() async throws {}

  func fetchRestingHeartRateSamples(
    from startDate: Date,
    to endDate: Date
  ) async throws -> [RestingHeartRateHealthSample] {
    restingHeartRateSamples.filter {
      $0.startDate <= endDate && $0.endDate >= startDate
    }
  }

  func saveRestingHeartRate(_ candidate: RestingHeartRateSyncCandidate) async throws {
    let source = HealthDataSource(
      name: "Sleep Relay",
      bundleIdentifier: sleepRelayBundleIdentifier,
      version: "Preview"
    )
    restingHeartRateSamples.append(
      RestingHeartRateHealthSample(
        source: source,
        valueBPM: candidate.valueBPM,
        startDate: candidate.endDate,
        endDate: candidate.endDate,
        syncIdentifier: candidate.syncIdentifier
      )
    )
    samples.append(
      HealthCoverageSampleRecord(
        metric: .restingHeartRate,
        source: source,
        startDate: candidate.endDate,
        endDate: candidate.endDate
      )
    )
  }

  func deleteRestingHeartRate(syncIdentifier: String) async throws {
    let deletedDates = Set(
      restingHeartRateSamples
        .filter {
          $0.source.bundleIdentifier == sleepRelayBundleIdentifier
            && $0.syncIdentifier == syncIdentifier
        }
        .map(\.startDate)
    )
    restingHeartRateSamples.removeAll {
      $0.source.bundleIdentifier == sleepRelayBundleIdentifier
        && $0.syncIdentifier == syncIdentifier
    }
    samples.removeAll {
      $0.metric == .restingHeartRate
        && $0.source.bundleIdentifier == sleepRelayBundleIdentifier
        && deletedDates.contains($0.startDate)
    }
  }

  static let samples: [HealthCoverageSampleRecord] = {
    let eight = HealthDataSource(
      name: "Eight Sleep",
      bundleIdentifier: "com.example.eightsleep",
      version: "6.9"
    )
    let watch = HealthDataSource(
      name: "Apple Watch",
      bundleIdentifier: "com.apple.health",
      version: nil
    )
    let base = Date(timeIntervalSince1970: 1_777_593_600)

    return [
      HealthCoverageSampleRecord(
        metric: .sleepAnalysis,
        source: eight,
        startDate: base.addingTimeInterval(23 * 3_600),
        endDate: base.addingTimeInterval(30 * 3_600)
      ),
      HealthCoverageSampleRecord(
        metric: .heartRate,
        source: eight,
        startDate: base.addingTimeInterval(24 * 3_600),
        endDate: base.addingTimeInterval(24 * 3_600 + 60)
      ),
      HealthCoverageSampleRecord(
        metric: .heartRate,
        source: watch,
        startDate: base.addingTimeInterval(25 * 3_600),
        endDate: base.addingTimeInterval(25 * 3_600 + 60)
      ),
      HealthCoverageSampleRecord(
        metric: .respiratoryRate,
        source: eight,
        startDate: base.addingTimeInterval(26 * 3_600),
        endDate: base.addingTimeInterval(26 * 3_600 + 60)
      ),
      HealthCoverageSampleRecord(
        metric: .heartRateVariabilitySDNN,
        source: watch,
        startDate: base.addingTimeInterval(27 * 3_600),
        endDate: base.addingTimeInterval(27 * 3_600 + 60)
      ),
    ]
  }()

  static let restingHeartRateSamples: [RestingHeartRateHealthSample] = [
    RestingHeartRateHealthSample(
      source: HealthDataSource(
        name: "Google Health",
        bundleIdentifier: "com.fitbit.FitbitMobile",
        version: "Preview"
      ),
      valueBPM: 54,
      startDate: Date(timeIntervalSince1970: 1_788_038_400),
      endDate: Date(timeIntervalSince1970: 1_788_067_200),
      syncIdentifier: nil
    )
  ]
}
