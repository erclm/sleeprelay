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

  private static let metricTypes: [(metric: HealthMetricIdentifier, sampleType: HKSampleType)] = [
    (.sleepAnalysis, categoryType(.sleepAnalysis)),
    (.heartRate, quantityType(.heartRate)),
    (.respiratoryRate, quantityType(.respiratoryRate)),
    (.restingHeartRate, quantityType(.restingHeartRate)),
    (.heartRateVariabilitySDNN, quantityType(.heartRateVariabilitySDNN)),
  ]

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
