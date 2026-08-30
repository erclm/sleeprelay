import Foundation
import Observation
import SleepRelayCore

enum AppTab: Hashable {
  case connect
  case data
  case health
  case about
}

enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected(lastUpdated: Date)
  case failed(message: String)
}

enum EightSleepHistoryState: Equatable {
  case idle
  case loading(completedRanges: Int, totalRanges: Int)
  case loaded(
    fetchedAt: Date,
    sourceNightCount: Int,
    invalidNightCount: Int,
    candidates: [RestingHeartRateSyncCandidate]
  )
  case failed(message: String)
}

struct AppConfiguration {
  let eightSleep: EightSleepAPIConfiguration

  var isEightSleepConfigured: Bool { eightSleep.isConfigured }

  static func live(bundle: Bundle = .main) -> AppConfiguration {
    func cleanValue(for key: String) -> String {
      guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
        return ""
      }
      let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return cleaned.contains("$(") ? "" : cleaned
    }

    return AppConfiguration(
      eightSleep: EightSleepAPIConfiguration(
        clientID: cleanValue(for: "EightSleepClientID"),
        clientSecret: cleanValue(for: "EightSleepClientSecret")
      )
    )
  }
}

@MainActor
@Observable
final class AppModel {
  var selectedTab: AppTab = .connect
  private(set) var connectionState: ConnectionState = .disconnected
  private(set) var historyState: EightSleepHistoryState = .idle
  private(set) var nights: [EightSleepNight] = []
  private(set) var isProviderConfigured: Bool
  private(set) var hasSavedCredentials = false
  private(set) var savedEmail: String?
  private(set) var credentialMessage: String?

  private let provider: any EightSleepProviding
  private let credentialStore: any EightSleepCredentialStoring
  private let backgroundRefreshScheduler: any BackgroundRefreshScheduling
  private let preferences: UserDefaults
  private var activeCredentials: EightSleepCredentials?
  private var didLoadCredentials = false
  private var isLifecycleRefreshInProgress = false

  private static let lastAutomaticRefreshKey = "app.sleeprelay.lastAutomaticRefreshSleepDay"
  private static let historyStartYear = 2015

  init(
    provider: any EightSleepProviding,
    credentialStore: any EightSleepCredentialStoring = InMemoryEightSleepCredentialStore(),
    backgroundRefreshScheduler: any BackgroundRefreshScheduling =
      NoopBackgroundRefreshScheduler(),
    preferences: UserDefaults = .standard,
    isProviderConfigured: Bool = true,
    initialNights: [EightSleepNight] = [],
    initialState: ConnectionState = .disconnected
  ) {
    self.provider = provider
    self.credentialStore = credentialStore
    self.backgroundRefreshScheduler = backgroundRefreshScheduler
    self.preferences = preferences
    self.isProviderConfigured = isProviderConfigured
    nights = initialNights
    connectionState = initialState
  }

  static func live(configuration: AppConfiguration = .live()) -> AppModel {
    AppModel(
      provider: EightSleepHTTPClient(configuration: configuration.eightSleep),
      credentialStore: KeychainEightSleepCredentialStore(),
      backgroundRefreshScheduler: BackgroundRefreshScheduler(),
      isProviderConfigured: configuration.isEightSleepConfigured
    )
  }

  static var preview: AppModel {
    AppModel(
      provider: FixtureEightSleepProvider(),
      initialNights: FixtureEightSleepProvider.snapshot.nights,
      initialState: .connected(lastUpdated: FixtureEightSleepProvider.snapshot.fetchedAt)
    )
  }

  func connect(email: String, password: String) async {
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedEmail.isEmpty, !password.isEmpty else {
      connectionState = .failed(message: "Enter your Eight Sleep email and password.")
      return
    }

    let credentials = EightSleepCredentials(email: trimmedEmail, password: password)
    connectionState = .connecting
    credentialMessage = nil
    do {
      let snapshot = try await provider.connect(
        credentials: credentials,
        request: recentNightsRequest()
      )
      activeCredentials = credentials
      trySave(credentials)
      apply(snapshot)
      historyState = .idle
      preferences.set(sleepDayKey(for: snapshot.fetchedAt), forKey: Self.lastAutomaticRefreshKey)
      scheduleBackgroundRefresh(after: snapshot.fetchedAt)
      selectedTab = .data
    } catch is CancellationError {
      connectionState = .disconnected
    } catch {
      connectionState = .failed(message: userFacingMessage(for: error))
    }
  }

  func refresh() async {
    guard case .connected = connectionState else { return }
    do {
      let snapshot = try await refreshOrReconnect(request: recentNightsRequest())
      apply(snapshot)
      preferences.set(sleepDayKey(for: snapshot.fetchedAt), forKey: Self.lastAutomaticRefreshKey)
      scheduleBackgroundRefresh(after: snapshot.fetchedAt)
    } catch is CancellationError {
      return
    } catch {
      handleConnectionFailure(error)
    }
  }

  /// Restores the Keychain login after launch and refreshes at most once per
  /// local sleep day while this process remains connected. A sleep day rolls
  /// over at 4 a.m.
  func refreshForLifecycleIfNeeded(now: Date = .now) async {
    guard !isLifecycleRefreshInProgress else { return }
    isLifecycleRefreshInProgress = true
    defer { isLifecycleRefreshInProgress = false }

    loadSavedCredentialsIfNeeded()
    guard let activeCredentials else { return }
    scheduleBackgroundRefresh(after: now)

    let currentSleepDay = sleepDayKey(for: now)
    if case .connected = connectionState,
      preferences.string(forKey: Self.lastAutomaticRefreshKey) == currentSleepDay
    {
      return
    }

    let wasConnected: Bool
    if case .connected = connectionState {
      wasConnected = true
    } else {
      wasConnected = false
    }
    connectionState = .connecting
    do {
      let snapshot: EightSleepSnapshot
      if wasConnected {
        snapshot = try await refreshOrReconnect(request: recentNightsRequest(now: now))
      } else {
        snapshot = try await provider.connect(
          credentials: activeCredentials,
          request: recentNightsRequest(now: now)
        )
      }
      apply(snapshot)
      preferences.set(currentSleepDay, forKey: Self.lastAutomaticRefreshKey)
      scheduleBackgroundRefresh(after: snapshot.fetchedAt)
      if selectedTab == .connect { selectedTab = .data }
    } catch is CancellationError {
      connectionState = .disconnected
    } catch {
      handleConnectionFailure(error)
    }
  }

  /// Refreshes Eight Sleep while the app is suspended or relaunched for a
  /// background app-refresh task. The caller may then safely attempt an
  /// already-authorized HealthKit sync with the refreshed nights.
  @discardableResult
  func performScheduledBackgroundRefresh(now: Date = .now) async -> Bool {
    guard !isLifecycleRefreshInProgress else { return false }
    isLifecycleRefreshInProgress = true
    defer { isLifecycleRefreshInProgress = false }

    loadSavedCredentialsIfNeeded()
    guard let activeCredentials else {
      backgroundRefreshScheduler.cancel()
      return false
    }

    defer {
      if self.activeCredentials != nil {
        scheduleBackgroundRefresh(after: now)
      }
    }

    let wasConnected: Bool
    if case .connected = connectionState {
      wasConnected = true
    } else {
      wasConnected = false
    }

    do {
      let snapshot: EightSleepSnapshot
      if wasConnected {
        snapshot = try await refreshOrReconnect(request: recentNightsRequest(now: now))
      } else {
        snapshot = try await provider.connect(
          credentials: activeCredentials,
          request: recentNightsRequest(now: now)
        )
      }
      apply(snapshot)
      preferences.set(sleepDayKey(for: now), forKey: Self.lastAutomaticRefreshKey)
      return true
    } catch is CancellationError {
      return false
    } catch {
      handleConnectionFailure(error, selectConnectTab: false)
      return false
    }
  }

  func loadAllHistory(now: Date = .now) async {
    guard case .connected = connectionState else {
      historyState = .failed(message: "Connect Eight Sleep before auditing history.")
      return
    }

    let requests = historyRequests(now: now)
    var seenNightIDs: Set<String> = []
    var candidatesBySyncIdentifier: [String: RestingHeartRateSyncCandidate] = [:]
    historyState = .loading(completedRanges: 0, totalRanges: requests.count)

    do {
      for (index, request) in requests.enumerated() {
        try Task.checkCancellation()
        let snapshot = try await refreshOrReconnect(request: request)
        for night in snapshot.nights {
          guard seenNightIDs.insert(night.id).inserted else { continue }
          if let candidate = night.restingHeartRateSyncCandidate {
            candidatesBySyncIdentifier[candidate.syncIdentifier] = candidate
          }
        }
        historyState = .loading(completedRanges: index + 1, totalRanges: requests.count)
      }

      let candidates = candidatesBySyncIdentifier.values.sorted { $0.day > $1.day }
      historyState = .loaded(
        fetchedAt: now,
        sourceNightCount: seenNightIDs.count,
        invalidNightCount: max(seenNightIDs.count - candidates.count, 0),
        candidates: candidates
      )
    } catch is CancellationError {
      historyState = .idle
    } catch {
      historyState = .failed(message: userFacingMessage(for: error))
    }
  }

  func disconnect() async {
    await provider.disconnect()
    activeCredentials = nil
    nights = []
    historyState = .idle
    preferences.removeObject(forKey: Self.lastAutomaticRefreshKey)
    backgroundRefreshScheduler.cancel()
    do {
      try credentialStore.delete()
      hasSavedCredentials = false
      savedEmail = nil
      credentialMessage = nil
    } catch {
      credentialMessage = userFacingMessage(for: error)
    }
    connectionState = .disconnected
    selectedTab = .connect
  }

  private func loadSavedCredentialsIfNeeded() {
    guard !didLoadCredentials else { return }
    didLoadCredentials = true
    do {
      activeCredentials = try credentialStore.load()
      hasSavedCredentials = activeCredentials != nil
      savedEmail = activeCredentials?.email
    } catch {
      credentialMessage = userFacingMessage(for: error)
    }
  }

  private func trySave(_ credentials: EightSleepCredentials) {
    do {
      try credentialStore.save(credentials)
      hasSavedCredentials = true
      savedEmail = credentials.email
      credentialMessage = nil
    } catch {
      hasSavedCredentials = false
      savedEmail = credentials.email
      credentialMessage = userFacingMessage(for: error)
    }
  }

  private func refreshOrReconnect(
    request: EightSleepFetchRequest
  ) async throws -> EightSleepSnapshot {
    do {
      return try await provider.refresh(request: request)
    } catch EightSleepAPIError.sessionExpired {
      guard let activeCredentials else { throw EightSleepAPIError.sessionExpired }
      return try await provider.connect(credentials: activeCredentials, request: request)
    }
  }

  private func apply(_ snapshot: EightSleepSnapshot) {
    nights = snapshot.nights.sorted { $0.day > $1.day }
    connectionState = .connected(lastUpdated: snapshot.fetchedAt)
  }

  private func handleConnectionFailure(_ error: Error, selectConnectTab: Bool = true) {
    if error as? EightSleepAPIError == .invalidCredentials {
      activeCredentials = nil
      try? credentialStore.delete()
      hasSavedCredentials = false
      savedEmail = nil
      preferences.removeObject(forKey: Self.lastAutomaticRefreshKey)
      backgroundRefreshScheduler.cancel()
    }
    connectionState = .failed(message: userFacingMessage(for: error))
    if selectConnectTab { selectedTab = .connect }
  }

  private func scheduleBackgroundRefresh(after date: Date) {
    guard hasSavedCredentials else { return }
    backgroundRefreshScheduler.scheduleNextRefresh(after: date)
  }

  private func recentNightsRequest(now: Date = .now) -> EightSleepFetchRequest {
    let calendar = localCalendar
    let fromDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    return fetchRequest(from: fromDate, to: now, includeIntervalProbes: true)
  }

  private func historyRequests(now: Date) -> [EightSleepFetchRequest] {
    let calendar = localCalendar
    let currentYear = calendar.component(.year, from: now)
    guard currentYear >= Self.historyStartYear else { return [] }

    return (Self.historyStartYear ... currentYear).reversed().compactMap { year in
      guard
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
        let followingYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)),
        let endOfYear = calendar.date(byAdding: .day, value: -1, to: followingYear)
      else { return nil }
      return fetchRequest(
        from: start,
        to: min(endOfYear, now),
        includeIntervalProbes: false
      )
    }
  }

  private func fetchRequest(
    from: Date,
    to: Date,
    includeIntervalProbes: Bool
  ) -> EightSleepFetchRequest {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = localCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return EightSleepFetchRequest(
      from: formatter.string(from: from),
      to: formatter.string(from: to),
      timeZoneIdentifier: localCalendar.timeZone.identifier,
      includeIntervalProbes: includeIntervalProbes
    )
  }

  private func sleepDayKey(for date: Date) -> String {
    let shifted = localCalendar.date(byAdding: .hour, value: -4, to: date) ?? date
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = localCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: shifted)
  }

  private var localCalendar: Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    return calendar
  }

  private func userFacingMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return "The Eight Sleep request failed. Try again later."
  }
}
