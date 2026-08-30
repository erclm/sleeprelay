import Foundation
import SleepRelayCore

@MainActor
protocol HealthCoverageProviding {
  var isHealthDataAvailable: Bool { get }
  var sleepRelayBundleIdentifier: String { get }

  func requestReadAuthorization() async throws
  func fetchSamples(from startDate: Date, to endDate: Date) async throws
    -> [HealthCoverageSampleRecord]
  func requestRestingHeartRateWriteAuthorization() async throws
  func fetchRestingHeartRateSamples(
    from startDate: Date,
    to endDate: Date
  ) async throws -> [RestingHeartRateHealthSample]
  func saveRestingHeartRate(_ candidate: RestingHeartRateSyncCandidate) async throws
  func deleteRestingHeartRate(syncIdentifier: String) async throws
}
