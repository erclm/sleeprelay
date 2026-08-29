import Foundation
import SleepRelayCore

@MainActor
protocol HealthCoverageProviding {
  var isHealthDataAvailable: Bool { get }

  func requestReadAuthorization() async throws
  func fetchSamples(from startDate: Date, to endDate: Date) async throws
    -> [HealthCoverageSampleRecord]
}
