import SleepRelayCore
import SwiftUI

@main
struct SleepRelayApp: App {
  @State private var model: AppModel
  @State private var healthModel: HealthCoverageModel

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-validateHealthKitSampleConstruction") {
        guard
          let night = FixtureEightSleepProvider.snapshot.nights.first,
          let candidate = night.restingHeartRateSyncCandidate
        else {
          preconditionFailure("The HealthKit construction fixture is missing an RHR candidate.")
        }
        do {
          _ = try HealthKitCoverageProvider.makeRestingHeartRateSample(candidate)
          print("SLEEP_RELAY_HEALTHKIT_SAMPLE_VALID")
        } catch {
          preconditionFailure("HealthKit sample construction failed: \(error)")
        }
      }

      if ProcessInfo.processInfo.arguments.contains("-useFixtures") {
        _model = State(initialValue: .preview)
        _healthModel = State(initialValue: .preview)
      } else if ProcessInfo.processInfo.arguments.contains("-useFixtureEightWithLiveHealth") {
        _model = State(initialValue: .preview)
        _healthModel = State(initialValue: .live())
      } else {
        _model = State(initialValue: .live())
        _healthModel = State(initialValue: .live())
      }
    #else
      _model = State(initialValue: .live())
      _healthModel = State(initialValue: .live())
    #endif
  }

  var body: some Scene {
    WindowGroup {
      AppView(model: model, healthModel: healthModel)
    }
  }
}
