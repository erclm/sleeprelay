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

enum RestingHeartRateSyncState: Equatable {
  case idle
  case loading
  case loaded(
    candidate: RestingHeartRateSyncCandidate,
    decision: RestingHeartRateSyncDecision
  )
  case writing(candidate: RestingHeartRateSyncCandidate)
  case deleting(candidate: RestingHeartRateSyncCandidate)
  case unavailable(message: String)
  case failed(message: String)
}

@MainActor
@Observable
final class HealthCoverageModel {
  var lookbackDays = 7
  private(set) var state: HealthCoverageState
  private(set) var restingHeartRateStates: [String: RestingHeartRateSyncState] = [:]

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

  func restingHeartRateState(for night: EightSleepNight) -> RestingHeartRateSyncState {
    restingHeartRateStates[night.id] ?? .idle
  }

  func loadRestingHeartRateStatus(for night: EightSleepNight) async {
    guard provider.isHealthDataAvailable else {
      restingHeartRateStates[night.id] = .unavailable(
        message: "Health data is not available on this device."
      )
      return
    }
    guard let candidate = night.restingHeartRateSyncCandidate else {
      restingHeartRateStates[night.id] = .unavailable(
        message: "This night does not contain a validated Eight reported RHR and sleep interval."
      )
      return
    }

    restingHeartRateStates[night.id] = .loading
    do {
      let decision = try await restingHeartRateDecision(for: candidate)
      restingHeartRateStates[night.id] = .loaded(candidate: candidate, decision: decision)
    } catch is CancellationError {
      restingHeartRateStates[night.id] = .idle
    } catch {
      restingHeartRateStates[night.id] = .failed(message: writeMessage(for: error))
    }
  }

  func writeRestingHeartRate(
    for night: EightSleepNight,
    allowAdditionalSource: Bool
  ) async {
    guard let candidate = night.restingHeartRateSyncCandidate else {
      restingHeartRateStates[night.id] = .unavailable(
        message: "This night does not contain a validated Eight reported RHR and sleep interval."
      )
      return
    }

    restingHeartRateStates[night.id] = .writing(candidate: candidate)
    do {
      try await provider.requestRestingHeartRateWriteAuthorization()
      let decision = try await restingHeartRateDecision(for: candidate)
      switch decision {
      case .ready:
        break
      case .otherSourcesPresent where allowAdditionalSource:
        break
      case .otherSourcesPresent, .eightAlreadyPresent, .alreadyWritten:
        restingHeartRateStates[night.id] = .loaded(
          candidate: candidate,
          decision: decision
        )
        return
      }

      try await provider.saveRestingHeartRate(candidate)
      let refreshedDecision = try await restingHeartRateDecision(for: candidate)
      restingHeartRateStates[night.id] = .loaded(
        candidate: candidate,
        decision: refreshedDecision
      )
    } catch is CancellationError {
      await loadRestingHeartRateStatus(for: night)
    } catch {
      restingHeartRateStates[night.id] = .failed(message: writeMessage(for: error))
    }
  }

  func deleteRestingHeartRate(for night: EightSleepNight) async {
    guard let candidate = night.restingHeartRateSyncCandidate else { return }

    restingHeartRateStates[night.id] = .deleting(candidate: candidate)
    do {
      try await provider.deleteRestingHeartRate(syncIdentifier: candidate.syncIdentifier)
      let refreshedDecision = try await restingHeartRateDecision(for: candidate)
      restingHeartRateStates[night.id] = .loaded(
        candidate: candidate,
        decision: refreshedDecision
      )
    } catch is CancellationError {
      await loadRestingHeartRateStatus(for: night)
    } catch {
      restingHeartRateStates[night.id] = .failed(message: writeMessage(for: error))
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

  private func restingHeartRateDecision(
    for candidate: RestingHeartRateSyncCandidate
  ) async throws -> RestingHeartRateSyncDecision {
    let existingSamples = try await provider.fetchRestingHeartRateSamples(
      from: candidate.startDate,
      to: candidate.endDate
    )
    return RestingHeartRateSyncPolicy.decision(
      for: candidate,
      existingSamples: existingSamples,
      sleepRelayBundleIdentifier: provider.sleepRelayBundleIdentifier
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

  private func writeMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return "The resting heart rate change could not be completed. Check Health permissions and try again."
  }
}
