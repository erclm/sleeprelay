import Foundation
import Observation
import SleepRelayCore

enum AppTab: Hashable {
  case connect
  case data
  case about
}

enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected(lastUpdated: Date)
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
  private(set) var nights: [EightSleepNight] = []
  private(set) var isProviderConfigured: Bool

  private let provider: any EightSleepProviding

  init(
    provider: any EightSleepProviding,
    isProviderConfigured: Bool = true,
    initialNights: [EightSleepNight] = [],
    initialState: ConnectionState = .disconnected
  ) {
    self.provider = provider
    self.isProviderConfigured = isProviderConfigured
    nights = initialNights
    connectionState = initialState
  }

  static func live(configuration: AppConfiguration = .live()) -> AppModel {
    AppModel(
      provider: EightSleepHTTPClient(configuration: configuration.eightSleep),
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
    guard !email.isEmpty, !password.isEmpty else {
      connectionState = .failed(message: "Enter your Eight Sleep email and password.")
      return
    }

    connectionState = .connecting
    do {
      let snapshot = try await provider.connect(
        credentials: EightSleepCredentials(email: email, password: password),
        request: recentNightsRequest()
      )
      nights = snapshot.nights.sorted { $0.day > $1.day }
      connectionState = .connected(lastUpdated: snapshot.fetchedAt)
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
      let snapshot = try await provider.refresh(request: recentNightsRequest())
      nights = snapshot.nights.sorted { $0.day > $1.day }
      connectionState = .connected(lastUpdated: snapshot.fetchedAt)
    } catch is CancellationError {
      return
    } catch {
      connectionState = .failed(message: userFacingMessage(for: error))
      selectedTab = .connect
    }
  }

  func disconnect() async {
    await provider.disconnect()
    nights = []
    connectionState = .disconnected
    selectedTab = .connect
  }

  private func recentNightsRequest(now: Date = .now) -> EightSleepFetchRequest {
    var calendar = Calendar.autoupdatingCurrent
    calendar.timeZone = .autoupdatingCurrent
    let fromDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"

    return EightSleepFetchRequest(
      from: formatter.string(from: fromDate),
      to: formatter.string(from: now),
      timeZoneIdentifier: calendar.timeZone.identifier
    )
  }

  private func userFacingMessage(for error: Error) -> String {
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return "The read-only Eight Sleep request failed. Try again later."
  }
}
