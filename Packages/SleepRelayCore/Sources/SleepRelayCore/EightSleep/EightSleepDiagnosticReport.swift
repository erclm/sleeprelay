import Foundation

public enum EightSleepDiagnosticReport {
  public static let formatVersion = "payload-shape-v1"

  /// A structure-only report intended to be safe to copy from an Internal build.
  /// It does not include the night date, metric values, raw samples, recognized
  /// identifier values, credentials, request details, response text, or absolute
  /// timestamps.
  public static func sanitizedStructureReport(for night: EightSleepNight) -> String {
    var lines = [
      "Sleep Relay payload structure - sanitized",
      "Format: \(formatVersion)",
      "Scope: one decoded Eight Sleep night",
      "Contains: sanitized JSON paths, value kinds, counts, and broad relative-cadence buckets",
      "Excludes: primitive payload values, dates, absolute timestamps, exact cadence, raw samples, credentials, and recognized identifiers",
      "Review note: field names come from a private schema; inspect paths before sharing in case an unknown identifier is used as a field name",
      "",
      "Selected trends days[] object",
      "Endpoint: GET /v1/users/{user}/trends",
      night.trendsPathSummaries.isEmpty
        ? "Status: Not included in this refresh"
        : "Status: Available",
    ]
    append(night.trendsPathSummaries, to: &lines)

    lines.append(contentsOf: [
      "",
      "Intervals response",
      "Endpoint: GET /v1/users/{user}/intervals/{session}",
    ])

    if let probe = night.intervalProbe {
      switch probe.status {
      case .available:
        lines.append(
          probe.pathSummaries.isEmpty
            ? "Status: Not included in this refresh"
            : "Status: Available"
        )
      case .unavailable(let reason):
        lines.append("Status: Unavailable (\(sanitizedUnavailableReason(reason)))")
      }
      append(probe.pathSummaries, to: &lines)
    } else if night.latestSessionID == nil {
      lines.append("Status: Not requested because no session reference was decoded")
      append([], to: &lines)
    } else {
      lines.append("Status: Not included in this refresh")
      append([], to: &lines)
    }

    lines.append(contentsOf: [
      "",
      "Privacy check",
      "This copied report is generated from an in-memory structural summary and contains no primitive response values or raw response text.",
    ])
    return lines.joined(separator: "\n")
  }

  public static func summaryDescription(_ summary: EightSleepProbePathSummary) -> String {
    var components = [
      summary.kindCounts.sorted { $0.kind.rawValue < $1.kind.rawValue }
        .map { "\($0.kind.label) x\($0.count)" }
        .joined(separator: ", ")
    ]

    if summary.arrayInstanceCount > 0 {
      var arrayDescription =
        "arrays \(summary.arrayInstanceCount); items total \(summary.totalArrayElementCount)"
      if let minimum = summary.minimumArrayElementCount,
        let maximum = summary.maximumArrayElementCount
      {
        arrayDescription += minimum == maximum
          ? "; length \(minimum)"
          : "; length \(minimum)...\(maximum)"
      }
      components.append(arrayDescription)
    }

    if summary.timestampObservationCount > 0 {
      var cadence =
        "timestamp-like items \(summary.timestampObservationCount); sampled positive gaps \(summary.cadenceGapCount)"
      if let bucket = summary.typicalCadenceBucket {
        cadence += "; typical cadence \(bucket.label)"
      }
      if summary.cadenceSampleWasCapped { cadence += "; sample capped" }
      components.append(cadence)
    }

    return components.filter { !$0.isEmpty }.joined(separator: " | ")
  }

  private static func append(
    _ summaries: [EightSleepProbePathSummary],
    to lines: inout [String]
  ) {
    lines.append("Paths: \(summaries.count)")
    if summaries.isEmpty {
      lines.append("- none")
      return
    }

    lines.append(contentsOf: summaries.sorted { $0.path < $1.path }.map { summary in
      "- \(summary.path) | \(summaryDescription(summary))"
    })
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
