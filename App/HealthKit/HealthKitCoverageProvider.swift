import Foundation
import HealthKit
import SleepRelayCore

enum HealthKitCoverageError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "Health data is not available on this device."
    }
  }
}

@MainActor
final class HealthKitCoverageProvider: HealthCoverageProviding {
  private let healthStore: HKHealthStore

  var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
  var sleepRelayBundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "app.sleeprelay.ios"
  }

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func requestReadAuthorization() async throws {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    let readTypes = Set(Self.metricTypes.map { $0.sampleType as HKObjectType })
    try await healthStore.requestAuthorization(
      toShare: Set<HKSampleType>(),
      read: readTypes
    )
  }

  func fetchSamples(from startDate: Date, to endDate: Date) async throws
    -> [HealthCoverageSampleRecord]
  {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    let datePredicate = HKQuery.predicateForSamples(
      withStart: startDate,
      end: endDate,
      options: [.strictStartDate]
    )
    var records: [HealthCoverageSampleRecord] = []

    for definition in Self.metricTypes {
      let descriptor = HKSampleQueryDescriptor<HKSample>(
        predicates: [.sample(type: definition.sampleType, predicate: datePredicate)],
        sortDescriptors: [SortDescriptor(\HKSample.startDate, order: .forward)]
      )
      let samples = try await descriptor.result(for: healthStore)
      records.append(
        contentsOf: samples.map { sample in
          HealthCoverageSampleRecord(
            metric: definition.metric,
            source: HealthDataSource(
              name: sample.sourceRevision.source.name,
              bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
              version: sample.sourceRevision.version
            ),
            startDate: sample.startDate,
            endDate: sample.endDate
          )
        })
    }

    return records
  }

  func requestRestingHeartRateWriteAuthorization() async throws {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    try await healthStore.requestAuthorization(
      toShare: [Self.restingHeartRateType],
      read: [Self.restingHeartRateType]
    )
  }

  func fetchRestingHeartRateSamples(
    from startDate: Date,
    to endDate: Date
  ) async throws -> [RestingHeartRateHealthSample] {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    let predicate = HKQuery.predicateForSamples(
      withStart: startDate,
      end: endDate,
      options: []
    )
    let descriptor = HKSampleQueryDescriptor<HKSample>(
      predicates: [.sample(type: Self.restingHeartRateType, predicate: predicate)],
      sortDescriptors: [SortDescriptor(\HKSample.startDate, order: .forward)]
    )
    let samples = try await descriptor.result(for: healthStore)

    return samples.compactMap { sample in
      guard let quantitySample = sample as? HKQuantitySample else { return nil }
      return RestingHeartRateHealthSample(
        source: HealthDataSource(
          name: sample.sourceRevision.source.name,
          bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
          version: sample.sourceRevision.version
        ),
        valueBPM: quantitySample.quantity.doubleValue(for: Self.beatsPerMinute),
        startDate: sample.startDate,
        endDate: sample.endDate,
        syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String
      )
    }
  }

  func saveRestingHeartRate(_ candidate: RestingHeartRateSyncCandidate) async throws {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    let sample = HKQuantitySample(
      type: Self.restingHeartRateType,
      quantity: HKQuantity(unit: Self.beatsPerMinute, doubleValue: candidate.valueBPM),
      start: candidate.endDate,
      end: candidate.endDate,
      metadata: [
        HKMetadataKeySyncIdentifier: candidate.syncIdentifier,
        HKMetadataKeySyncVersion: RestingHeartRateSyncCandidate.syncVersion,
        HKMetadataKeyAlgorithmVersion: RestingHeartRateSyncCandidate.algorithmVersion,
        "app.sleeprelay.eightSleepDay": candidate.day,
      ]
    )
    try await healthStore.save(sample)
  }

  func deleteRestingHeartRate(syncIdentifier: String) async throws {
    guard isHealthDataAvailable else { throw HealthKitCoverageError.unavailable }

    let predicate = HKQuery.predicateForObjects(
      withMetadataKey: HKMetadataKeySyncIdentifier,
      allowedValues: [syncIdentifier]
    )
    let descriptor = HKSampleQueryDescriptor<HKSample>(
      predicates: [.sample(type: Self.restingHeartRateType, predicate: predicate)],
      sortDescriptors: []
    )
    let samples = try await descriptor.result(for: healthStore)
    let sleepRelaySamples = samples.filter {
      $0.sourceRevision.source.bundleIdentifier == sleepRelayBundleIdentifier
    }
    guard !sleepRelaySamples.isEmpty else { return }
    try await healthStore.delete(sleepRelaySamples)
  }

  private static let metricTypes: [(metric: HealthMetricIdentifier, sampleType: HKSampleType)] = [
    (.sleepAnalysis, categoryType(.sleepAnalysis)),
    (.heartRate, quantityType(.heartRate)),
    (.respiratoryRate, quantityType(.respiratoryRate)),
    (.restingHeartRate, quantityType(.restingHeartRate)),
    (.heartRateVariabilitySDNN, quantityType(.heartRateVariabilitySDNN)),
  ]
  private static let restingHeartRateType = quantityType(.restingHeartRate)
  private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

  private static func categoryType(_ identifier: HKCategoryTypeIdentifier) -> HKCategoryType {
    guard let type = HKObjectType.categoryType(forIdentifier: identifier) else {
      preconditionFailure("HealthKit category type is unavailable: \(identifier.rawValue)")
    }
    return type
  }

  private static func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType {
    guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
      preconditionFailure("HealthKit quantity type is unavailable: \(identifier.rawValue)")
    }
    return type
  }
}
