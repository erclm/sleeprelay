import Foundation
import Testing

@testable import SleepRelayCore

actor StubTransport: HTTPTransport {
  private var responses: [(Data, HTTPURLResponse)]
  private(set) var requests: [URLRequest] = []

  init(responses: [(Data, HTTPURLResponse)]) {
    self.responses = responses
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    guard !responses.isEmpty else {
      throw EightSleepAPIError.invalidResponse
    }
    return responses.removeFirst()
  }
}

struct EightSleepHTTPClientTests {
  @Test
  func authenticatesThenFetchesReadOnlyTrends() async throws {
    let authURL = URL(string: "https://auth.example.test/v1/tokens")!
    let baseURL = URL(string: "https://client.example.test/v1/")!
    let authResponse = HTTPURLResponse(
      url: authURL,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let trendsResponse = HTTPURLResponse(
      url: baseURL,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let transport = StubTransport(responses: [
      (
        Data(#"{"access_token":"short-lived","expires_in":3600,"userId":"user-1"}"#.utf8),
        authResponse
      ),
      (Data(#"{"days":[]}"#.utf8), trendsResponse),
    ])
    let client = EightSleepHTTPClient(
      configuration: EightSleepAPIConfiguration(
        clientID: "client",
        clientSecret: "client-secret",
        authURL: authURL,
        clientAPIBaseURL: baseURL
      ),
      transport: transport
    )

    let snapshot = try await client.connect(
      credentials: EightSleepCredentials(email: "person@example.test", password: "password"),
      request: EightSleepFetchRequest(
        from: "2026-08-21",
        to: "2026-08-28",
        timeZoneIdentifier: "America/Los_Angeles"
      )
    )

    #expect(snapshot.nights.isEmpty)
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[0].httpMethod == "POST")
    #expect(
      requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    let body = String(data: try #require(requests[0].httpBody), encoding: .utf8)
    #expect(body?.contains("grant_type=password") == true)
    #expect(body?.contains("username=person@example.test") == true)
    #expect(requests[1].httpMethod == "GET")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer short-lived")
    #expect(requests[1].url?.path == "/v1/users/user-1/trends")
    #expect(requests[1].url?.query?.contains("model-version=v2") == true)
  }

  @Test
  func refusesToSendCredentialsWhenClientConfigurationIsMissing() async {
    let transport = StubTransport(responses: [])
    let client = EightSleepHTTPClient(
      configuration: EightSleepAPIConfiguration(clientID: "", clientSecret: ""),
      transport: transport
    )

    await #expect(throws: EightSleepAPIError.missingClientConfiguration) {
      try await client.connect(
        credentials: EightSleepCredentials(email: "person@example.test", password: "password"),
        request: EightSleepFetchRequest(
          from: "2026-08-21", to: "2026-08-28", timeZoneIdentifier: "UTC")
      )
    }
    #expect(await transport.requests.isEmpty)
  }
}
