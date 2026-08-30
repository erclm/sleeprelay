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
        Label("Eight Sleep connection", systemImage: "link")
          .font(.headline)
        Text(
          "Sleep Relay reads your sleep data without changing Eight Sleep. Your login is saved in Apple Keychain so new nights can refresh automatically."
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
          "Your email and password are sent directly to Eight Sleep and stored only in Apple Keychain on this iPhone. Sleep Relay has no account server. Disconnecting deletes the saved login."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)

        if model.hasSavedCredentials {
          Label("Login saved in Apple Keychain", systemImage: "key.fill")
            .foregroundStyle(.green)
        }
        if let message = model.credentialMessage {
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }
    }
    .navigationTitle("Sleep Relay")
    .task {
      if email.isEmpty, let savedEmail = model.savedEmail {
        email = savedEmail
      }
    }
    .onChange(of: model.savedEmail) { _, savedEmail in
      if email.isEmpty, let savedEmail { email = savedEmail }
    }
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
      Button("Disconnect and Forget Login", role: .destructive) {
        Task { await model.disconnect() }
      }
    case .disconnected, .failed:
      Button("Connect and Save Login") {
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
        Label("Connected", systemImage: "checkmark.shield")
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
