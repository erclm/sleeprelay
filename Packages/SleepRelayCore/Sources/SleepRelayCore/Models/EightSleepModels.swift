import Foundation

public struct EightSleepCredentials: Codable, Equatable, Sendable {
  public let email: String
  public let password: String

  public init(email: String, password: String) {
    self.email = email
    self.password = password
  }
}

public struct EightSleepFetchRequest: Equatable, Sendable {
  public let from: String
  public let to: String
  public let timeZoneIdentifier: String
  public let includeIntervalProbes: Bool
  public let includePayloadShapeDiagnostics: Bool

  public init(
    from: String,
    to: String,
    timeZoneIdentifier: String,
    includeIntervalProbes: Bool = true,
    includePayloadShapeDiagnostics: Bool = false
  ) {
    self.from = from
    self.to = to
    self.timeZoneIdentifier = timeZoneIdentifier
    self.includeIntervalProbes = includeIntervalProbes
    self.includePayloadShapeDiagnostics = includePayloadShapeDiagnostics
  }
}

public struct EightSleepSnapshot: Equatable, Sendable {
  public let fetchedAt: Date
  public let nights: [EightSleepNight]

  public init(fetchedAt: Date, nights: [EightSleepNight]) {
    self.fetchedAt = fetchedAt
    self.nights = nights
  }
}

public struct EightSleepNight: Identifiable, Hashable, Sendable {
  public let id: String
  public let day: String
  public let presenceStart: Date?
  public let presenceEnd: Date?
  public let isProcessing: Bool
  public let score: Double?
  public let sleepDurationSeconds: Double?
  public let averageHeartRateBPM: Double?
  public let explicitRestingHeartRateBPM: Double?
  public let reportedHRVMilliseconds: Double?
  public let averageRespiratoryRate: Double?
  public let tossAndTurns: Double?
  public let lightSleepSeconds: Double?
  public let deepSleepSeconds: Double?
  public let remSleepSeconds: Double?
  public let availableFields: [String]
  public let metricFields: [EightSleepMetricField]
  public let timeSeries: [EightSleepTimeSeries]
  public let latestSessionID: String?
  public internal(set) var intervalProbe: EightSleepIntervalProbe?
  public let trendsPathSummaries: [EightSleepProbePathSummary]

  var diagnosticNightlyHRVCurrentMilliseconds: Double? {
    metricFields.first { $0.path == "sleepQualityScore.hrv.current" }?.value
  }

  public var discoveredRestingHeartRateBPM: Double? {
    explicitRestingHeartRateBPM
      ?? intervalProbe?.metricFields.first(where: { field in
        let normalized = field.path.lowercased().filter(\.isLetter)
        return normalized.contains("restingheartrate") || normalized.hasSuffix("rhr")
      })?.value
  }

  public init(
    id: String,
    day: String,
    presenceStart: Date?,
    presenceEnd: Date?,
    isProcessing: Bool,
    score: Double?,
    sleepDurationSeconds: Double?,
    averageHeartRateBPM: Double?,
    explicitRestingHeartRateBPM: Double?,
    reportedHRVMilliseconds: Double?,
    averageRespiratoryRate: Double?,
    tossAndTurns: Double?,
    lightSleepSeconds: Double?,
    deepSleepSeconds: Double?,
    remSleepSeconds: Double?,
    availableFields: [String],
    metricFields: [EightSleepMetricField],
    timeSeries: [EightSleepTimeSeries],
    latestSessionID: String?,
    intervalProbe: EightSleepIntervalProbe?,
    trendsPathSummaries: [EightSleepProbePathSummary] = []
  ) {
    self.id = id
    self.day = day
    self.presenceStart = presenceStart
    self.presenceEnd = presenceEnd
    self.isProcessing = isProcessing
    self.score = score
    self.sleepDurationSeconds = sleepDurationSeconds
    self.averageHeartRateBPM = averageHeartRateBPM
    self.explicitRestingHeartRateBPM = explicitRestingHeartRateBPM
    self.reportedHRVMilliseconds = reportedHRVMilliseconds
    self.averageRespiratoryRate = averageRespiratoryRate
    self.tossAndTurns = tossAndTurns
    self.lightSleepSeconds = lightSleepSeconds
    self.deepSleepSeconds = deepSleepSeconds
    self.remSleepSeconds = remSleepSeconds
    self.availableFields = availableFields
    self.metricFields = metricFields
    self.timeSeries = timeSeries
    self.latestSessionID = latestSessionID
    self.intervalProbe = intervalProbe
    self.trendsPathSummaries = trendsPathSummaries
  }
}

public struct EightSleepMetricField: Identifiable, Hashable, Sendable {
  public var id: String { path }

  public let path: String
  public let value: Double

  public init(path: String, value: Double) {
    self.path = path
    self.value = value
  }
}

public struct EightSleepTimeSeriesSample: Hashable, Sendable {
  public let timestamp: Date
  public let value: Double

  public init(timestamp: Date, value: Double) {
    self.timestamp = timestamp
    self.value = value
  }
}

public struct EightSleepTimeSeries: Identifiable, Hashable, Sendable {
  public let id: String
  public let sessionID: String
  public let name: String
  public let sampleCount: Int
  public let firstTimestamp: Date?
  public let lastTimestamp: Date?
  public let latestNumericValue: Double?
  public let numericSamples: [EightSleepTimeSeriesSample]

  public init(
    id: String,
    sessionID: String,
    name: String,
    sampleCount: Int,
    firstTimestamp: Date?,
    lastTimestamp: Date?,
    latestNumericValue: Double?,
    numericSamples: [EightSleepTimeSeriesSample]
  ) {
    self.id = id
    self.sessionID = sessionID
    self.name = name
    self.sampleCount = sampleCount
    self.firstTimestamp = firstTimestamp
    self.lastTimestamp = lastTimestamp
    self.latestNumericValue = latestNumericValue
    self.numericSamples = numericSamples
  }
}

public enum EightSleepIntervalProbeStatus: Equatable, Hashable, Sendable {
  case available
  case unavailable(reason: String)

  public var label: String {
    switch self {
    case .available: "Available"
    case .unavailable(let reason): reason
    }
  }
}

public struct EightSleepSeriesSummary: Identifiable, Hashable, Sendable {
  public var id: String { path }

  public let path: String
  public let sampleCount: Int
  public let minimum: Double
  public let median: Double
  public let maximum: Double

  public init(
    path: String,
    sampleCount: Int,
    minimum: Double,
    median: Double,
    maximum: Double
  ) {
    self.path = path
    self.sampleCount = sampleCount
    self.minimum = minimum
    self.median = median
    self.maximum = maximum
  }
}

public enum EightSleepProbeValueKind: String, CaseIterable, Hashable, Sendable {
  case array
  case boolean
  case null
  case number
  case numericString
  case object
  case text
  case timestampString

  public var label: String {
    switch self {
    case .array: "array"
    case .boolean: "boolean"
    case .null: "null"
    case .number: "number"
    case .numericString: "numeric string"
    case .object: "object"
    case .text: "text"
    case .timestampString: "timestamp string"
    }
  }
}

public struct EightSleepProbeKindCount: Hashable, Sendable {
  public let kind: EightSleepProbeValueKind
  public let count: Int

  public init(kind: EightSleepProbeValueKind, count: Int) {
    self.kind = kind
    self.count = count
  }
}

public enum EightSleepProbeCadenceBucket: String, CaseIterable, Hashable, Sendable {
  case underTenMilliseconds
  case tenToHundredMilliseconds
  case hundredMillisecondsToOneSecond
  case oneToTenSeconds
  case tenSecondsToOneMinute
  case oneToTenMinutes
  case tenMinutesToOneHour
  case overOneHour

  public var label: String {
    switch self {
    case .underTenMilliseconds: "under 10 ms"
    case .tenToHundredMilliseconds: "10-100 ms"
    case .hundredMillisecondsToOneSecond: "100 ms-1 sec"
    case .oneToTenSeconds: "1-10 sec"
    case .tenSecondsToOneMinute: "10-60 sec"
    case .oneToTenMinutes: "1-10 min"
    case .tenMinutesToOneHour: "10-60 min"
    case .overOneHour: "1 hour or more"
    }
  }
}

/// A value-free description of one JSON path in an Eight Sleep response.
///
/// It intentionally retains only schema names, JSON kinds, counts, and a broad
/// relative-cadence bucket. It never retains payload values or absolute timestamps.
public struct EightSleepProbePathSummary: Identifiable, Hashable, Sendable {
  public var id: String { path }

  public let path: String
  public let kindCounts: [EightSleepProbeKindCount]
  public let arrayInstanceCount: Int
  public let totalArrayElementCount: Int
  public let minimumArrayElementCount: Int?
  public let maximumArrayElementCount: Int?
  public let timestampObservationCount: Int
  public let cadenceGapCount: Int
  public let typicalCadenceBucket: EightSleepProbeCadenceBucket?
  public let cadenceSampleWasCapped: Bool

  public init(
    path: String,
    kindCounts: [EightSleepProbeKindCount],
    arrayInstanceCount: Int = 0,
    totalArrayElementCount: Int = 0,
    minimumArrayElementCount: Int? = nil,
    maximumArrayElementCount: Int? = nil,
    timestampObservationCount: Int = 0,
    cadenceGapCount: Int = 0,
    typicalCadenceBucket: EightSleepProbeCadenceBucket? = nil,
    cadenceSampleWasCapped: Bool = false
  ) {
    self.path = path
    self.kindCounts = kindCounts
    self.arrayInstanceCount = arrayInstanceCount
    self.totalArrayElementCount = totalArrayElementCount
    self.minimumArrayElementCount = minimumArrayElementCount
    self.maximumArrayElementCount = maximumArrayElementCount
    self.timestampObservationCount = timestampObservationCount
    self.cadenceGapCount = cadenceGapCount
    self.typicalCadenceBucket = typicalCadenceBucket
    self.cadenceSampleWasCapped = cadenceSampleWasCapped
  }
}

public struct EightSleepIntervalProbe: Hashable, Sendable {
  public let status: EightSleepIntervalProbeStatus
  public let fieldPaths: [String]
  public let metricFields: [EightSleepMetricField]
  public let series: [EightSleepSeriesSummary]
  public let pathSummaries: [EightSleepProbePathSummary]
  public let seriesRelationships: [EightSleepSeriesRelationship]
  public let algorithmVersionRelationship: EightSleepAlgorithmVersionRelationship
  public let nightlyHRVConsistency: [EightSleepNightlyHRVConsistency]

  public init(
    status: EightSleepIntervalProbeStatus,
    fieldPaths: [String],
    metricFields: [EightSleepMetricField],
    series: [EightSleepSeriesSummary],
    pathSummaries: [EightSleepProbePathSummary] = [],
    seriesRelationships: [EightSleepSeriesRelationship] = [],
    algorithmVersionRelationship: EightSleepAlgorithmVersionRelationship = .notCaptured,
    nightlyHRVConsistency: [EightSleepNightlyHRVConsistency] = []
  ) {
    self.status = status
    self.fieldPaths = fieldPaths
    self.metricFields = metricFields
    self.series = series
    self.pathSummaries = pathSummaries
    self.seriesRelationships = seriesRelationships
    self.algorithmVersionRelationship = algorithmVersionRelationship
    self.nightlyHRVConsistency = nightlyHRVConsistency
  }

  public static func unavailable(_ reason: String) -> EightSleepIntervalProbe {
    EightSleepIntervalProbe(
      status: .unavailable(reason: reason),
      fieldPaths: [],
      metricFields: [],
      series: [],
      pathSummaries: [],
      seriesRelationships: [],
      algorithmVersionRelationship: .notCaptured,
      nightlyHRVConsistency: []
    )
  }
}

public enum EightSleepSeriesComparison: String, CaseIterable, Hashable, Sendable {
  case trendsHRVToRMSSD
  case intervalsHRVToRMSSD
  case heartRateAcrossEndpoints
  case hrvAcrossEndpoints
  case rmssdAcrossEndpoints

  public var label: String {
    switch self {
    case .trendsHRVToRMSSD: "Trends hrv versus trends rmssd"
    case .intervalsHRVToRMSSD: "Intervals hrv versus intervals rmssd"
    case .heartRateAcrossEndpoints: "Heart rate: trends versus intervals"
    case .hrvAcrossEndpoints: "hrv: trends versus intervals"
    case .rmssdAcrossEndpoints: "rmssd: trends versus intervals"
    }
  }
}

public enum EightSleepSeriesRelationshipAvailability: String, Hashable, Sendable {
  case available
  case leftUnavailable
  case rightUnavailable
  case bothUnavailable

  public var label: String {
    switch self {
    case .available: "Available"
    case .leftUnavailable: "Left series unavailable"
    case .rightUnavailable: "Right series unavailable"
    case .bothUnavailable: "Both series unavailable"
    }
  }
}

public enum EightSleepSeriesOrder: String, Hashable, Sendable {
  case ascending
  case descending
  case unordered
  case unavailable

  public var label: String {
    switch self {
    case .ascending: "ascending"
    case .descending: "descending"
    case .unordered: "unordered or duplicate-only"
    case .unavailable: "unavailable"
    }
  }
}

public enum EightSleepSeriesTimestampRelation: String, Hashable, Sendable {
  case identical
  case leftSubset
  case rightSubset
  case partialOverlap
  case disjoint
  case unavailable

  public var label: String {
    switch self {
    case .identical: "identical grids"
    case .leftSubset: "left grid is a subset"
    case .rightSubset: "right grid is a subset"
    case .partialOverlap: "partially overlapping grids"
    case .disjoint: "disjoint grids"
    case .unavailable: "unavailable"
    }
  }
}

public enum EightSleepSeriesStride: String, Hashable, Sendable {
  case contiguous
  case two
  case three
  case fourOrMore
  case irregular
  case indeterminate
  case notApplicable

  public var label: String {
    switch self {
    case .contiguous: "contiguous retained timestamps"
    case .two: "every second retained timestamp"
    case .three: "every third retained timestamp"
    case .fourOrMore: "every fourth-or-later retained timestamp"
    case .irregular: "irregular retained-timestamp spacing"
    case .indeterminate: "indeterminate from one timestamp"
    case .notApplicable: "not applicable"
    }
  }
}

public enum EightSleepSeriesValueRelation: String, Hashable, Sendable {
  case allExact
  case allWithinTolerance
  case allCompatibleAfterRounding
  case mixed
  case allDifferent
  case unavailable

  public var label: String {
    switch self {
    case .allExact: "all aligned values numerically identical"
    case .allWithinTolerance: "all aligned values identical or near-equal"
    case .allCompatibleAfterRounding: "all aligned values compatible after rounding"
    case .mixed: "mixed aligned-value relationship"
    case .allDifferent: "all aligned values different"
    case .unavailable: "unavailable"
    }
  }
}

public enum EightSleepSeriesCoMovement: String, Hashable, Sendable {
  case strongPositive
  case moderatePositive
  case weak
  case moderateNegative
  case strongNegative
  case unavailable

  public var label: String {
    switch self {
    case .strongPositive: "strong positive co-movement"
    case .moderatePositive: "moderate positive co-movement"
    case .weak: "weak co-movement"
    case .moderateNegative: "moderate negative co-movement"
    case .strongNegative: "strong negative co-movement"
    case .unavailable: "unavailable"
    }
  }
}

/// A fixed-schema, value-free comparison generated while both endpoint
/// responses are in memory. It retains counts and categorical relationships,
/// but no timestamps, measurements, identifiers, or response strings.
public struct EightSleepSeriesRelationship: Identifiable, Hashable, Sendable {
  public var id: String { comparison.rawValue }

  public let comparison: EightSleepSeriesComparison
  public let availability: EightSleepSeriesRelationshipAvailability
  public let leftObservationCount: Int
  public let rightObservationCount: Int
  public let leftOrder: EightSleepSeriesOrder
  public let rightOrder: EightSleepSeriesOrder
  public let timestampRelation: EightSleepSeriesTimestampRelation
  public let subsetStride: EightSleepSeriesStride
  public let sharedTimestampCount: Int
  public let comparableValueCount: Int
  public let exactValueMatchCount: Int
  public let nearValueMatchCount: Int
  public let oneDecimalRoundedValueMatchCount: Int
  public let wholeNumberRoundedValueMatchCount: Int
  public let differentValueCount: Int
  public let leftDuplicateTimestampCount: Int
  public let rightDuplicateTimestampCount: Int
  public let valueRelation: EightSleepSeriesValueRelation
  public let coMovement: EightSleepSeriesCoMovement

  public init(
    comparison: EightSleepSeriesComparison,
    availability: EightSleepSeriesRelationshipAvailability,
    leftObservationCount: Int,
    rightObservationCount: Int,
    leftOrder: EightSleepSeriesOrder,
    rightOrder: EightSleepSeriesOrder,
    timestampRelation: EightSleepSeriesTimestampRelation,
    subsetStride: EightSleepSeriesStride,
    sharedTimestampCount: Int,
    comparableValueCount: Int,
    exactValueMatchCount: Int,
    nearValueMatchCount: Int,
    oneDecimalRoundedValueMatchCount: Int,
    wholeNumberRoundedValueMatchCount: Int,
    differentValueCount: Int,
    leftDuplicateTimestampCount: Int,
    rightDuplicateTimestampCount: Int,
    valueRelation: EightSleepSeriesValueRelation,
    coMovement: EightSleepSeriesCoMovement
  ) {
    self.comparison = comparison
    self.availability = availability
    self.leftObservationCount = leftObservationCount
    self.rightObservationCount = rightObservationCount
    self.leftOrder = leftOrder
    self.rightOrder = rightOrder
    self.timestampRelation = timestampRelation
    self.subsetStride = subsetStride
    self.sharedTimestampCount = sharedTimestampCount
    self.comparableValueCount = comparableValueCount
    self.exactValueMatchCount = exactValueMatchCount
    self.nearValueMatchCount = nearValueMatchCount
    self.oneDecimalRoundedValueMatchCount = oneDecimalRoundedValueMatchCount
    self.wholeNumberRoundedValueMatchCount = wholeNumberRoundedValueMatchCount
    self.differentValueCount = differentValueCount
    self.leftDuplicateTimestampCount = leftDuplicateTimestampCount
    self.rightDuplicateTimestampCount = rightDuplicateTimestampCount
    self.valueRelation = valueRelation
    self.coMovement = coMovement
  }
}

public enum EightSleepAlgorithmVersionRelationship: String, Hashable, Sendable {
  case notCaptured
  case bothAbsent
  case trendsOnly
  case intervalsOnly
  case exactMatch
  case different

  public var label: String {
    switch self {
    case .notCaptured: "not captured"
    case .bothAbsent: "absent from both responses"
    case .trendsOnly: "present only in trends"
    case .intervalsOnly: "present only in intervals"
    case .exactMatch: "opaque version strings match exactly"
    case .different: "opaque version strings differ"
    }
  }
}

public enum EightSleepNightlyHRVSeries: String, CaseIterable, Hashable, Sendable {
  case trendsHRV
  case trendsRMSSD
  case intervalsHRV
  case intervalsRMSSD

  public var label: String {
    switch self {
    case .trendsHRV: "Trends hrv"
    case .trendsRMSSD: "Trends rmssd"
    case .intervalsHRV: "Intervals hrv"
    case .intervalsRMSSD: "Intervals rmssd"
    }
  }
}

public enum EightSleepNightlyHRVConsistencyAvailability: String, Hashable, Sendable {
  case available
  case nightlySummaryUnavailable
  case seriesUnavailable

  public var label: String {
    switch self {
    case .available: "Available"
    case .nightlySummaryUnavailable: "Nightly HRV summary unavailable"
    case .seriesUnavailable: "Series unavailable"
    }
  }
}

public enum EightSleepSimpleAggregate: String, CaseIterable, Hashable, Sendable {
  case first
  case last
  case mean
  case median

  public var label: String { rawValue }
}

public enum EightSleepAggregateMatchPrecision: String, Hashable, Sendable {
  case exact
  case near
  case oneDecimal
  case wholeNumber

  public var label: String {
    switch self {
    case .exact: "exact"
    case .near: "near-equal"
    case .oneDecimal: "same after one-decimal rounding"
    case .wholeNumber: "same after whole-number rounding"
    }
  }
}

public struct EightSleepAggregateMatch: Hashable, Sendable {
  public let aggregate: EightSleepSimpleAggregate
  public let precision: EightSleepAggregateMatchPrecision

  public init(
    aggregate: EightSleepSimpleAggregate,
    precision: EightSleepAggregateMatchPrecision
  ) {
    self.aggregate = aggregate
    self.precision = precision
  }
}

/// Reports only whether a server-provided nightly HRV summary is consistent
/// with a few simple aggregates on this one night. It does not identify the
/// server formula and retains neither the summary nor any series values.
public struct EightSleepNightlyHRVConsistency: Identifiable, Hashable, Sendable {
  public var id: String { series.rawValue }

  public let series: EightSleepNightlyHRVSeries
  public let availability: EightSleepNightlyHRVConsistencyAvailability
  public let observationCount: Int
  public let matchingAggregates: [EightSleepAggregateMatch]

  public init(
    series: EightSleepNightlyHRVSeries,
    availability: EightSleepNightlyHRVConsistencyAvailability,
    observationCount: Int,
    matchingAggregates: [EightSleepAggregateMatch]
  ) {
    self.series = series
    self.availability = availability
    self.observationCount = observationCount
    self.matchingAggregates = matchingAggregates
  }
}
