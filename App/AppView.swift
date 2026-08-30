import SwiftUI

struct AppView: View {
  @Bindable var model: AppModel
  @Bindable var healthModel: HealthCoverageModel
  @Environment(\.scenePhase) private var scenePhase

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
        AboutView(model: model)
      }
      .tabItem { Label("About", systemImage: "info.circle") }
      .tag(AppTab.about)

      #if INTERNAL_TOOLS
        NavigationStack {
          DeveloperView(model: model)
        }
        .tabItem { Label("Developer", systemImage: "wrench.and.screwdriver") }
        .tag(AppTab.developer)
      #endif
    }
    .task {
      await model.refreshForLifecycleIfNeeded()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await model.refreshForLifecycleIfNeeded() }
    }
    .onChange(of: model.connectionState) { _, state in
      guard case .connected = state else { return }
      Task { await healthModel.automaticSyncIfEligible(nights: model.nights) }
    }
  }
}

#Preview("Loaded") {
  AppView(model: .preview, healthModel: .preview)
}
