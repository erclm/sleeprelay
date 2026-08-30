import Foundation

public struct RestingHeartRateSyncCandidate: Hashable, Identifiable, Sendable {
  public static let algorithmVersion = "eight-reported-rhr-v1"
  public static let syncVersion = 1

  public let id: String
  public let day: String
  public let valueBPM: Double
  public let startDate: Date
  public let endDate: Date

  public var syncIdentifier: String {
    "app.sleeprelay.rhr.\(day)"
  }

  public init(
    id: String,
    day: String,
    valueBPM: Double,
    startDate: Date,
    endDate: Date
  ) {
    self.id = id
    self.day = day
    self.valueBPM = valueBPM
    self.startDate = startDate
    self.endDate = endDate
  }
}

extension EightSleepNight {
  public var restingHeartRateSyncCandidate: RestingHeartRateSyncCandidate? {
    guard
      !isProcessing,
      let valueBPM = discoveredRestingHeartRateBPM,
      valueBPM.isFinite,
      (20 ... 250).contains(valueBPM),
      let startDate = presenceStart,
      let endDate = presenceEnd,
      startDate < endDate
    else { return nil }

    return RestingHeartRateSyncCandidate(
      id: id,
      day: day,
      valueBPM: valueBPM,
      startDate: startDate,
      endDate: endDate
    )
  }
}

public struct RestingHeartRateHealthSample: Hashable, Sendable {
  public let source: HealthDataSource
  public let valueBPM: Double
  public let startDate: Date
  public let endDate: Date
  public let syncIdentifier: String?

  public init(
    source: HealthDataSource,
    valueBPM: Double,
    startDate: Date,
    endDate: Date,
    syncIdentifier: String?
  ) {
    self.source = source
    self.valueBPM = valueBPM
    self.startDate = startDate
    self.endDate = endDate
    self.syncIdentifier = syncIdentifier
  }
}

public enum RestingHeartRateSyncDecision: Equatable, Sendable {
  case ready
  case otherSourcesPresent([String])
  case eightAlreadyPresent
  case alreadyWritten
}

public enum RestingHeartRateSyncPolicy {
  public static func decision(
    for candidate: RestingHeartRateSyncCandidate,
    existingSamples: [RestingHeartRateHealthSample],
    sleepRelayBundleIdentifier: String
  ) -> RestingHeartRateSyncDecision {
    if existingSamples.contains(where: { sample in
      sample.syncIdentifier == candidate.syncIdentifier
        || (sample.source.bundleIdentifier == sleepRelayBundleIdentifier
          && overlaps(sample, candidate))
    }) {
      return .alreadyWritten
    }

    let overlappingSamples = existingSamples.filter { overlaps($0, candidate) }
    if overlappingSamples.contains(where: { sample in
      sample.source.bundleIdentifier.lowercased().contains("eightsleep")
    }) {
      return .eightAlreadyPresent
    }

    let otherSources = Set(
      overlappingSamples
        .filter { $0.source.bundleIdentifier != sleepRelayBundleIdentifier }
        .map { $0.source.name }
    )
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    if !otherSources.isEmpty {
      return .otherSourcesPresent(otherSources)
    }
    return .ready
  }

  private static func overlaps(
    _ sample: RestingHeartRateHealthSample,
    _ candidate: RestingHeartRateSyncCandidate
  ) -> Bool {
    sample.startDate <= candidate.endDate && sample.endDate >= candidate.startDate
  }
}
