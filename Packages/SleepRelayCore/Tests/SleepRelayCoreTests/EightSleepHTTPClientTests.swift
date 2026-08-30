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

  @Test
  func probesVerifiedReadOnlyIntervalsPathAndKeepsOnlySanitizedSummary() async throws {
    let authURL = URL(string: "https://auth.example.test/v1/tokens")!
    let baseURL = URL(string: "https://client.example.test/v1/")!
    func response(_ url: URL) -> HTTPURLResponse {
      HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
    let transport = StubTransport(responses: [
      (
        Data(#"{"access_token":"short-lived","expires_in":3600,"userId":"user-1"}"#.utf8),
        response(authURL)
      ),
      (
        Data(
          #"{"days":[{"day":"2026-08-28","mainSessionId":"session-secret","sleepQualityScore":{"hrv":{"current":40.5}},"sessions":[{"id":"other-session-secret","hrvAlgorithmVersion":"private-other-version","timeseries":{"heartRate":[["2026-08-28T06:00:00Z",999]]}},{"id":"session-secret","hrvAlgorithmVersion":"private-selected-version","timeseries":{"heartRate":[["2026-08-28T06:00:00Z",58],["2026-08-28T06:05:00Z",56]],"hrv":[["2026-08-28T06:00:00Z",39],["2026-08-28T06:05:00Z",42]],"rmssd":[["2026-08-28T06:00:00Z",39],["2026-08-28T06:05:00Z",42]]}}]}]}"#.utf8
        ),
        response(baseURL)
      ),
      (
        Data(
          #"{"summary":{"rhr":55},"hrvAlgorithmVersion":"private-selected-version","timeseries":{"heartRate":[["2026-08-28T06:00:00Z",58],["2026-08-28T06:05:00Z",56]],"hrv":[["2026-08-28T06:00:00Z",39],["2026-08-28T06:05:00Z",42]],"rmssd":[["2026-08-28T06:00:00Z",39],["2026-08-28T06:05:00Z",42]]}}"#.utf8
        ),
        response(baseURL)
      ),
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
        from: "2026-08-28",
        to: "2026-08-28",
        timeZoneIdentifier: "UTC",
        includePayloadShapeDiagnostics: true
      )
    )

    let night = try #require(snapshot.nights.first)
    #expect(night.discoveredRestingHeartRateBPM == 55)
    #expect(night.intervalProbe?.series.first?.sampleCount == 2)
    #expect(night.intervalProbe?.fieldPaths.contains("timeseries.heartRate[]") == true)
    #expect(night.trendsPathSummaries.contains { $0.path == "sessions" })
    #expect(
      night.intervalProbe?.pathSummaries.contains { $0.path == "timeseries.heartRate" }
        == true
    )
    #expect(
      night.intervalProbe?.pathSummaries.first { $0.path == "timeseries.heartRate" }?
        .typicalCadenceBucket == .oneToTenMinutes
    )
    #expect(night.intervalProbe?.seriesRelationships.count == 5)
    #expect(night.intervalProbe?.algorithmVersionRelationship == .exactMatch)
    #expect(
      night.intervalProbe?.nightlyHRVConsistency.first { $0.series == .trendsHRV }?
        .matchingAggregates.map(\.aggregate) == [.mean, .median]
    )
    #expect(
      night.intervalProbe?.seriesRelationships.first {
        $0.comparison == .heartRateAcrossEndpoints
      }?.valueRelation == .allExact
    )
    let structureReport = EightSleepDiagnosticReport.sanitizedStructureReport(for: night)
    let relationshipReport = EightSleepSeriesRelationshipReport.sanitizedReport(for: night)
    #expect(!structureReport.contains("user-1"))
    #expect(!structureReport.contains("session-secret"))
    #expect(!structureReport.contains("other-session-secret"))
    #expect(!structureReport.contains("2026-08-28"))
    #expect(relationshipReport.contains("Format: series-relationship-v1"))
    #expect(!relationshipReport.contains("user-1"))
    #expect(!relationshipReport.contains("session-secret"))
    #expect(!relationshipReport.contains("other-session-secret"))
    #expect(!relationshipReport.contains("2026-08-28"))
    #expect(!relationshipReport.contains("private-selected-version"))
    #expect(!relationshipReport.contains("private-other-version"))
    let requests = await transport.requests
    #expect(requests.count == 3)
    #expect(requests[2].httpMethod == "GET")
    #expect(requests[2].url?.path == "/v1/users/user-1/intervals/session-secret")
    #expect(requests[2].url?.query == nil)
  }

  @Test
  func historyRequestSkipsPerNightIntervalProbes() async throws {
    let authURL = URL(string: "https://auth.example.test/v1/tokens")!
    let baseURL = URL(string: "https://client.example.test/v1/")!
    func response(_ url: URL) -> HTTPURLResponse {
      HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
    let transport = StubTransport(responses: [
      (
        Data(#"{"access_token":"short-lived","expires_in":3600,"userId":"user-1"}"#.utf8),
        response(authURL)
      ),
      (
        Data(
          #"{"days":[{"day":"2026-08-28","sessions":[{"id":"session-secret","timeseries":{}}]}]}"#.utf8
        ),
        response(baseURL)
      ),
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
        from: "2025-01-01",
        to: "2025-12-31",
        timeZoneIdentifier: "UTC",
        includeIntervalProbes: false
      )
    )

    #expect(snapshot.nights.count == 1)
    #expect(snapshot.nights.first?.intervalProbe == nil)
    #expect(snapshot.nights.first?.trendsPathSummaries.isEmpty == true)
    #expect(await transport.requests.count == 2)
  }
}
