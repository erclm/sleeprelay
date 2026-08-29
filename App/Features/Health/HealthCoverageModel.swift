import Foundation
import Observation
import SleepRelayCore

enum HealthCoverageState: Equatable {
  case unavailable
  case notRequested
  case loading
  case loaded(lastUpdated: Date, coverage: [HealthMetricCoverage])
  case failed(message: String)
}

@MainActor
@Observable
final class HealthCoverageModel {
  var lookbackDays = 7
  private(set) var state: HealthCoverageState

  private let provider: any HealthCoverageProviding

  init(
    provider: any HealthCoverageProviding,
    initialState: HealthCoverageState? = nil
  ) {
    self.provider = provider
    state = initialState ?? (provider.isHealthDataAvailable ? .notRequested : .unavailable)
  }

  static func live() -> HealthCoverageModel {
    HealthCoverageModel(provider: HealthKitCoverageProvider())
  }

  static var preview: HealthCoverageModel {
    let samples = FixtureHealthCoverageProvider.samples
    return HealthCoverageModel(
      provider: FixtureHealthCoverageProvider(samples: samples),
      initialState: .loaded(
        lastUpdated: Date(timeIntervalSince1970: 1_777_625_600),
        coverage: HealthCoverageSummarizer.summarize(samples)
      )
    )
  }

  static var emptyPreview: HealthCoverageModel {
    HealthCoverageModel(
      provider: FixtureHealthCoverageProvider(samples: []),
      initialState: .loaded(
        lastUpdated: Date(timeIntervalSince1970: 1_777_625_600),
        coverage: HealthCoverageSummarizer.summarize([])
      )
    )
  }

  func requestReadAccessAndLoad() async {
    guard provider.isHealthDataAvailable else {
      state = .unavailable
      return
    }

    state = .loading
    do {
      try await provider.requestReadAuthorization()
      try await loadCoverage()
    } catch is CancellationError {
      state = .notRequested
    } catch {
      state = .failed(message: message(for: error))
    }
  }

  func refresh() async {
    guard provider.isHealthDataAvailable else {
      state = .unavailable
      return
    }

    state = .loading
    do {
      try await loadCoverage()
    } catch is CancellationError {
      return
    } catch {
      state = .failed(message: message(for: error))
    }
  }

  private func loadCoverage(now: Date = .now) async throws {
    let startDate =
      Calendar.autoupdatingCurrent.date(
        byAdding: .day,
        value: -lookbackDays,
        to: now
      ) ?? now
    let samples = try await provider.fetchSamples(from: startDate, to: now)
    state = .loaded(
      lastUpdated: now,
      coverage: HealthCoverageSummarizer.summarize(samples)
    )
  }

  private func message(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return "The read-only HealthKit audit failed. Try again later."
  }
}
