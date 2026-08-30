import Foundation

public enum BackgroundRefreshSchedule {
  public static func nextDate(
    after date: Date,
    recentWakeDates: [Date],
    calendar sourceCalendar: Calendar = .autoupdatingCurrent
  ) -> Date {
    var calendar = sourceCalendar
    calendar.timeZone = sourceCalendar.timeZone

    let targetMinute = targetMinuteOfDay(
      recentWakeDates: recentWakeDates,
      calendar: calendar
    )
    let hour = targetMinute / 60
    let minute = targetMinute % 60
    let candidate = calendar.date(
      bySettingHour: hour,
      minute: minute,
      second: 0,
      of: date
    ) ?? date.addingTimeInterval(6 * 60 * 60)

    if candidate > date { return candidate }
    return calendar.date(byAdding: .day, value: 1, to: candidate)
      ?? date.addingTimeInterval(24 * 60 * 60)
  }

  private static let minimumWakeSampleCount = 3
  private static let postWakeDelayMinutes = 90
  private static let fallbackMinuteOfDay = 10 * 60
  private static let sleepDayBoundaryMinute = 4 * 60

  private static func targetMinuteOfDay(
    recentWakeDates: [Date],
    calendar: Calendar
  ) -> Int {
    guard recentWakeDates.count >= minimumWakeSampleCount else {
      return fallbackMinuteOfDay
    }

    let wakeMinutes = recentWakeDates.map { date in
      let components = calendar.dateComponents([.hour, .minute], from: date)
      let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
      // Treat wake times after midnight but before the 4 a.m. sleep-day
      // boundary as the continuation of the previous evening. This keeps the
      // median stable for schedules clustered around midnight.
      return minuteOfDay < sleepDayBoundaryMinute ? minuteOfDay + 24 * 60 : minuteOfDay
    }.sorted()

    let medianWakeMinute = wakeMinutes[wakeMinutes.count / 2]
    return (medianWakeMinute + postWakeDelayMinutes) % (24 * 60)
  }
}
