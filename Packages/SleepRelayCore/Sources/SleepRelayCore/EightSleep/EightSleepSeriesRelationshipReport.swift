import Foundation

public enum EightSleepSeriesRelationshipReport {
  public static let formatVersion = "series-relationship-v1"

  /// A fixed-schema report that contains relationship categories and counts,
  /// but no payload timestamps, measurements, identifiers, or response text.
  public static func sanitizedReport(for night: EightSleepNight) -> String {
    let relationships = night.intervalProbe?.seriesRelationships ?? []
    var lines = [
      "Sleep Relay series relationship audit - sanitized",
      "Format: \(formatVersion)",
      "Scope: selected Eight Sleep session from one decoded night",
      "Contains: fixed comparison labels, counts, ordering, timestamp-grid and value-match categories, coarse co-movement, opaque algorithm-version equality, and one-night simple-aggregate consistency",
      "Excludes: dates, timestamps, measurements, deltas, exact cadence, correlation coefficients, identifiers, algorithm-version strings, credentials, and response text",
      "Request profiles: trends uses model-version v2; intervals uses the endpoint default",
      "Convention: left and right follow the order of each comparison label",
      "Caveat: requests are sequential snapshots, so differences can reflect reprocessing as well as endpoint behavior",
      "Interpretation: these relationships cannot establish an HRV formula or turn RMSSD into Apple Health SDNN",
      "Method: exact means equal after JSON numeric decoding; near means an absolute difference no greater than 0.01 units or 1 ppm of magnitude; rounding categories are checked only after exact and near",
      "Co-movement: Pearson correlation from at least 10 unambiguous aligned pairs; weak is below 0.3 in magnitude, moderate is 0.3 to below 0.7, and strong is 0.7 or above",
      "",
      "Status: \(status(for: night))",
      "Comparisons: \(relationships.count)",
    ]

    if relationships.isEmpty {
      lines.append("- none")
    } else {
      for relationship in relationships.sorted(by: comparisonOrder) {
        lines.append("- \(relationship.comparison.label)")
        lines.append("  \(summaryDescription(relationship))")
      }
    }

    lines.append(contentsOf: [
      "",
      "HRV algorithm version relation: \(night.intervalProbe?.algorithmVersionRelationship.label ?? EightSleepAlgorithmVersionRelationship.notCaptured.label)",
      "",
      "Nightly HRV summary consistency",
    ])
    let consistency = night.intervalProbe?.nightlyHRVConsistency ?? []
    lines.append("Series: \(consistency.count)")
    if consistency.isEmpty {
      lines.append("- none")
    } else {
      for item in consistency.sorted(by: consistencyOrder) {
        lines.append("- \(item.series.label) | \(nightlySummaryDescription(item))")
      }
    }
    lines.append(
      "Caution: aggregate matches mean only consistent on this night; they do not identify Eight Sleep's server formula."
    )

    lines.append(contentsOf: [
      "",
      "Privacy check",
      "This fixed-schema report retains no raw interval samples. Counts are derived diagnostics and can approximate recording coverage; the report is sanitized, not anonymous.",
    ])
    return lines.joined(separator: "\n")
  }

  public static func summaryDescription(
    _ relationship: EightSleepSeriesRelationship
  ) -> String {
    guard relationship.availability == .available else {
      return [
        "status \(relationship.availability.label)",
        "observations left \(relationship.leftObservationCount); right \(relationship.rightObservationCount)",
      ].joined(separator: " | ")
    }

    var parts = [
      "status Available",
      "observations left \(relationship.leftObservationCount); right \(relationship.rightObservationCount)",
      "order left \(relationship.leftOrder.label); right \(relationship.rightOrder.label)",
      "timestamps \(relationship.timestampRelation.label)",
    ]
    if relationship.subsetStride != .notApplicable {
      parts.append("subset spacing \(relationship.subsetStride.label)")
    }
    parts.append("shared timestamps \(relationship.sharedTimestampCount)")
    parts.append("comparable pairs \(relationship.comparableValueCount)")
    parts.append(
      "value matches exact \(relationship.exactValueMatchCount); near \(relationship.nearValueMatchCount); one-decimal rounding \(relationship.oneDecimalRoundedValueMatchCount); whole-number rounding \(relationship.wholeNumberRoundedValueMatchCount); different \(relationship.differentValueCount)"
    )
    parts.append("values \(relationship.valueRelation.label)")
    parts.append(
      "duplicate timestamp groups left \(relationship.leftDuplicateTimestampCount); right \(relationship.rightDuplicateTimestampCount)"
    )
    parts.append("co-movement \(relationship.coMovement.label)")
    return parts.joined(separator: " | ")
  }

  public static func nightlySummaryDescription(
    _ consistency: EightSleepNightlyHRVConsistency
  ) -> String {
    guard consistency.availability == .available else {
      return "status \(consistency.availability.label) | observations \(consistency.observationCount)"
    }
    let matches = consistency.matchingAggregates.map { match in
      "\(match.aggregate.label) (\(match.precision.label))"
    }.joined(separator: ", ")
    return [
      "status Available",
      "observations \(consistency.observationCount)",
      "simple aggregates consistent on this night: \(matches.isEmpty ? "none" : matches)",
    ].joined(separator: " | ")
  }

  private static func comparisonOrder(
    _ left: EightSleepSeriesRelationship,
    _ right: EightSleepSeriesRelationship
  ) -> Bool {
    let order = Dictionary(
      uniqueKeysWithValues: EightSleepSeriesComparison.allCases.enumerated().map {
        ($0.element, $0.offset)
      }
    )
    return order[left.comparison, default: 0] < order[right.comparison, default: 0]
  }

  private static func consistencyOrder(
    _ left: EightSleepNightlyHRVConsistency,
    _ right: EightSleepNightlyHRVConsistency
  ) -> Bool {
    let order = Dictionary(
      uniqueKeysWithValues: EightSleepNightlyHRVSeries.allCases.enumerated().map {
        ($0.element, $0.offset)
      }
    )
    return order[left.series, default: 0] < order[right.series, default: 0]
  }

  private static func status(for night: EightSleepNight) -> String {
    guard let probe = night.intervalProbe else {
      return night.latestSessionID == nil
        ? "Not requested because no session reference was decoded"
        : "Not included in this refresh"
    }
    switch probe.status {
    case .available:
      return probe.seriesRelationships.isEmpty
        ? "Not included in this refresh"
        : "Available"
    case .unavailable(let reason):
      return "Unavailable (\(sanitizedUnavailableReason(reason)))"
    }
  }

  private static func sanitizedUnavailableReason(_ reason: String) -> String {
    switch reason {
    case "Request failed", "Unexpected response shape", "Session expired", "Rate limited",
      "Endpoint unavailable (HTTP 404)":
      return reason
    default:
      if reason.range(of: #"^HTTP [1-5][0-9][0-9]$"#, options: .regularExpression) != nil {
        return reason
      }
      return "Unavailable"
    }
  }
}
