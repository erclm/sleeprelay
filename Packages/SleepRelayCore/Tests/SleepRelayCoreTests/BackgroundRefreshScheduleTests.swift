import Foundation
import Testing

@testable import SleepRelayCore

struct BackgroundRefreshScheduleTests {
  @Test
  func fallsBackToTenAMWithoutEnoughWakeHistory() throws {
    let now = try makeDate(day: 1, hour: 8)

    let scheduled = BackgroundRefreshSchedule.nextDate(
      after: now,
      recentWakeDates: [
        try makeDate(day: 1, hour: 7),
        try makeDate(day: 2, hour: 7),
      ],
      calendar: calendar
    )

    #expect(scheduled == (try makeDate(day: 1, hour: 10)))
  }

  @Test
  func advancesFallbackToTheNextDayWhenTodayHasPassed() throws {
    let now = try makeDate(day: 1, hour: 11)

    let scheduled = BackgroundRefreshSchedule.nextDate(
      after: now,
      recentWakeDates: [],
      calendar: calendar
    )

    #expect(scheduled == (try makeDate(day: 2, hour: 10)))
  }

  @Test
  func schedulesNinetyMinutesAfterTheMedianWakeTime() throws {
    let scheduled = BackgroundRefreshSchedule.nextDate(
      after: try makeDate(day: 4, hour: 8),
      recentWakeDates: [
        try makeDate(day: 1, hour: 7, minute: 15),
        try makeDate(day: 2, hour: 9),
        try makeDate(day: 3, hour: 7, minute: 30),
      ],
      calendar: calendar
    )

    #expect(scheduled == (try makeDate(day: 4, hour: 9)))
  }

  @Test
  func handlesWakeTimesClusteredAcrossMidnight() throws {
    let scheduled = BackgroundRefreshSchedule.nextDate(
      after: try makeDate(day: 4, hour: 0, minute: 30),
      recentWakeDates: [
        try makeDate(day: 1, hour: 23, minute: 45),
        try makeDate(day: 2, hour: 0, minute: 15),
        try makeDate(day: 3, hour: 0, minute: 30),
      ],
      calendar: calendar
    )

    #expect(scheduled == (try makeDate(day: 4, hour: 1, minute: 45)))
  }

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }

  private func makeDate(day: Int, hour: Int, minute: Int = 0) throws -> Date {
    try #require(
      calendar.date(
        from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
      )
    )
  }
}
