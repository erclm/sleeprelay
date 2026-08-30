import Foundation
import Testing

@testable import SleepRelayCore

struct EightSleepPayloadShapeAnalyzerTests {
  @Test
  func inventoriesEveryNestedShapeIncludingFieldsAfterTheThirdArrayElement() throws {
    let data = Data(
      #"{"rows":[{"flag":true,"values":[1,2]},{"flag":false,"values":[]},{"label":"safe"},{"rrIntervals":[801,799]}],"mixed":[1,"2","text",false,null,{},[3,4]],"empty":[]}"#.utf8
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      data,
      includePayloadShapeDiagnostics: true
    )

    let rows = try #require(summary("rows", in: probe.pathSummaries))
    #expect(rows.arrayInstanceCount == 1)
    #expect(rows.totalArrayElementCount == 4)
    #expect(rows.minimumArrayElementCount == 4)
    #expect(rows.maximumArrayElementCount == 4)

    let repeatedValues = try #require(summary("rows[].values", in: probe.pathSummaries))
    #expect(repeatedValues.arrayInstanceCount == 2)
    #expect(repeatedValues.totalArrayElementCount == 2)
    #expect(repeatedValues.minimumArrayElementCount == 0)
    #expect(repeatedValues.maximumArrayElementCount == 2)

    let lateIntervals = try #require(
      summary("rows[].rrIntervals", in: probe.pathSummaries)
    )
    #expect(lateIntervals.arrayInstanceCount == 1)
    #expect(summary("rows[].rrIntervals[]", in: probe.pathSummaries) != nil)

    let mixedItems = try #require(summary("mixed[]", in: probe.pathSummaries))
    #expect(
      Set(mixedItems.kindCounts.map(\.kind)) == [
        .array, .boolean, .null, .number, .numericString, .object, .text,
      ]
    )
    #expect(summary("mixed[][]", in: probe.pathSummaries) != nil)
    #expect(summary("empty", in: probe.pathSummaries)?.totalArrayElementCount == 0)

    let disabledProbe = try EightSleepIntervalProbeDecoder.decode(data)
    #expect(disabledProbe.pathSummaries.isEmpty)
  }

  @Test
  func reportsRelativeCadenceWithoutRetainingAbsoluteTimestamps() throws {
    let chronological = Data(
      #"{"heartRate":[["2026-08-28T06:00:00Z",4321.987],["2026-08-28T06:05:00Z",4322.987],["2026-08-28T06:12:00Z",4323.987]]}"#.utf8
    )
    let reversed = Data(
      #"{"heartRate":[["2026-08-28T06:12:00Z",4323.987],["2026-08-28T06:05:00Z",4322.987],["2026-08-28T06:00:00Z",4321.987]]}"#.utf8
    )

    let first = try EightSleepIntervalProbeDecoder.decode(
      chronological,
      includePayloadShapeDiagnostics: true
    )
    let second = try EightSleepIntervalProbeDecoder.decode(
      reversed,
      includePayloadShapeDiagnostics: true
    )
    let cadence = try #require(summary("heartRate", in: first.pathSummaries))

    #expect(cadence.timestampObservationCount == 3)
    #expect(cadence.cadenceGapCount == 2)
    #expect(cadence.typicalCadenceBucket == .oneToTenMinutes)
    #expect(!cadence.cadenceSampleWasCapped)
    #expect(first.pathSummaries == second.pathSummaries)
    #expect(summary("heartRate[]", in: first.pathSummaries)?.arrayInstanceCount == 3)
    #expect(
      Set(
        try #require(summary("heartRate[][]", in: first.pathSummaries)).kindCounts.map(\.kind)
      ) == [.number, .timestampString]
    )
  }

  @Test
  func doesNotTreatEpochLikeIdentifierValuesAsTimestamps() throws {
    let data = Data(
      #"{"id":"1724824800","mainSessionId":"1724824801","sessionIds":["1724824802","1724824803"],"fluid":"1724824804","fluids":"1724824805","timestamp":"2026-08-28T06:00:00Z"}"#.utf8
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      data,
      includePayloadShapeDiagnostics: true
    )

    #expect(summary("id", in: probe.pathSummaries)?.kindCounts.first?.kind == .text)
    #expect(summary("mainSessionId", in: probe.pathSummaries)?.kindCounts.first?.kind == .text)
    #expect(summary("sessionIds", in: probe.pathSummaries)?.timestampObservationCount == 0)
    #expect(summary("sessionIds[]", in: probe.pathSummaries)?.kindCounts.first?.kind == .text)
    #expect(summary("fluid", in: probe.pathSummaries)?.kindCounts.first?.kind == .timestampString)
    #expect(summary("fluids", in: probe.pathSummaries)?.kindCounts.first?.kind == .timestampString)
    #expect(summary("timestamp", in: probe.pathSummaries)?.kindCounts.first?.kind == .timestampString)
  }

  @Test
  func doesNotClaimOneTypicalBucketWhenEvenMiddleGapsCrossABoundary() throws {
    let data = Data(
      #"{"series":[["2026-08-28T06:00:00Z",1],["2026-08-28T06:09:59Z",2],["2026-08-28T06:20:00Z",3]]}"#.utf8
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      data,
      includePayloadShapeDiagnostics: true
    )

    #expect(summary("series", in: probe.pathSummaries)?.cadenceGapCount == 2)
    #expect(summary("series", in: probe.pathSummaries)?.typicalCadenceBucket == nil)
  }

  @Test
  func structureReportRedactsIdentifiersDatesTimestampsAndAllPayloadValues() throws {
    let trendsData = Data(
      #"{"days":[{"day":"2099-12-31","id":"night-secret-1234567890","sessions":[{"id":"session-secret-1234567890","timeseries":{}}],"token":"raw-token-secret","heartRateVariability1":[987653.321],"mystery":[987654.321,987655.321]}]}"#.utf8
    )
    let intervalData = Data(
      #"{"deviceId":"pod_A7x9","pod_A7x9":{"value":765431.123},"device-temperature":123.456,"session-summary-v2":234.567,"06:00:00Z":{"value":765430.123},"2026-08-28T06:00:00Z":{"value":765432.123},"12345":{"value":765433.123},"person@example.test":{"value":765434.123},"2f1c17e3-97c7-40a9-a86e-d44ec0c1cc24":{"value":765435.123},"known-user-secret":{"value":765436.123},"series":[["2026-08-28T06:00:00Z",654321.987],["2026-08-28T06:05:00Z",654322.987]]}"#.utf8
    )

    var night = try #require(
      EightSleepPayloadDecoder.decodeTrends(
        trendsData,
        redacting: ["known-user-secret"],
        includePayloadShapeDiagnostics: true
      ).first
    )
    night.intervalProbe = try EightSleepIntervalProbeDecoder.decode(
      intervalData,
      redacting: [
        "known-user-secret", "night-secret-1234567890", "session-secret-1234567890",
      ],
      includePayloadShapeDiagnostics: true
    )

    let report = EightSleepDiagnosticReport.sanitizedStructureReport(for: night)

    #expect(report.contains("Format: payload-shape-v1"))
    #expect(report.contains("mystery"))
    #expect(report.contains("heartRateVariability1"))
    #expect(report.contains("series"))
    #expect(report.contains("{timestamp}"))
    #expect(report.contains("{index}"))
    #expect(report.contains("{identifier}"))
    #expect(report.contains("typical cadence 1-10 min"))
    #expect(report.contains("device-temperature"))
    #expect(report.contains("session-summary-v2"))

    for forbidden in [
      "2099-12-31",
      "night-secret-1234567890",
      "session-secret-1234567890",
      "raw-token-secret",
      "2026-08-28T06:00:00Z",
      "person@example.test",
      "2f1c17e3-97c7-40a9-a86e-d44ec0c1cc24",
      "known-user-secret",
      "pod_A7x9",
      "987653.321",
      "987654.321",
      "765432.123",
      "654321.987",
    ] {
      #expect(!report.contains(forbidden))
    }
  }

  @Test
  func sanitizesReservedPathCharactersWithoutCollidingWithTheRootSentinel() {
    #expect(sanitizedFieldKey("$") == #"\$"#)
    #expect(sanitizedFieldKey("a.b[c]\\d|e") == #"a\.b\[c\]\\d\|e"#)
    #expect(sanitizedFieldKey("{identifier}") == #"\{identifier\}"#)
    #expect(sanitizedFieldKey("06:00:00Z") == "{timestamp}")
    #expect(sanitizedFieldKey("device-temperature") == "device-temperature")
    #expect(sanitizedFieldKey("session-summary-v2") == "session-summary-v2")
    #expect(sanitizedFieldKey("session-abcdef") == "{identifier}")
    #expect(sanitizedFieldKey("user-abc") == "{identifier}")
    #expect(sanitizedFieldKey("08-30-2026") == "{timestamp}")
    #expect(sanitizedFieldKey("bpm54") == "{value-key}")
    #expect(sanitizedFieldKey("line\u{2028}break") == "line?break")
    #expect(sanitizedFieldKey("pod_A7x9", redacting: ["pod_A7x9"]) == "{identifier}")
  }

  @Test
  func rendersCanonicalStructureReportAndSortsCallerProvidedKinds() {
    let trendsSummary = EightSleepProbePathSummary(
      path: "$",
      kindCounts: [
        EightSleepProbeKindCount(kind: .text, count: 2),
        EightSleepProbeKindCount(kind: .number, count: 1),
      ]
    )
    let intervalProbe = EightSleepIntervalProbe(
      status: .unavailable(reason: "secret-server-detail"),
      fieldPaths: [],
      metricFields: [],
      series: [],
      pathSummaries: []
    )
    let night = makeNight(
      trendsPathSummaries: [trendsSummary],
      intervalProbe: intervalProbe
    )

    let report = EightSleepDiagnosticReport.sanitizedStructureReport(for: night)

    #expect(
      report == """
        Sleep Relay payload structure - sanitized
        Format: payload-shape-v1
        Scope: one decoded Eight Sleep night
        Contains: sanitized JSON paths, value kinds, counts, and broad relative-cadence buckets
        Excludes: primitive payload values, dates, absolute timestamps, exact cadence, raw samples, credentials, and recognized identifiers
        Review note: field names come from a private schema; inspect paths before sharing in case an unknown identifier is used as a field name

        Selected trends days[] object
        Endpoint: GET /v1/users/{user}/trends
        Status: Available
        Paths: 1
        - $ | number x1, text x2

        Intervals response
        Endpoint: GET /v1/users/{user}/intervals/{session}
        Status: Unavailable (Unavailable)
        Paths: 0
        - none

        Privacy check
        This copied report is generated from an in-memory structural summary and contains no primitive response values or raw response text.
        """
    )
    #expect(!report.contains("secret-server-detail"))
    #expect(!report.contains("2099-12-31"))
  }

  @Test
  func recognizesSubTenMillisecondCadenceWithoutReportingExactIntervals() throws {
    let data = Data(
      #"{"wave":[["2026-08-28T06:00:00.000Z",1],["2026-08-28T06:00:00.002Z",2],["2026-08-28T06:00:00.004Z",3]]}"#.utf8
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      data,
      includePayloadShapeDiagnostics: true
    )
    let wave = try #require(summary("wave", in: probe.pathSummaries))
    let report = EightSleepDiagnosticReport.summaryDescription(wave)

    #expect(wave.typicalCadenceBucket == .underTenMilliseconds)
    #expect(report.contains("typical cadence under 10 ms"))
    #expect(!report.contains("0.002"))
    #expect(!report.contains("2 ms"))
  }

  private func summary(
    _ path: String,
    in summaries: [EightSleepProbePathSummary]
  ) -> EightSleepProbePathSummary? {
    summaries.first { $0.path == path }
  }

  private func makeNight(
    trendsPathSummaries: [EightSleepProbePathSummary],
    intervalProbe: EightSleepIntervalProbe?
  ) -> EightSleepNight {
    EightSleepNight(
      id: "private-night-id",
      day: "2099-12-31",
      presenceStart: nil,
      presenceEnd: nil,
      isProcessing: false,
      score: 98_765.4321,
      sleepDurationSeconds: nil,
      averageHeartRateBPM: nil,
      explicitRestingHeartRateBPM: nil,
      reportedHRVMilliseconds: nil,
      averageRespiratoryRate: nil,
      tossAndTurns: nil,
      lightSleepSeconds: nil,
      deepSleepSeconds: nil,
      remSleepSeconds: nil,
      availableFields: [],
      metricFields: [],
      timeSeries: [],
      latestSessionID: "private-session-id",
      intervalProbe: intervalProbe,
      trendsPathSummaries: trendsPathSummaries
    )
  }
}
