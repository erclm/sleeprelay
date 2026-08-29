import SwiftUI

@main
struct SleepRelayApp: App {
  @State private var model = AppModel.live()

  var body: some Scene {
    WindowGroup {
      AppView(model: model)
    }
  }
}
