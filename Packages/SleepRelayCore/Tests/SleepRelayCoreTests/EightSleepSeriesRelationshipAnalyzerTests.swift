import Foundation
import Testing

@testable import SleepRelayCore

struct EightSleepSeriesRelationshipAnalyzerTests {
  @Test
  func detectsEveryThirdEndpointGridWithoutRetainingSamples() throws {
    let trendsHeartRate = makeSeries(
      name: "heartRate",
      minuteOffsets: [0, 1, 2, 3, 4, 5, 6],
      values: [60, 61, 62, 63, 64, 65, 66]
    )
    let intervalData = intervalPayload([
      "heartRate": points(
        minuteOffsets: [0, 3, 6],
        values: [60, 63, 66]
      )
    ])

    let probe = try EightSleepIntervalProbeDecoder.decode(
      intervalData,
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsHeartRate]
    )
    let relationship = try #require(
      probe.seriesRelationships.first {
        $0.comparison == .heartRateAcrossEndpoints
      }
    )

    #expect(probe.seriesRelationships.count == 5)
    #expect(relationship.availability == .available)
    #expect(relationship.leftObservationCount == 7)
    #expect(relationship.rightObservationCount == 3)
    #expect(relationship.timestampRelation == .rightSubset)
    #expect(relationship.subsetStride == .three)
    #expect(relationship.sharedTimestampCount == 3)
    #expect(relationship.comparableValueCount == 3)
    #expect(relationship.exactValueMatchCount == 3)
    #expect(relationship.valueRelation == .allExact)
    #expect(relationship.coMovement == .unavailable)
  }

  @Test
  func comparesHRVAndRMSSDWithOnlyCategoricalCoMovement() throws {
    let offsets = Array(0..<10)
    let values = offsets.map { Double($0 + 10) }
    let intervalData = intervalPayload([
      "hrv": points(minuteOffsets: offsets, values: values),
      "rmssd": points(minuteOffsets: offsets, values: values),
    ])

    let probe = try EightSleepIntervalProbeDecoder.decode(
      intervalData,
      includePayloadShapeDiagnostics: true
    )
    let relationship = try #require(
      probe.seriesRelationships.first {
        $0.comparison == .intervalsHRVToRMSSD
      }
    )

    #expect(relationship.timestampRelation == .identical)
    #expect(relationship.valueRelation == .allExact)
    #expect(relationship.exactValueMatchCount == 10)
    #expect(relationship.coMovement == .strongPositive)
  }

  @Test
  func excludesDuplicateTimestampsFromValueMatching() throws {
    let trendsHRV = makeSeries(
      name: "hrv",
      minuteOffsets: [0, 0, 1, 2, 3],
      values: [1, 999, 10, 20, 30]
    )
    let trendsRMSSD = makeSeries(
      name: "rmssd",
      minuteOffsets: [0, 1, 2, 3],
      values: [1, 10, 20.005, 40]
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([:]),
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsHRV, trendsRMSSD]
    )
    let relationship = try #require(
      probe.seriesRelationships.first {
        $0.comparison == .trendsHRVToRMSSD
      }
    )

    #expect(relationship.leftDuplicateTimestampCount == 1)
    #expect(relationship.rightDuplicateTimestampCount == 0)
    #expect(relationship.sharedTimestampCount == 4)
    #expect(relationship.comparableValueCount == 3)
    #expect(relationship.exactValueMatchCount == 1)
    #expect(relationship.nearValueMatchCount == 1)
    #expect(relationship.differentValueCount == 1)
    #expect(relationship.valueRelation == .mixed)
  }

  @Test
  func partitionsExactNearRoundedAndDifferentValues() throws {
    let trendsHRV = makeSeries(
      name: "hrv",
      minuteOffsets: [0, 1, 2, 3, 4],
      values: [10, 20, 30.01, 40.1, 50]
    )
    let trendsRMSSD = makeSeries(
      name: "rmssd",
      minuteOffsets: [0, 1, 2, 3, 4],
      values: [10, 20.005, 30.04, 40.4, 51]
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([:]),
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsHRV, trendsRMSSD]
    )
    let relationship = try #require(
      probe.seriesRelationships.first { $0.comparison == .trendsHRVToRMSSD }
    )

    #expect(relationship.exactValueMatchCount == 1)
    #expect(relationship.nearValueMatchCount == 1)
    #expect(relationship.oneDecimalRoundedValueMatchCount == 1)
    #expect(relationship.wholeNumberRoundedValueMatchCount == 1)
    #expect(relationship.differentValueCount == 1)
    #expect(relationship.valueRelation == .mixed)
  }

  @Test
  func reportsRoundedCompatibilityAndIndeterminateSingletonSubset() throws {
    let trendsHRV = makeSeries(
      name: "hrv",
      minuteOffsets: [0, 1],
      values: [10.01, 20.1]
    )
    let trendsRMSSD = makeSeries(
      name: "rmssd",
      minuteOffsets: [0, 1],
      values: [10.04, 20.4]
    )
    let trendsHeartRate = makeSeries(
      name: "heartRate",
      minuteOffsets: [0, 1, 2],
      values: [60, 61, 62]
    )
    let probe = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([
        "heartRate": points(minuteOffsets: [1], values: [61])
      ]),
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsHRV, trendsRMSSD, trendsHeartRate]
    )

    let rounded = try #require(
      probe.seriesRelationships.first { $0.comparison == .trendsHRVToRMSSD }
    )
    #expect(rounded.oneDecimalRoundedValueMatchCount == 1)
    #expect(rounded.wholeNumberRoundedValueMatchCount == 1)
    #expect(rounded.valueRelation == .allCompatibleAfterRounding)

    let singleton = try #require(
      probe.seriesRelationships.first { $0.comparison == .heartRateAcrossEndpoints }
    )
    #expect(singleton.timestampRelation == .rightSubset)
    #expect(singleton.subsetStride == .indeterminate)
    #expect(singleton.rightOrder == .unavailable)

    let contiguousProbe = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([
        "heartRate": points(minuteOffsets: [0, 1], values: [60, 61])
      ]),
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsHeartRate]
    )
    #expect(
      contiguousProbe.seriesRelationships.first {
        $0.comparison == .heartRateAcrossEndpoints
      }?.subsetStride == .contiguous
    )
  }

  @Test
  func comparesAlgorithmVersionsTransientlyAndChecksSimpleNightlyAggregates() throws {
    let trendsRMSSD = makeSeries(
      name: "rmssd",
      minuteOffsets: [0, 1, 2, 3],
      values: [40, 42, 46, 48]
    )
    let sameVersion = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([:], algorithmVersion: "private-version-a"),
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trendsRMSSD],
      trendsAlgorithmVersion: "private-version-a",
      nightlyHRVMilliseconds: 44
    )
    #expect(sameVersion.algorithmVersionRelationship == .exactMatch)

    let trendsConsistency = try #require(
      sameVersion.nightlyHRVConsistency.first { $0.series == .trendsRMSSD }
    )
    #expect(trendsConsistency.availability == .available)
    #expect(trendsConsistency.observationCount == 4)
    #expect(
      trendsConsistency.matchingAggregates == [
        EightSleepAggregateMatch(aggregate: .mean, precision: .exact),
        EightSleepAggregateMatch(aggregate: .median, precision: .exact),
      ]
    )
    #expect(
      sameVersion.nightlyHRVConsistency.first { $0.series == .trendsHRV }?.availability
        == .seriesUnavailable
    )

    let differentVersion = try EightSleepIntervalProbeDecoder.decode(
      intervalPayload([:], algorithmVersion: "private-version-b"),
      includePayloadShapeDiagnostics: true,
      trendsAlgorithmVersion: "private-version-a"
    )
    #expect(differentVersion.algorithmVersionRelationship == .different)
    #expect(
      differentVersion.nightlyHRVConsistency.allSatisfy {
        $0.availability == .nightlySummaryUnavailable
      }
    )
  }

  @Test
  func diagnosticsFlagControlsAllRelationshipRetention() throws {
    let trends = makeSeries(name: "hrv", minuteOffsets: [0, 1], values: [10, 11])
    let data = intervalPayload(
      ["hrv": points(minuteOffsets: [0, 1], values: [10, 11])],
      algorithmVersion: "private-version"
    )

    let disabled = try EightSleepIntervalProbeDecoder.decode(
      data,
      trendsSeries: [trends],
      trendsAlgorithmVersion: "private-version",
      nightlyHRVMilliseconds: 10.5
    )
    let enabled = try EightSleepIntervalProbeDecoder.decode(
      data,
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trends],
      trendsAlgorithmVersion: "private-version",
      nightlyHRVMilliseconds: 10.5
    )

    #expect(disabled.seriesRelationships.isEmpty)
    #expect(disabled.algorithmVersionRelationship == .notCaptured)
    #expect(disabled.nightlyHRVConsistency.isEmpty)
    #expect(enabled.seriesRelationships.count == 5)
    #expect(
      enabled.seriesRelationships.first {
        $0.comparison == .hrvAcrossEndpoints
      }?.availability == .available
    )
  }

  @Test
  func relationshipReportExcludesRawInputsAndDynamicSchemaNames() throws {
    let trends = makeSeries(
      name: "hrv",
      minuteOffsets: Array(0..<10),
      values: (0..<10).map { 654_321.987 + Double($0) }
    )
    let interval = intervalPayload(
      [
        "hrv": points(
          minuteOffsets: Array(0..<10),
          values: (0..<10).map { 654_321.987 + Double($0) }
        ),
        "privateDynamicSeriesName": points(minuteOffsets: [0], values: [987_654.321]),
      ],
      algorithmVersion: "private-interval-version"
    )
    let probe = try EightSleepIntervalProbeDecoder.decode(
      interval,
      redacting: ["private-session-secret"],
      includePayloadShapeDiagnostics: true,
      trendsSeries: [trends],
      trendsAlgorithmVersion: "private-trends-version",
      nightlyHRVMilliseconds: 654_326.487
    )
    let night = makeNight(intervalProbe: probe)

    let report = EightSleepSeriesRelationshipReport.sanitizedReport(for: night)

    #expect(report.contains("Format: series-relationship-v1"))
    #expect(report.contains("hrv: trends versus intervals"))
    #expect(report.contains("values all aligned values numerically identical"))
    #expect(report.contains("co-movement strong positive co-movement"))
    for forbidden in [
      "2099-12-31",
      "private-night-secret",
      "private-session-secret",
      "privateDynamicSeriesName",
      "2023-11-14",
      "654321.987",
      "987654.321",
      "private-interval-version",
      "private-trends-version",
      "654326.487",
    ] {
      #expect(!report.contains(forbidden))
    }
  }

  @Test
  func rendersCanonicalFixedSchemaRelationshipReport() {
    let relationship = EightSleepSeriesRelationship(
      comparison: .heartRateAcrossEndpoints,
      availability: .available,
      leftObservationCount: 7,
      rightObservationCount: 3,
      leftOrder: .ascending,
      rightOrder: .ascending,
      timestampRelation: .rightSubset,
      subsetStride: .three,
      sharedTimestampCount: 3,
      comparableValueCount: 3,
      exactValueMatchCount: 3,
      nearValueMatchCount: 0,
      oneDecimalRoundedValueMatchCount: 0,
      wholeNumberRoundedValueMatchCount: 0,
      differentValueCount: 0,
      leftDuplicateTimestampCount: 0,
      rightDuplicateTimestampCount: 0,
      valueRelation: .allExact,
      coMovement: .unavailable
    )
    let probe = EightSleepIntervalProbe(
      status: .available,
      fieldPaths: [],
      metricFields: [],
      series: [],
      seriesRelationships: [relationship],
      algorithmVersionRelationship: .exactMatch,
      nightlyHRVConsistency: [
        EightSleepNightlyHRVConsistency(
          series: .trendsRMSSD,
          availability: .available,
          observationCount: 4,
          matchingAggregates: [
            EightSleepAggregateMatch(aggregate: .mean, precision: .exact),
            EightSleepAggregateMatch(aggregate: .median, precision: .oneDecimal),
          ]
        )
      ]
    )

    let report = EightSleepSeriesRelationshipReport.sanitizedReport(
      for: makeNight(intervalProbe: probe)
    )

    #expect(
      report == """
        Sleep Relay series relationship audit - sanitized
        Format: series-relationship-v1
        Scope: selected Eight Sleep session from one decoded night
        Contains: fixed comparison labels, counts, ordering, timestamp-grid and value-match categories, coarse co-movement, opaque algorithm-version equality, and one-night simple-aggregate consistency
        Excludes: dates, timestamps, measurements, deltas, exact cadence, correlation coefficients, identifiers, algorithm-version strings, credentials, and response text
        Request profiles: trends uses model-version v2; intervals uses the endpoint default
        Convention: left and right follow the order of each comparison label
        Caveat: requests are sequential snapshots, so differences can reflect reprocessing as well as endpoint behavior
        Interpretation: these relationships cannot establish an HRV formula or turn RMSSD into Apple Health SDNN
        Method: exact means equal after JSON numeric decoding; near means an absolute difference no greater than 0.01 units or 1 ppm of magnitude; rounding categories are checked only after exact and near
        Co-movement: Pearson correlation from at least 10 unambiguous aligned pairs; weak is below 0.3 in magnitude, moderate is 0.3 to below 0.7, and strong is 0.7 or above

        Status: Available
        Comparisons: 1
        - Heart rate: trends versus intervals
          status Available | observations left 7; right 3 | order left ascending; right ascending | timestamps right grid is a subset | subset spacing every third retained timestamp | shared timestamps 3 | comparable pairs 3 | value matches exact 3; near 0; one-decimal rounding 0; whole-number rounding 0; different 0 | values all aligned values numerically identical | duplicate timestamp groups left 0; right 0 | co-movement unavailable

        HRV algorithm version relation: opaque version strings match exactly

        Nightly HRV summary consistency
        Series: 1
        - Trends rmssd | status Available | observations 4 | simple aggregates consistent on this night: mean (exact), median (same after one-decimal rounding)
        Caution: aggregate matches mean only consistent on this night; they do not identify Eight Sleep's server formula.

        Privacy check
        This fixed-schema report retains no raw interval samples. Counts are derived diagnostics and can approximate recording coverage; the report is sanitized, not anonymous.
        """
    )
  }

  private func makeSeries(
    name: String,
    minuteOffsets: [Int],
    values: [Double]
  ) -> EightSleepTimeSeries {
    let samples = zip(minuteOffsets, values).map { offset, value in
      EightSleepTimeSeriesSample(timestamp: date(minuteOffset: offset), value: value)
    }
    return EightSleepTimeSeries(
      id: "selected-session-\(name)",
      sessionID: "selected-session",
      name: name,
      sampleCount: samples.count,
      firstTimestamp: samples.first?.timestamp,
      lastTimestamp: samples.last?.timestamp,
      latestNumericValue: samples.last?.value,
      numericSamples: samples
    )
  }

  private func intervalPayload(
    _ series: [String: String],
    algorithmVersion: String? = nil
  ) -> Data {
    let body = series.keys.sorted().map { key in
      "\"\(key)\":[\(series[key] ?? "")]"
    }.joined(separator: ",")
    let versionField = algorithmVersion.map {
      "\"hrvAlgorithmVersion\":\"\($0)\","
    } ?? ""
    return Data("{\(versionField)\"timeseries\":{\(body)}}".utf8)
  }

  private func points(minuteOffsets: [Int], values: [Double]) -> String {
    zip(minuteOffsets, values).map { offset, value in
      "[\"\(timestamp(minuteOffset: offset))\",\(value)]"
    }.joined(separator: ",")
  }

  private func timestamp(minuteOffset: Int) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date(minuteOffset: minuteOffset))
  }

  private func date(minuteOffset: Int) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + Double(minuteOffset * 60))
  }

  private func makeNight(intervalProbe: EightSleepIntervalProbe?) -> EightSleepNight {
    EightSleepNight(
      id: "private-night-secret",
      day: "2099-12-31",
      presenceStart: nil,
      presenceEnd: nil,
      isProcessing: false,
      score: nil,
      sleepDurationSeconds: nil,
      averageHeartRateBPM: nil,
      explicitRestingHeartRateBPM: nil,
      reportedHRVMilliseconds: 123_456.789,
      averageRespiratoryRate: nil,
      tossAndTurns: nil,
      lightSleepSeconds: nil,
      deepSleepSeconds: nil,
      remSleepSeconds: nil,
      availableFields: ["privateDynamicSeriesName"],
      metricFields: [],
      timeSeries: [],
      latestSessionID: "private-session-secret",
      intervalProbe: intervalProbe
    )
  }
}
