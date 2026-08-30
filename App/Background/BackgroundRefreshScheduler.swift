import BackgroundTasks
import Foundation

@MainActor
protocol BackgroundRefreshScheduling {
  func scheduleNextRefresh(after date: Date)
  func cancel()
}

@MainActor
struct BackgroundRefreshScheduler: BackgroundRefreshScheduling {
  static let identifier = "app.sleeprelay.ios.background-refresh"

  private let scheduler: BGTaskScheduler

  init(scheduler: BGTaskScheduler = .shared) {
    self.scheduler = scheduler
  }

  func scheduleNextRefresh(after date: Date) {
    let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
    request.earliestBeginDate = Self.nextEarliestRefreshDate(after: date)

    scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
    try? scheduler.submit(request)
  }

  func cancel() {
    scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
  }

  static func nextEarliestRefreshDate(
    after date: Date,
    calendar sourceCalendar: Calendar = .autoupdatingCurrent
  ) -> Date {
    var calendar = sourceCalendar
    calendar.timeZone = .autoupdatingCurrent

    let startOfDay = calendar.startOfDay(for: date)
    let todayRefresh = calendar.date(
      bySettingHour: 5,
      minute: 0,
      second: 0,
      of: startOfDay
    ) ?? date.addingTimeInterval(6 * 60 * 60)
    if todayRefresh > date { return todayRefresh }

    let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
    return calendar.date(
      bySettingHour: 5,
      minute: 0,
      second: 0,
      of: nextDay
    ) ?? date.addingTimeInterval(24 * 60 * 60)
  }
}

@MainActor
struct NoopBackgroundRefreshScheduler: BackgroundRefreshScheduling {
  func scheduleNextRefresh(after _: Date) {}
  func cancel() {}
}
