import Foundation

public struct EightSleepAPIConfiguration: Equatable, Sendable {
  public let clientID: String
  public let clientSecret: String
  public let authURL: URL
  public let clientAPIBaseURL: URL

  public init(
    clientID: String,
    clientSecret: String,
    authURL: URL = URL(string: "https://auth-api.8slp.net/v1/tokens")!,
    clientAPIBaseURL: URL = URL(string: "https://client-api.8slp.net/v1/")!
  ) {
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.authURL = authURL
    self.clientAPIBaseURL = clientAPIBaseURL
  }

  public var isConfigured: Bool {
    !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

public enum EightSleepAPIError: Error, Equatable, LocalizedError, Sendable {
  case missingClientConfiguration
  case invalidCredentials
  case rateLimited
  case sessionExpired
  case invalidResponse
  case invalidPayload
  case server(statusCode: Int)

  public var errorDescription: String? {
    switch self {
    case .missingClientConfiguration:
      "The local Eight Sleep client configuration is missing."
    case .invalidCredentials:
      "Eight Sleep rejected the email or password."
    case .rateLimited:
      "Eight Sleep is temporarily rate limiting sign-ins. Please wait before retrying."
    case .sessionExpired:
      "The short-lived Eight Sleep session expired. Connect again to refresh it."
    case .invalidResponse, .invalidPayload:
      "Eight Sleep returned data in an unexpected format."
    case .server(let statusCode):
      "Eight Sleep returned HTTP \(statusCode)."
    }
  }
}

public protocol EightSleepProviding: Sendable {
  func connect(
    credentials: EightSleepCredentials,
    request: EightSleepFetchRequest
  ) async throws -> EightSleepSnapshot

  func refresh(request: EightSleepFetchRequest) async throws -> EightSleepSnapshot
  func disconnect() async
}

public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
  private let session: URLSession

  public init(session: URLSession) {
    self.session = session
  }

  public static func ephemeral() -> URLSessionTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSessionTransport(session: URLSession(configuration: configuration))
  }

  public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw EightSleepAPIError.invalidResponse
    }
    return (data, response)
  }
}

public actor EightSleepHTTPClient: EightSleepProviding {
  private struct AuthenticationResponse: Decodable {
    let accessToken: String
    let expiresIn: Double
    let userID: String

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case expiresIn = "expires_in"
      case userID = "userId"
    }
  }

  private struct Session: Sendable {
    let token: String
    let expiresAt: Date
    let userID: String
  }

  private let configuration: EightSleepAPIConfiguration
  private let transport: any HTTPTransport
  private var session: Session?

  public init(
    configuration: EightSleepAPIConfiguration,
    transport: any HTTPTransport = URLSessionTransport.ephemeral()
  ) {
    self.configuration = configuration
    self.transport = transport
  }

  public func connect(
    credentials: EightSleepCredentials,
    request: EightSleepFetchRequest
  ) async throws -> EightSleepSnapshot {
    session = try await authenticate(credentials)
    return try await fetch(request)
  }

  public func refresh(request: EightSleepFetchRequest) async throws -> EightSleepSnapshot {
    try await fetch(request)
  }

  public func disconnect() {
    session = nil
  }

  private func authenticate(_ credentials: EightSleepCredentials) async throws -> Session {
    guard configuration.isConfigured else {
      throw EightSleepAPIError.missingClientConfiguration
    }

    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "grant_type", value: "password"),
      URLQueryItem(name: "username", value: credentials.email),
      URLQueryItem(name: "password", value: credentials.password),
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "client_secret", value: configuration.clientSecret),
    ]

    var request = URLRequest(url: configuration.authURL)
    request.httpMethod = "POST"
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    request.setValue(
      "application/x-www-form-urlencoded",
      forHTTPHeaderField: "Content-Type"
    )
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SleepRelay/0.1", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await transport.data(for: request)
    switch response.statusCode {
    case 200..<300:
      break
    case 400, 401:
      throw EightSleepAPIError.invalidCredentials
    case 429:
      throw EightSleepAPIError.rateLimited
    default:
      throw EightSleepAPIError.server(statusCode: response.statusCode)
    }

    guard
      let auth = try? JSONDecoder().decode(AuthenticationResponse.self, from: data),
      !auth.accessToken.isEmpty,
      !auth.userID.isEmpty
    else {
      throw EightSleepAPIError.invalidPayload
    }

    return Session(
      token: auth.accessToken,
      expiresAt: Date().addingTimeInterval(max(auth.expiresIn - 60, 0)),
      userID: auth.userID
    )
  }

  private func fetch(_ request: EightSleepFetchRequest) async throws -> EightSleepSnapshot {
    guard let session else {
      throw EightSleepAPIError.sessionExpired
    }
    guard Date() < session.expiresAt else {
      self.session = nil
      throw EightSleepAPIError.sessionExpired
    }

    let trendsBase = configuration.clientAPIBaseURL
      .appendingPathComponent("users")
      .appendingPathComponent(session.userID)
      .appendingPathComponent("trends")
    guard var components = URLComponents(url: trendsBase, resolvingAgainstBaseURL: false) else {
      throw EightSleepAPIError.invalidResponse
    }
    components.queryItems = [
      URLQueryItem(name: "tz", value: request.timeZoneIdentifier),
      URLQueryItem(name: "from", value: request.from),
      URLQueryItem(name: "to", value: request.to),
      URLQueryItem(name: "include-main", value: "false"),
      URLQueryItem(name: "include-all-sessions", value: "true"),
      URLQueryItem(name: "model-version", value: "v2"),
    ]
    guard let url = components.url else {
      throw EightSleepAPIError.invalidResponse
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "GET"
    urlRequest.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    urlRequest.setValue("SleepRelay/0.1", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await transport.data(for: urlRequest)
    switch response.statusCode {
    case 200..<300:
      break
    case 401:
      self.session = nil
      throw EightSleepAPIError.sessionExpired
    case 429:
      throw EightSleepAPIError.rateLimited
    default:
      throw EightSleepAPIError.server(statusCode: response.statusCode)
    }

    let decodedTrends = try EightSleepPayloadDecoder.decodeTrendsWithDiagnosticContext(
      data,
      redacting: [session.userID],
      includePayloadShapeDiagnostics: request.includePayloadShapeDiagnostics
    )
    var nights = decodedTrends.nights
    guard request.includeIntervalProbes else {
      return EightSleepSnapshot(fetchedAt: Date(), nights: nights)
    }

    for index in nights.indices {
      guard let sessionID = nights[index].latestSessionID else { continue }
      do {
        let result = try await fetchIntervalProbe(
          sessionID: sessionID,
          session: session,
          additionalRedactions: [nights[index].id, nights[index].day],
          includePayloadShapeDiagnostics: request.includePayloadShapeDiagnostics,
          trendsSeries: request.includePayloadShapeDiagnostics
            ? nights[index].timeSeries.filter { $0.sessionID == sessionID }
            : [],
          trendsAlgorithmVersion: request.includePayloadShapeDiagnostics
            ? decodedTrends.selectedHRVAlgorithmVersionsBySessionID[sessionID]
            : nil,
          nightlyHRVMilliseconds: request.includePayloadShapeDiagnostics
            ? nights[index].diagnosticNightlyHRVCurrentMilliseconds
            : nil
        )
        nights[index].intervalProbe = result.probe
        if result.shouldStop {
          break
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        nights[index].intervalProbe = .unavailable("Request failed")
        break
      }
    }
    return EightSleepSnapshot(fetchedAt: Date(), nights: nights)
  }

  private func fetchIntervalProbe(
    sessionID: String,
    session: Session,
    additionalRedactions: Set<String>,
    includePayloadShapeDiagnostics: Bool,
    trendsSeries: [EightSleepTimeSeries],
    trendsAlgorithmVersion: String?,
    nightlyHRVMilliseconds: Double?
  ) async throws -> (probe: EightSleepIntervalProbe, shouldStop: Bool) {
    let url = configuration.clientAPIBaseURL
      .appendingPathComponent("users")
      .appendingPathComponent(session.userID)
      .appendingPathComponent("intervals")
      .appendingPathComponent(sessionID)

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("SleepRelay/0.1", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await transport.data(for: request)
    switch response.statusCode {
    case 200..<300:
      do {
        return (
          try EightSleepIntervalProbeDecoder.decode(
            data,
            redacting: Set([session.userID, sessionID]).union(additionalRedactions),
            includePayloadShapeDiagnostics: includePayloadShapeDiagnostics,
            trendsSeries: trendsSeries,
            trendsAlgorithmVersion: trendsAlgorithmVersion,
            nightlyHRVMilliseconds: nightlyHRVMilliseconds
          ),
          false
        )
      } catch {
        return (.unavailable("Unexpected response shape"), true)
      }
    case 401:
      self.session = nil
      return (.unavailable("Session expired"), true)
    case 404:
      return (.unavailable("Endpoint unavailable (HTTP 404)"), true)
    case 429:
      return (.unavailable("Rate limited"), true)
    default:
      return (.unavailable("HTTP \(response.statusCode)"), true)
    }
  }
}
