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

struct RestingHeartRateBackfillItem: Equatable, Identifiable {
  let candidate: RestingHeartRateSyncCandidate
  let decision: RestingHeartRateSyncDecision

  var id: String { candidate.syncIdentifier }
}

struct RestingHeartRateBackfillAudit: Equatable {
  let sourceNightCount: Int
  let invalidNightCount: Int
  let items: [RestingHeartRateBackfillItem]

  var readyCount: Int { count { $0.decision == .ready } }
  var alreadyWrittenCount: Int { count { $0.decision == .alreadyWritten } }
  var eightAlreadyPresentCount: Int { count { $0.decision == .eightAlreadyPresent } }
  var otherSourceCount: Int {
    count {
      if case .otherSourcesPresent = $0.decision { return true }
      return false
    }
  }

  private func count(_ predicate: (RestingHeartRateBackfillItem) -> Bool) -> Int {
    items.lazy.filter(predicate).count
  }
}

struct RestingHeartRateBackfillResult: Equatable {
  let addedCount: Int
  let failedCount: Int
  let skippedCount: Int
}

enum RestingHeartRateBackfillState: Equatable {
  case idle
  case auditing
  case ready(RestingHeartRateBackfillAudit)
  case writing(completed: Int, total: Int)
  case completed(
    audit: RestingHeartRateBackfillAudit,
    result: RestingHeartRateBackfillResult
  )
  case failed(message: String)
}

@MainActor
@Observable
final class HealthCoverageModel {
  var lookbackDays = 7
  var isAutomaticSyncEnabled: Bool {
    didSet {
      preferences.set(isAutomaticSyncEnabled, forKey: Self.automaticSyncEnabledKey)
    }
  }
  private(set) var state: HealthCoverageState
  private(set) var restingHeartRateStates: [String: RestingHeartRateSyncState] = [:]
  private(set) var backfillState: RestingHeartRateBackfillState = .idle
  private(set) var lastAutomaticSyncDate: Date?
  private(set) var lastAutomaticSyncAddedCount = 0

  private let provider: any HealthCoverageProviding
  private let preferences: UserDefaults
  private var isAutomaticSyncInProgress = false

  private static let automaticSyncEnabledKey = "app.sleeprelay.automaticRHRSyncEnabled"

  init(
    provider: any HealthCoverageProviding,
    preferences: UserDefaults = .standard,
    initialState: HealthCoverageState? = nil
  ) {
    self.provider = provider
    self.preferences = preferences
    if preferences.object(forKey: Self.automaticSyncEnabledKey) == nil {
      isAutomaticSyncEnabled = true
    } else {
      isAutomaticSyncEnabled = preferences.bool(forKey: Self.automaticSyncEnabledKey)
    }
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

  func auditBackfill(
    candidates: [RestingHeartRateSyncCandidate],
    sourceNightCount: Int,
    invalidNightCount: Int
  ) async {
    guard provider.isHealthDataAvailable else {
      backfillState = .failed(message: "Health data is not available on this device.")
      return
    }

    backfillState = .auditing
    do {
      try await provider.requestReadAuthorization()
      let audit = try await makeBackfillAudit(
        candidates: candidates,
        sourceNightCount: sourceNightCount,
        invalidNightCount: invalidNightCount
      )
      apply(audit)
      backfillState = .ready(audit)
    } catch is CancellationError {
      backfillState = .idle
    } catch {
      backfillState = .failed(message: writeMessage(for: error))
    }
  }

  func performBackfill() async {
    let initialAudit: RestingHeartRateBackfillAudit
    switch backfillState {
    case .ready(let audit), .completed(let audit, _):
      initialAudit = audit
    default:
      return
    }

    do {
      try await provider.requestRestingHeartRateWriteAuthorization()
      let currentAudit = try await makeBackfillAudit(
        candidates: initialAudit.items.map(\.candidate),
        sourceNightCount: initialAudit.sourceNightCount,
        invalidNightCount: initialAudit.invalidNightCount
      )
      let candidates = currentAudit.items.compactMap { item in
        item.decision == .ready ? item.candidate : nil
      }

      var addedCount = 0
      var failedCount = 0
      backfillState = .writing(completed: 0, total: candidates.count)
      for (index, candidate) in candidates.enumerated() {
        try Task.checkCancellation()
        do {
          try await provider.saveRestingHeartRate(candidate)
          addedCount += 1
        } catch {
          failedCount += 1
        }
        backfillState = .writing(completed: index + 1, total: candidates.count)
      }

      let refreshedAudit = try await makeBackfillAudit(
        candidates: initialAudit.items.map(\.candidate),
        sourceNightCount: initialAudit.sourceNightCount,
        invalidNightCount: initialAudit.invalidNightCount
      )
      apply(refreshedAudit)
      let result = RestingHeartRateBackfillResult(
        addedCount: addedCount,
        failedCount: failedCount,
        skippedCount: initialAudit.items.count - candidates.count
      )
      backfillState = .completed(audit: refreshedAudit, result: result)
    } catch is CancellationError {
      backfillState = .ready(initialAudit)
    } catch {
      backfillState = .failed(message: writeMessage(for: error))
    }
  }

  /// Runs only after the user has already granted RHR write access. It never
  /// presents Health authorization UI during foreground refresh.
  func automaticSyncIfEligible(nights: [EightSleepNight]) async {
    guard
      isAutomaticSyncEnabled,
      provider.restingHeartRateWriteAuthorizationStatus == .authorized,
      !isAutomaticSyncInProgress
    else { return }

    isAutomaticSyncInProgress = true
    defer { isAutomaticSyncInProgress = false }
    do {
      let audit = try await makeBackfillAudit(nights: nights)
      let candidates = audit.items.compactMap { item in
        item.decision == .ready ? item.candidate : nil
      }
      var addedCount = 0
      for candidate in candidates {
        do {
          try await provider.saveRestingHeartRate(candidate)
          addedCount += 1
        } catch {
          continue
        }
      }
      lastAutomaticSyncDate = .now
      lastAutomaticSyncAddedCount = addedCount
      if addedCount > 0 {
        let refreshedAudit = try await makeBackfillAudit(nights: nights)
        apply(refreshedAudit)
      }
    } catch is CancellationError {
      return
    } catch {
      return
    }
  }

  private func makeBackfillAudit(
    nights: [EightSleepNight]
  ) async throws -> RestingHeartRateBackfillAudit {
    var candidatesBySyncIdentifier: [String: RestingHeartRateSyncCandidate] = [:]
    for night in nights {
      guard let candidate = night.restingHeartRateSyncCandidate else { continue }
      candidatesBySyncIdentifier[candidate.syncIdentifier] = candidate
    }
    let candidates = candidatesBySyncIdentifier.values.sorted { $0.day > $1.day }
    return try await makeBackfillAudit(
      candidates: candidates,
      sourceNightCount: nights.count,
      invalidNightCount: max(nights.count - candidates.count, 0)
    )
  }

  private func makeBackfillAudit(
    candidates: [RestingHeartRateSyncCandidate],
    sourceNightCount: Int,
    invalidNightCount: Int
  ) async throws -> RestingHeartRateBackfillAudit {
    guard
      let earliest = candidates.map(\.startDate).min(),
      let latest = candidates.map(\.endDate).max()
    else {
      return RestingHeartRateBackfillAudit(
        sourceNightCount: sourceNightCount,
        invalidNightCount: invalidNightCount,
        items: []
      )
    }

    let existingSamples = try await provider.fetchRestingHeartRateSamples(
      from: earliest,
      to: latest
    )
    let items = candidates.map { candidate in
      RestingHeartRateBackfillItem(
        candidate: candidate,
        decision: RestingHeartRateSyncPolicy.decision(
          for: candidate,
          existingSamples: existingSamples,
          sleepRelayBundleIdentifier: provider.sleepRelayBundleIdentifier
        )
      )
    }
    return RestingHeartRateBackfillAudit(
      sourceNightCount: sourceNightCount,
      invalidNightCount: invalidNightCount,
      items: items
    )
  }

  private func apply(_ audit: RestingHeartRateBackfillAudit) {
    for item in audit.items {
      restingHeartRateStates[item.candidate.id] = .loaded(
        candidate: item.candidate,
        decision: item.decision
      )
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
