import SwiftUI

struct AppView: View {
  @Bindable var model: AppModel
  @Bindable var healthModel: HealthCoverageModel

  var body: some View {
    TabView(selection: $model.selectedTab) {
      NavigationStack {
        ConnectionView(model: model)
      }
      .tabItem { Label("Connect", systemImage: "link") }
      .tag(AppTab.connect)

      NavigationStack {
        SleepDataView(model: model, healthModel: healthModel)
      }
      .tabItem { Label("Eight Data", systemImage: "bed.double") }
      .tag(AppTab.data)

      NavigationStack {
        HealthCoverageView(model: healthModel)
      }
      .tabItem { Label("Health", systemImage: "heart.text.square") }
      .tag(AppTab.health)

      NavigationStack {
        AboutView()
      }
      .tabItem { Label("About", systemImage: "info.circle") }
      .tag(AppTab.about)
    }
  }
}

#Preview("Loaded") {
  AppView(model: .preview, healthModel: .preview)
}
