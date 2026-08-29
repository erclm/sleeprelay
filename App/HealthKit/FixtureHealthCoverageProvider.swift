import Foundation
import SleepRelayCore

@MainActor
final class FixtureHealthCoverageProvider: HealthCoverageProviding {
  let isHealthDataAvailable: Bool
  private let samples: [HealthCoverageSampleRecord]

  init(
    isHealthDataAvailable: Bool = true,
    samples: [HealthCoverageSampleRecord] = FixtureHealthCoverageProvider.samples
  ) {
    self.isHealthDataAvailable = isHealthDataAvailable
    self.samples = samples
  }

  func requestReadAuthorization() async throws {}

  func fetchSamples(from startDate: Date, to endDate: Date) async throws
    -> [HealthCoverageSampleRecord]
  {
    samples.filter { $0.startDate >= startDate && $0.startDate < endDate }
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
}
