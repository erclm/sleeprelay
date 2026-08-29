import Foundation

public enum HealthMetricIdentifier: String, CaseIterable, Hashable, Identifiable, Sendable {
  case sleepAnalysis
  case heartRate
  case respiratoryRate
  case restingHeartRate
  case heartRateVariabilitySDNN

  public var id: String { rawValue }
}

public struct HealthDataSource: Hashable, Identifiable, Sendable {
  public let name: String
  public let bundleIdentifier: String
  public let version: String?

  public var id: String {
    [bundleIdentifier, name, version ?? ""].joined(separator: "|")
  }

  public init(name: String, bundleIdentifier: String, version: String?) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
    self.version = version
  }
}

public struct HealthCoverageSampleRecord: Hashable, Sendable {
  public let metric: HealthMetricIdentifier
  public let source: HealthDataSource
  public let startDate: Date
  public let endDate: Date

  public init(
    metric: HealthMetricIdentifier,
    source: HealthDataSource,
    startDate: Date,
    endDate: Date
  ) {
    self.metric = metric
    self.source = source
    self.startDate = startDate
    self.endDate = endDate
  }
}

public struct HealthSourceCoverage: Hashable, Identifiable, Sendable {
  public let source: HealthDataSource
  public let sampleCount: Int
  public let nightCount: Int
  public let firstSampleStart: Date
  public let lastSampleEnd: Date

  public var id: String { source.id }

  public init(
    source: HealthDataSource,
    sampleCount: Int,
    nightCount: Int,
    firstSampleStart: Date,
    lastSampleEnd: Date
  ) {
    self.source = source
    self.sampleCount = sampleCount
    self.nightCount = nightCount
    self.firstSampleStart = firstSampleStart
    self.lastSampleEnd = lastSampleEnd
  }
}

public struct HealthNightCoverage: Hashable, Identifiable, Sendable {
  public let metric: HealthMetricIdentifier
  public let nightDate: Date
  public let source: HealthDataSource
  public let sampleCount: Int
  public let firstSampleStart: Date
  public let lastSampleEnd: Date

  public var id: String {
    "\(metric.rawValue)|\(Int(nightDate.timeIntervalSince1970))|\(source.id)"
  }

  public init(
    metric: HealthMetricIdentifier,
    nightDate: Date,
    source: HealthDataSource,
    sampleCount: Int,
    firstSampleStart: Date,
    lastSampleEnd: Date
  ) {
    self.metric = metric
    self.nightDate = nightDate
    self.source = source
    self.sampleCount = sampleCount
    self.firstSampleStart = firstSampleStart
    self.lastSampleEnd = lastSampleEnd
  }
}

public struct HealthMetricCoverage: Hashable, Identifiable, Sendable {
  public let metric: HealthMetricIdentifier
  public let sources: [HealthSourceCoverage]
  public let nights: [HealthNightCoverage]

  public var id: String { metric.id }
  public var sampleCount: Int { sources.reduce(0) { $0 + $1.sampleCount } }
  public var hasVisibleSamples: Bool { sampleCount > 0 }

  public init(
    metric: HealthMetricIdentifier,
    sources: [HealthSourceCoverage],
    nights: [HealthNightCoverage]
  ) {
    self.metric = metric
    self.sources = sources
    self.nights = nights
  }
}

public enum HealthCoverageSummarizer {
  public static func summarize(
    _ records: [HealthCoverageSampleRecord],
    metrics: [HealthMetricIdentifier] = HealthMetricIdentifier.allCases,
    calendar inputCalendar: Calendar = .autoupdatingCurrent
  ) -> [HealthMetricCoverage] {
    var calendar = inputCalendar

    return metrics.map { metric in
      let metricRecords = records.filter { $0.metric == metric }
      let nightGroups = Dictionary(grouping: metricRecords) { record in
        NightSourceKey(
          nightDate: nightDate(for: record.startDate, calendar: &calendar),
          source: record.source
        )
      }

      let nights = nightGroups.map { key, samples in
        HealthNightCoverage(
          metric: metric,
          nightDate: key.nightDate,
          source: key.source,
          sampleCount: samples.count,
          firstSampleStart: samples.map(\.startDate).min() ?? key.nightDate,
          lastSampleEnd: samples.map(\.endDate).max() ?? key.nightDate
        )
      }
      .sorted {
        if $0.nightDate != $1.nightDate { return $0.nightDate > $1.nightDate }
        return $0.source.name.localizedCaseInsensitiveCompare($1.source.name) == .orderedAscending
      }

      let sourceGroups = Dictionary(grouping: metricRecords, by: \.source)
      let sources = sourceGroups.map { source, samples in
        let sourceNights = Set(
          samples.map { nightDate(for: $0.startDate, calendar: &calendar) })
        return HealthSourceCoverage(
          source: source,
          sampleCount: samples.count,
          nightCount: sourceNights.count,
          firstSampleStart: samples.map(\.startDate).min() ?? .distantPast,
          lastSampleEnd: samples.map(\.endDate).max() ?? .distantPast
        )
      }
      .sorted {
        $0.source.name.localizedCaseInsensitiveCompare($1.source.name) == .orderedAscending
      }

      return HealthMetricCoverage(metric: metric, sources: sources, nights: nights)
    }
  }

  private static func nightDate(for date: Date, calendar: inout Calendar) -> Date {
    let shifted = calendar.date(byAdding: .hour, value: -12, to: date) ?? date
    return calendar.startOfDay(for: shifted)
  }
}

private struct NightSourceKey: Hashable {
  let nightDate: Date
  let source: HealthDataSource
}
