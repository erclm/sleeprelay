import BackgroundTasks
import Foundation
import SleepRelayCore

@MainActor
protocol BackgroundRefreshScheduling {
  func scheduleNextRefresh(after date: Date, recentWakeDates: [Date])
  func cancel()
}

@MainActor
struct BackgroundRefreshScheduler: BackgroundRefreshScheduling {
  static let identifier = "app.sleeprelay.ios.background-refresh"

  private let scheduler: BGTaskScheduler

  init(scheduler: BGTaskScheduler = .shared) {
    self.scheduler = scheduler
  }

  func scheduleNextRefresh(after date: Date, recentWakeDates: [Date]) {
    let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
    request.earliestBeginDate = BackgroundRefreshSchedule.nextDate(
      after: date,
      recentWakeDates: recentWakeDates
    )

    scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
    try? scheduler.submit(request)
  }

  func cancel() {
    scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
  }
}

@MainActor
struct NoopBackgroundRefreshScheduler: BackgroundRefreshScheduling {
  func scheduleNextRefresh(after _: Date, recentWakeDates _: [Date]) {}
  func cancel() {}
}
