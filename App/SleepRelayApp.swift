import SwiftUI

@main
struct SleepRelayApp: App {
  @State private var model: AppModel
  @State private var healthModel: HealthCoverageModel

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-useFixtures") {
        _model = State(initialValue: .preview)
        _healthModel = State(initialValue: .preview)
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
