import Foundation
import Testing

@testable import SleepRelayCore

struct HealthCoverageTests {
  @Test
  func groupsSamplesByMetricSleepNightAndSource() throws {
    let eight = HealthDataSource(
      name: "Eight Sleep", bundleIdentifier: "example.eight", version: "1")
    let watch = HealthDataSource(
      name: "Apple Watch", bundleIdentifier: "com.apple.health", version: nil)
    let records = [
      HealthCoverageSampleRecord(
        metric: .sleepAnalysis,
        source: eight,
        startDate: try date("2026-08-29T01:00:00Z"),
        endDate: try date("2026-08-29T02:00:00Z")
      ),
      HealthCoverageSampleRecord(
        metric: .sleepAnalysis,
        source: eight,
        startDate: try date("2026-08-29T02:00:00Z"),
        endDate: try date("2026-08-29T03:00:00Z")
      ),
      HealthCoverageSampleRecord(
        metric: .sleepAnalysis,
        source: watch,
        startDate: try date("2026-08-28T23:00:00Z"),
        endDate: try date("2026-08-29T01:00:00Z")
      ),
    ]

    let coverage = HealthCoverageSummarizer.summarize(
      records,
      metrics: [.sleepAnalysis, .restingHeartRate],
      calendar: utcCalendar
    )
    let sleep = try #require(coverage.first)
    let expectedNight = try date("2026-08-28T00:00:00Z")

    #expect(sleep.sampleCount == 3)
    #expect(sleep.sources.count == 2)
    #expect(sleep.nights.count == 2)
    #expect(sleep.sources.first(where: { $0.source == eight })?.sampleCount == 2)
    #expect(sleep.sources.first(where: { $0.source == eight })?.nightCount == 1)
    #expect(sleep.nights.allSatisfy { $0.nightDate == expectedNight })
    #expect(coverage[1].hasVisibleSamples == false)
  }

  @Test
  func noonBoundaryKeepsOvernightSamplesWithTheStartingSleepDate() throws {
    let source = HealthDataSource(
      name: "Source", bundleIdentifier: "example.source", version: nil)
    let records = [
      HealthCoverageSampleRecord(
        metric: .heartRate,
        source: source,
        startDate: try date("2026-08-29T11:59:00Z"),
        endDate: try date("2026-08-29T12:00:00Z")
      ),
      HealthCoverageSampleRecord(
        metric: .heartRate,
        source: source,
        startDate: try date("2026-08-29T12:00:00Z"),
        endDate: try date("2026-08-29T12:01:00Z")
      ),
    ]

    let coverage = HealthCoverageSummarizer.summarize(
      records,
      metrics: [.heartRate],
      calendar: utcCalendar
    )
    let nights = try #require(coverage.first?.nights)
    let august29 = try date("2026-08-29T00:00:00Z")
    let august28 = try date("2026-08-28T00:00:00Z")

    #expect(nights.count == 2)
    #expect(nights[0].nightDate == august29)
    #expect(nights[1].nightDate == august28)
  }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func date(_ value: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: value))
  }
}
