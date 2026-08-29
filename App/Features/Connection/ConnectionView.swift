import SleepRelayCore
import SwiftUI

struct ConnectionView: View {
  let model: AppModel

  @State private var email = ""
  @State private var password = ""
  @FocusState private var focusedField: Field?

  private enum Field {
    case email
    case password
  }

  var body: some View {
    Form {
      Section {
        Label("Read-only prototype", systemImage: "eye")
          .font(.headline)
        Text(
          "Sleep Relay currently fetches recent sleep data. It has no HealthKit writer and no Eight Sleep mutation endpoints."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }

      Section("Eight Sleep account") {
        TextField("Email", text: $email)
          .textContentType(.username)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focusedField, equals: .email)
          .accessibilityIdentifier("eight-email")

        SecureField("Password", text: $password)
          .textContentType(.password)
          .focused($focusedField, equals: .password)
          .accessibilityIdentifier("eight-password")

        connectButton
      }

      stateSection

      Section("Credential handling") {
        Text(
          "Your email and password are sent directly to Eight Sleep for this session. Sleep Relay does not save them. The short-lived access token stays only in memory and disappears when the app closes or you disconnect."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("API status") {
        LabeledContent("Integration", value: "Unofficial")
        LabeledContent(
          "Local client config",
          value: model.isProviderConfigured ? "Available" : "Missing"
        )
      }
    }
    .navigationTitle("Sleep Relay")
  }

  @ViewBuilder
  private var connectButton: some View {
    switch model.connectionState {
    case .connecting:
      HStack {
        ProgressView()
        Text("Connecting…")
      }
    case .connected:
      Button("Disconnect", role: .destructive) {
        Task { await model.disconnect() }
      }
    case .disconnected, .failed:
      Button("Connect read-only") {
        let submittedPassword = password
        password = ""
        focusedField = nil
        Task {
          await model.connect(email: email, password: submittedPassword)
        }
      }
      .disabled(email.isEmpty || password.isEmpty || !model.isProviderConfigured)
      .accessibilityIdentifier("connect-eight")
    }
  }

  @ViewBuilder
  private var stateSection: some View {
    switch model.connectionState {
    case .disconnected:
      Section {
        Label("Not connected", systemImage: "circle")
          .foregroundStyle(.secondary)
      }
    case .connecting:
      EmptyView()
    case .connected(let lastUpdated):
      Section("Session") {
        Label("Connected read-only", systemImage: "checkmark.shield")
          .foregroundStyle(.green)
        LabeledContent(
          "Fetched", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
        LabeledContent("Visible nights", value: "\(model.nights.count)")
      }
    case .failed(let message):
      Section("Could not connect") {
        Label(message, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
    }
  }
}

#Preview("Disconnected") {
  NavigationStack {
    ConnectionView(
      model: AppModel(provider: FixtureEightSleepProvider())
    )
  }
}
