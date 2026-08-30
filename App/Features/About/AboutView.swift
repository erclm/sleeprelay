import SwiftUI

struct AboutView: View {
  var body: some View {
    List {
      Section("Current build") {
        Label("Eight Sleep reads only", systemImage: "arrow.down.circle")
        Label("HealthKit coverage reads only", systemImage: "heart.text.square")
        Label("Explicit RHR-only HealthKit imports", systemImage: "heart.circle")
        Label("No saved account password", systemImage: "key.slash")
        Label("No Sleep Relay server", systemImage: "externaldrive.badge.xmark")
      }

      Section("Why read first?") {
        Text(
          "The Eight Sleep API is unofficial and can change. This prototype exposes the fields and time-series names returned for your own nights before we decide which values can safely map to Apple Health."
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
    }
    .navigationTitle("About")
  }
}

#Preview {
  NavigationStack {
    AboutView()
  }
}
