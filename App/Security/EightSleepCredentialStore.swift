import Foundation
import Security
import SleepRelayCore

enum EightSleepCredentialStoreError: LocalizedError {
  case keychain(OSStatus)
  case invalidStoredValue

  var errorDescription: String? {
    switch self {
    case .keychain:
      "The Eight Sleep login could not be saved securely in Apple Keychain."
    case .invalidStoredValue:
      "The saved Eight Sleep login could not be read from Apple Keychain."
    }
  }
}

@MainActor
protocol EightSleepCredentialStoring {
  func load() throws -> EightSleepCredentials?
  func save(_ credentials: EightSleepCredentials) throws
  func delete() throws
}

@MainActor
final class KeychainEightSleepCredentialStore: EightSleepCredentialStoring {
  private let service: String
  private let account = "eight-sleep-login"

  init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "app.sleeprelay.ios") {
    service = "\(bundleIdentifier).credentials"
  }

  func load() throws -> EightSleepCredentials? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw EightSleepCredentialStoreError.keychain(status)
    }
    guard
      let data = result as? Data,
      let credentials = try? JSONDecoder().decode(EightSleepCredentials.self, from: data),
      !credentials.email.isEmpty,
      !credentials.password.isEmpty
    else {
      throw EightSleepCredentialStoreError.invalidStoredValue
    }
    return credentials
  }

  func save(_ credentials: EightSleepCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    var attributes = baseQuery
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    SecItemDelete(baseQuery as CFDictionary)
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw EightSleepCredentialStoreError.keychain(status)
    }
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw EightSleepCredentialStoreError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

@MainActor
final class InMemoryEightSleepCredentialStore: EightSleepCredentialStoring {
  private var credentials: EightSleepCredentials?

  init(credentials: EightSleepCredentials? = nil) {
    self.credentials = credentials
  }

  func load() throws -> EightSleepCredentials? { credentials }
  func save(_ credentials: EightSleepCredentials) throws { self.credentials = credentials }
  func delete() throws { credentials = nil }
}
