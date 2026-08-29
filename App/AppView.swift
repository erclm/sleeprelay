import SwiftUI

struct AppView: View {
  @Bindable var model: AppModel

  var body: some View {
    TabView(selection: $model.selectedTab) {
      NavigationStack {
        ConnectionView(model: model)
      }
      .tabItem { Label("Connect", systemImage: "link") }
      .tag(AppTab.connect)

      NavigationStack {
        SleepDataView(model: model)
      }
      .tabItem { Label("Eight Data", systemImage: "bed.double") }
      .tag(AppTab.data)

      NavigationStack {
        AboutView()
      }
      .tabItem { Label("About", systemImage: "info.circle") }
      .tag(AppTab.about)
    }
  }
}

#Preview("Loaded") {
  AppView(model: .preview)
}
