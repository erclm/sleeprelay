import SwiftUI

struct AboutView: View {
  let model: AppModel

  #if INTERNAL_TOOLS
    @State private var buildTapCount = 0
    @State private var isDeveloperUnlocked = false
  #endif

  var body: some View {
    List {
      Section("Current build") {
        Label("Eight Sleep reads only", systemImage: "arrow.down.circle")
        Label("HealthKit coverage reads only", systemImage: "heart.text.square")
        Label("Explicit RHR-only HealthKit imports", systemImage: "heart.circle")
        Label("Login saved in Apple Keychain", systemImage: "key.fill")
        Label("No Sleep Relay server", systemImage: "externaldrive.badge.xmark")
      }

      Section("Automatic refresh") {
        Text(
          "With a saved login, Sleep Relay asks iOS to fetch new nights after your typical wake time and also checks when you open the app. iOS chooses when background refresh runs."
        )
      }

      Section("API status") {
        LabeledContent("Integration", value: "Unofficial")
        LabeledContent(
          "Local client config",
          value: model.isProviderConfigured ? "Available" : "Missing"
        )
      }

      Section("HRV safety") {
        Text(
          "Eight Sleep and Fitbit report RMSSD. Apple Health's HRV type is SDNN. Sleep Relay shows Eight's RMSSD but does not relabel or write it as SDNN."
        )
      }

      Section("Open source") {
        Text(
          "Sleep Relay is licensed under MPL-2.0. Eight Sleep is a trademark of its owner; this project is not affiliated with or endorsed by Eight Sleep."
        )
      }

      Section("App") {
        #if INTERNAL_TOOLS
          Button {
            buildTapCount += 1
            if buildTapCount >= 7 { isDeveloperUnlocked = true }
          } label: {
            buildRow
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Version \(version), build \(build)")
        #else
          buildRow
        #endif
      }

      #if INTERNAL_TOOLS
        if isDeveloperUnlocked {
          Section("Internal") {
            NavigationLink {
              DeveloperView(model: model)
            } label: {
              Label("Diagnostics", systemImage: "wrench.and.screwdriver")
            }
          }
        }
      #endif
    }
    .navigationTitle("About")
  }

  private var buildRow: some View {
    LabeledContent("Version", value: "\(version) (\(build))")
  }

  private var version: String {
    buildValue("CFBundleShortVersionString")
  }

  private var build: String {
    buildValue("CFBundleVersion")
  }

  private func buildValue(_ key: String) -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
      return "Unknown"
    }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned.contains("$(") ? "Unknown" : cleaned
  }
}

#Preview {
  NavigationStack {
    AboutView(model: .preview)
  }
}
