import Foundation

struct EightSleepSeriesRelationshipAnalysis {
  let relationships: [EightSleepSeriesRelationship]
  let algorithmVersionRelationship: EightSleepAlgorithmVersionRelationship
  let nightlyHRVConsistency: [EightSleepNightlyHRVConsistency]
}

enum EightSleepSeriesRelationshipAnalyzer {
  static func analyze(
    trendsSeries: [EightSleepTimeSeries],
    intervalRoot: JSONValue,
    trendsAlgorithmVersion: String?,
    nightlyHRVMilliseconds: Double?
  ) -> EightSleepSeriesRelationshipAnalysis {
    let parser = SeriesTimestampParser()
    let trends = allowlistedTrendsInputs(trendsSeries)
    let intervals = allowlistedIntervalInputs(intervalRoot, parser: parser)

    return EightSleepSeriesRelationshipAnalysis(
      relationships: [
        compare(
          .trendsHRVToRMSSD,
          left: trends["hrv"],
          right: trends["rmssd"]
        ),
        compare(
          .intervalsHRVToRMSSD,
          left: intervals["hrv"],
          right: intervals["rmssd"]
        ),
        compare(
          .heartRateAcrossEndpoints,
          left: trends["heartrate"],
          right: intervals["heartrate"]
        ),
        compare(
          .hrvAcrossEndpoints,
          left: trends["hrv"],
          right: intervals["hrv"]
        ),
        compare(
          .rmssdAcrossEndpoints,
          left: trends["rmssd"],
          right: intervals["rmssd"]
        ),
      ],
      algorithmVersionRelationship: algorithmVersionRelationship(
        trendsVersion: trendsAlgorithmVersion,
        intervalsVersion: intervalAlgorithmVersion(intervalRoot)
      ),
      nightlyHRVConsistency: nightlyHRVConsistency(
        nightlyHRVMilliseconds: nightlyHRVMilliseconds,
        trendsHRV: trends["hrv"],
        trendsRMSSD: trends["rmssd"],
        intervalsHRV: intervals["hrv"],
        intervalsRMSSD: intervals["rmssd"]
      )
    )
  }

  private static func allowlistedTrendsInputs(
    _ series: [EightSleepTimeSeries]
  ) -> [String: SeriesInput] {
    let grouped = Dictionary(grouping: series) { normalizedName($0.name) }
    var result: [String: SeriesInput] = [:]

    for name in ["heartrate", "hrv", "rmssd"] {
      guard let matches = grouped[name], matches.count == 1, let match = matches.first else {
        continue
      }
      result[name] = SeriesInput(
        observations: match.numericSamples.compactMap { sample in
          guard sample.value.isFinite else { return nil }
          return SeriesObservation(timestamp: sample.timestamp, value: sample.value)
        }
      )
    }
    return result
  }

  private static func allowlistedIntervalInputs(
    _ root: JSONValue,
    parser: SeriesTimestampParser
  ) -> [String: SeriesInput] {
    guard
      let object = root.objectValue,
      let timeSeries = object["timeseries"]?.objectValue
    else { return [:] }

    let grouped = Dictionary(grouping: timeSeries.keys) { normalizedName($0) }
    var result: [String: SeriesInput] = [:]

    for name in ["heartrate", "hrv", "rmssd"] {
      guard
        let matchingKeys = grouped[name],
        matchingKeys.count == 1,
        let key = matchingKeys.first,
        let rawSamples = timeSeries[key]?.arrayValue
      else { continue }

      let observations = rawSamples.compactMap { value -> SeriesObservation? in
        guard
          let tuple = value.arrayValue,
          tuple.count == 2,
          let rawTimestamp = tuple[0].stringValue,
          case .number(let measurement) = tuple[1],
          measurement.isFinite,
          let timestamp = parser.parse(rawTimestamp)
        else { return nil }
        return SeriesObservation(timestamp: timestamp, value: measurement)
      }
      result[name] = SeriesInput(observations: observations)
    }
    return result
  }

  private static func normalizedName(_ name: String) -> String {
    name.lowercased().filter(\.isLetter)
  }

  private static func compare(
    _ comparison: EightSleepSeriesComparison,
    left: SeriesInput?,
    right: SeriesInput?
  ) -> EightSleepSeriesRelationship {
    let leftObservations = left?.observations ?? []
    let rightObservations = right?.observations ?? []
    let leftIsAvailable = !leftObservations.isEmpty
    let rightIsAvailable = !rightObservations.isEmpty
    let availability: EightSleepSeriesRelationshipAvailability
    switch (leftIsAvailable, rightIsAvailable) {
    case (true, true): availability = .available
    case (false, true): availability = .leftUnavailable
    case (true, false): availability = .rightUnavailable
    case (false, false): availability = .bothUnavailable
    }

    let leftGroups = Dictionary(grouping: leftObservations, by: \.timestamp)
    let rightGroups = Dictionary(grouping: rightObservations, by: \.timestamp)
    let leftTimestamps = Set(leftGroups.keys)
    let rightTimestamps = Set(rightGroups.keys)
    let sharedTimestamps = leftTimestamps.intersection(rightTimestamps)
    let timestampRelation = timestampRelation(
      left: leftTimestamps,
      right: rightTimestamps,
      available: availability == .available
    )

    let comparablePairs = sharedTimestamps.sorted().compactMap {
      timestamp -> (Double, Double)? in
      guard
        let leftValues = leftGroups[timestamp], leftValues.count == 1,
        let rightValues = rightGroups[timestamp], rightValues.count == 1,
        let leftValue = leftValues.first?.value,
        let rightValue = rightValues.first?.value
      else { return nil }
      return (leftValue, rightValue)
    }

    var exactMatches = 0
    var nearMatches = 0
    var oneDecimalRoundedMatches = 0
    var wholeNumberRoundedMatches = 0
    var differences = 0
    for (leftValue, rightValue) in comparablePairs {
      switch matchPrecision(leftValue, rightValue) {
      case .exact: exactMatches += 1
      case .near: nearMatches += 1
      case .oneDecimal: oneDecimalRoundedMatches += 1
      case .wholeNumber: wholeNumberRoundedMatches += 1
      case nil: differences += 1
      }
    }

    return EightSleepSeriesRelationship(
      comparison: comparison,
      availability: availability,
      leftObservationCount: leftObservations.count,
      rightObservationCount: rightObservations.count,
      leftOrder: order(of: leftObservations),
      rightOrder: order(of: rightObservations),
      timestampRelation: timestampRelation,
      subsetStride: subsetStride(
        relation: timestampRelation,
        left: leftTimestamps,
        right: rightTimestamps
      ),
      sharedTimestampCount: sharedTimestamps.count,
      comparableValueCount: comparablePairs.count,
      exactValueMatchCount: exactMatches,
      nearValueMatchCount: nearMatches,
      oneDecimalRoundedValueMatchCount: oneDecimalRoundedMatches,
      wholeNumberRoundedValueMatchCount: wholeNumberRoundedMatches,
      differentValueCount: differences,
      leftDuplicateTimestampCount: leftGroups.values.filter { $0.count > 1 }.count,
      rightDuplicateTimestampCount: rightGroups.values.filter { $0.count > 1 }.count,
      valueRelation: valueRelation(
        comparableCount: comparablePairs.count,
        exactMatches: exactMatches,
        nearMatches: nearMatches,
        oneDecimalRoundedMatches: oneDecimalRoundedMatches,
        wholeNumberRoundedMatches: wholeNumberRoundedMatches,
        differences: differences
      ),
      coMovement: coMovement(comparablePairs)
    )
  }

  private static func timestampRelation(
    left: Set<Date>,
    right: Set<Date>,
    available: Bool
  ) -> EightSleepSeriesTimestampRelation {
    guard available, !left.isEmpty, !right.isEmpty else { return .unavailable }
    if left == right { return .identical }
    if left.isSubset(of: right) { return .leftSubset }
    if right.isSubset(of: left) { return .rightSubset }
    if left.isDisjoint(with: right) { return .disjoint }
    return .partialOverlap
  }

  private static func subsetStride(
    relation: EightSleepSeriesTimestampRelation,
    left: Set<Date>,
    right: Set<Date>
  ) -> EightSleepSeriesStride {
    let subset: Set<Date>
    let superset: Set<Date>
    switch relation {
    case .leftSubset:
      subset = left
      superset = right
    case .rightSubset:
      subset = right
      superset = left
    default:
      return .notApplicable
    }

    guard subset.count >= 2 else { return .indeterminate }
    let positions = superset.sorted().enumerated().compactMap { index, timestamp in
      subset.contains(timestamp) ? index : nil
    }
    let gaps = zip(positions, positions.dropFirst()).map { pair in
      pair.1 - pair.0
    }
    guard let stride = gaps.first, gaps.allSatisfy({ $0 == stride }) else {
      return .irregular
    }
    switch stride {
    case 1: return .contiguous
    case 2: return .two
    case 3: return .three
    default: return .fourOrMore
    }
  }

  private static func order(
    of observations: [SeriesObservation]
  ) -> EightSleepSeriesOrder {
    guard observations.count >= 2 else { return .unavailable }
    let pairs = Array(zip(observations, observations.dropFirst()))
    let nondecreasing = pairs.allSatisfy { pair in
      pair.0.timestamp <= pair.1.timestamp
    }
    let nonincreasing = pairs.allSatisfy { pair in
      pair.0.timestamp >= pair.1.timestamp
    }
    let hasIncrease = pairs.contains { pair in
      pair.0.timestamp < pair.1.timestamp
    }
    let hasDecrease = pairs.contains { pair in
      pair.0.timestamp > pair.1.timestamp
    }
    if nondecreasing, hasIncrease { return .ascending }
    if nonincreasing, hasDecrease { return .descending }
    return .unordered
  }

  private static func matchPrecision(
    _ left: Double,
    _ right: Double
  ) -> EightSleepAggregateMatchPrecision? {
    if left == right { return .exact }
    let tolerance = max(0.01, 0.000_001 * max(abs(left), abs(right)))
    if abs(left - right) <= tolerance { return .near }
    if valuesMatchAfterRounding(left, right, scale: 10) { return .oneDecimal }
    if valuesMatchAfterRounding(left, right, scale: 1) { return .wholeNumber }
    return nil
  }

  private static func valuesMatchAfterRounding(
    _ left: Double,
    _ right: Double,
    scale: Double
  ) -> Bool {
    let scaledLeft = left * scale
    let scaledRight = right * scale
    guard scaledLeft.isFinite, scaledRight.isFinite else { return false }
    return scaledLeft.rounded() == scaledRight.rounded()
  }

  private static func valueRelation(
    comparableCount: Int,
    exactMatches: Int,
    nearMatches: Int,
    oneDecimalRoundedMatches: Int,
    wholeNumberRoundedMatches: Int,
    differences: Int
  ) -> EightSleepSeriesValueRelation {
    guard comparableCount > 0 else { return .unavailable }
    if exactMatches == comparableCount { return .allExact }
    if differences == 0, exactMatches + nearMatches == comparableCount {
      return .allWithinTolerance
    }
    if differences == 0,
      exactMatches + nearMatches + oneDecimalRoundedMatches + wholeNumberRoundedMatches
        == comparableCount
    {
      return .allCompatibleAfterRounding
    }
    if differences == comparableCount { return .allDifferent }
    return .mixed
  }

  private static func intervalAlgorithmVersion(_ root: JSONValue) -> String? {
    guard
      let rawVersion = root.objectValue?["hrvAlgorithmVersion"]?.stringValue,
      !rawVersion.isEmpty
    else { return nil }
    return rawVersion
  }

  private static func algorithmVersionRelationship(
    trendsVersion: String?,
    intervalsVersion: String?
  ) -> EightSleepAlgorithmVersionRelationship {
    switch (trendsVersion, intervalsVersion) {
    case (nil, nil): .bothAbsent
    case (.some, nil): .trendsOnly
    case (nil, .some): .intervalsOnly
    case (.some(let trends), .some(let intervals)):
      trends == intervals ? .exactMatch : .different
    }
  }

  private static func nightlyHRVConsistency(
    nightlyHRVMilliseconds: Double?,
    trendsHRV: SeriesInput?,
    trendsRMSSD: SeriesInput?,
    intervalsHRV: SeriesInput?,
    intervalsRMSSD: SeriesInput?
  ) -> [EightSleepNightlyHRVConsistency] {
    let inputs: [(EightSleepNightlyHRVSeries, SeriesInput?)] = [
      (.trendsHRV, trendsHRV),
      (.trendsRMSSD, trendsRMSSD),
      (.intervalsHRV, intervalsHRV),
      (.intervalsRMSSD, intervalsRMSSD),
    ]
    return inputs.map { series, input in
      nightlyHRVConsistency(
        series: series,
        nightlyHRVMilliseconds: nightlyHRVMilliseconds,
        input: input
      )
    }
  }

  private static func nightlyHRVConsistency(
    series: EightSleepNightlyHRVSeries,
    nightlyHRVMilliseconds: Double?,
    input: SeriesInput?
  ) -> EightSleepNightlyHRVConsistency {
    let values = uniqueValuesSortedByTimestamp(input?.observations ?? [])
    guard let nightlyHRVMilliseconds, nightlyHRVMilliseconds.isFinite else {
      return EightSleepNightlyHRVConsistency(
        series: series,
        availability: .nightlySummaryUnavailable,
        observationCount: values.count,
        matchingAggregates: []
      )
    }
    guard !values.isEmpty else {
      return EightSleepNightlyHRVConsistency(
        series: series,
        availability: .seriesUnavailable,
        observationCount: 0,
        matchingAggregates: []
      )
    }

    let sum = values.reduce(0, +)
    let candidates: [(EightSleepSimpleAggregate, Double?)] = [
      (.first, values.first),
      (.last, values.last),
      (.mean, sum.isFinite ? sum / Double(values.count) : nil),
      (.median, median(values)),
    ]
    let matchingAggregates = candidates.compactMap {
      aggregate, candidate -> EightSleepAggregateMatch? in
      guard
        let candidate,
        candidate.isFinite,
        let precision = matchPrecision(nightlyHRVMilliseconds, candidate)
      else { return nil }
      return EightSleepAggregateMatch(aggregate: aggregate, precision: precision)
    }
    return EightSleepNightlyHRVConsistency(
      series: series,
      availability: .available,
      observationCount: values.count,
      matchingAggregates: matchingAggregates
    )
  }

  private static func uniqueValuesSortedByTimestamp(
    _ observations: [SeriesObservation]
  ) -> [Double] {
    Dictionary(grouping: observations, by: \.timestamp)
      .filter { $0.value.count == 1 }
      .sorted { $0.key < $1.key }
      .compactMap { $0.value.first?.value }
  }

  private static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let midpoint = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[midpoint - 1] + sorted[midpoint]) / 2
    }
    return sorted[midpoint]
  }

  private static func coMovement(
    _ pairs: [(Double, Double)]
  ) -> EightSleepSeriesCoMovement {
    guard pairs.count >= 10 else { return .unavailable }
    let count = Double(pairs.count)
    let leftMean = pairs.reduce(0) { $0 + $1.0 } / count
    let rightMean = pairs.reduce(0) { $0 + $1.1 } / count
    var covariance = 0.0
    var leftSquares = 0.0
    var rightSquares = 0.0
    for (left, right) in pairs {
      let leftDelta = left - leftMean
      let rightDelta = right - rightMean
      covariance += leftDelta * rightDelta
      leftSquares += leftDelta * leftDelta
      rightSquares += rightDelta * rightDelta
    }
    let denominator = sqrt(leftSquares * rightSquares)
    guard denominator > 0, denominator.isFinite else { return .unavailable }
    let correlation = covariance / denominator
    guard correlation.isFinite else { return .unavailable }
    if correlation >= 0.7 { return .strongPositive }
    if correlation >= 0.3 { return .moderatePositive }
    if correlation <= -0.7 { return .strongNegative }
    if correlation <= -0.3 { return .moderateNegative }
    return .weak
  }
}

private struct SeriesInput {
  let observations: [SeriesObservation]
}

private struct SeriesObservation {
  let timestamp: Date
  let value: Double
}

private struct SeriesTimestampParser {
  private let fractional: ISO8601DateFormatter
  private let standard: ISO8601DateFormatter

  init() {
    fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
  }

  func parse(_ value: String) -> Date? {
    fractional.date(from: value) ?? standard.date(from: value)
  }
}
