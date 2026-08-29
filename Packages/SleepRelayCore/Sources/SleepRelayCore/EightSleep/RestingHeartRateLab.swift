import Foundation

public struct RestingHeartRateLabAnalysis: Equatable, Sendable {
  public static let algorithmVersion = "presence-low-median-v0"

  public let sampleCount: Int
  public let minimumBPM: Double?
  public let medianBPM: Double?
  public let averageBPM: Double?
  public let maximumBPM: Double?
  public let typicalCadenceSeconds: Double?
  public let experimentalLowWindowMedianBPM: Double?
  public let experimentalWindowSampleCount: Int?
  public let explanation: String

  public init(
    sampleCount: Int,
    minimumBPM: Double?,
    medianBPM: Double?,
    averageBPM: Double?,
    maximumBPM: Double?,
    typicalCadenceSeconds: Double?,
    experimentalLowWindowMedianBPM: Double?,
    experimentalWindowSampleCount: Int?,
    explanation: String
  ) {
    self.sampleCount = sampleCount
    self.minimumBPM = minimumBPM
    self.medianBPM = medianBPM
    self.averageBPM = averageBPM
    self.maximumBPM = maximumBPM
    self.typicalCadenceSeconds = typicalCadenceSeconds
    self.experimentalLowWindowMedianBPM = experimentalLowWindowMedianBPM
    self.experimentalWindowSampleCount = experimentalWindowSampleCount
    self.explanation = explanation
  }
}

public enum RestingHeartRateLab {
  private static let windowDuration: TimeInterval = 15 * 60

  public static func analyze(_ night: EightSleepNight) -> RestingHeartRateLabAnalysis {
    let samples = sanitizedHeartRateSamples(from: night)
    let values = samples.map(\.value)
    let cadence = median(positiveGaps(in: samples))
    let candidate = lowestRollingMedian(in: samples, typicalCadence: cadence)

    let explanation: String
    if samples.isEmpty {
      explanation = "No timestamped heart-rate samples were available."
    } else if candidate == nil {
      explanation =
        "Heart-rate samples were found, but no 15-minute window had enough timestamp coverage."
    } else {
      explanation =
        "Research only: this uses the lowest well-covered 15-minute median inside the bed-presence interval. Confirmed-asleep intervals are not yet available, so it cannot be written as resting heart rate."
    }

    return RestingHeartRateLabAnalysis(
      sampleCount: samples.count,
      minimumBPM: values.min(),
      medianBPM: median(values),
      averageBPM: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
      maximumBPM: values.max(),
      typicalCadenceSeconds: cadence,
      experimentalLowWindowMedianBPM: candidate?.median,
      experimentalWindowSampleCount: candidate?.sampleCount,
      explanation: explanation
    )
  }

  public static func sanitizedReport(
    for night: EightSleepNight,
    officialEightRestingHeartRateBPM: Double? = nil
  ) -> String {
    let analysis = analyze(night)
    var lines = [
      "Sleep Relay RHR Lab — sanitized report",
      "Night: \(night.day)",
      "Endpoint: GET /v1/users/{user}/trends",
      "Probe: GET /v1/users/{user}/intervals/{session}",
      "Algorithm: \(RestingHeartRateLabAnalysis.algorithmVersion)",
      "HealthKit writes: disabled",
      "",
      "Decoded values",
      "- Explicit RHR field: \(formatBPM(night.discoveredRestingHeartRateBPM))",
      "- Average sleeping HR: \(formatBPM(night.averageHeartRateBPM))",
      "- Eight HRV label: RMSSD",
      "- Eight HRV: \(format(night.reportedHRVMilliseconds, suffix: " ms"))",
      "- Respiratory rate: \(format(night.averageRespiratoryRate, suffix: " /min"))",
      "",
      "Heart-rate series",
      "- Valid timestamped samples: \(analysis.sampleCount)",
      "- Minimum: \(formatBPM(analysis.minimumBPM))",
      "- Median: \(formatBPM(analysis.medianBPM))",
      "- Average: \(formatBPM(analysis.averageBPM))",
      "- Maximum: \(formatBPM(analysis.maximumBPM))",
      "- Typical cadence: \(format(analysis.typicalCadenceSeconds, suffix: " sec"))",
      "- Experimental 15-minute low median: \(formatBPM(analysis.experimentalLowWindowMedianBPM))",
    ]

    if let officialEightRestingHeartRateBPM {
      lines.append("- Official Eight app RHR (manual): \(formatBPM(officialEightRestingHeartRateBPM))")
      if let candidate = analysis.experimentalLowWindowMedianBPM {
        lines.append(
          "- Experimental minus official: \(format(candidate - officialEightRestingHeartRateBPM, suffix: " bpm"))"
        )
      }
    } else {
      lines.append("- Official Eight app RHR (manual): not entered")
    }

    lines.append(contentsOf: ["", "Matched numeric metric paths"])
    let trendsFields = night.metricFields.map { ("trends", $0) }
    let intervalFields = (night.intervalProbe?.metricFields ?? []).map { ("intervals", $0) }
    let matchedFields = trendsFields + intervalFields
    if matchedFields.isEmpty {
      lines.append("- none")
    } else {
      lines.append(contentsOf: matchedFields.map { source, field in
        "- \(source).\(field.path): \(format(field.value, suffix: ""))"
      })
    }

    lines.append(contentsOf: [
      "",
      "Verified intervals endpoint probe",
      "- Status: \(night.intervalProbe?.status.label ?? "Not requested: no session ID")",
      "- Discovered field paths: \(night.intervalProbe?.fieldPaths.count ?? 0)",
    ])
    if let series = night.intervalProbe?.series, !series.isEmpty {
      lines.append(contentsOf: series.map {
        "- \($0.path): count \($0.sampleCount), min \(format($0.minimum, suffix: "")), median \(format($0.median, suffix: "")), max \(format($0.maximum, suffix: ""))"
      })
    } else {
      lines.append("- Matched numeric series: none")
    }

    lines.append(contentsOf: [
      "",
      "Limitation",
      analysis.explanation,
      "",
      "Privacy",
      "Contains the night date, metric field names, and health measurements. Excludes email, password, access token, user/device/session IDs, exact timestamps, and raw API payload.",
    ])
    return lines.joined(separator: "\n")
  }

  private static func sanitizedHeartRateSamples(
    from night: EightSleepNight
  ) -> [EightSleepTimeSeriesSample] {
    let samples = night.timeSeries
      .filter { normalize($0.name) == "heartrate" }
      .flatMap(\.numericSamples)
      .filter { sample in
        guard sample.value.isFinite, sample.value > 0 else { return false }
        if let start = night.presenceStart, sample.timestamp < start { return false }
        if let end = night.presenceEnd, sample.timestamp > end { return false }
        return true
      }
      .sorted { $0.timestamp < $1.timestamp }

    var deduplicated: [EightSleepTimeSeriesSample] = []
    for sample in samples {
      if deduplicated.last?.timestamp == sample.timestamp {
        deduplicated[deduplicated.count - 1] = sample
      } else {
        deduplicated.append(sample)
      }
    }
    return deduplicated
  }

  private static func positiveGaps(
    in samples: [EightSleepTimeSeriesSample]
  ) -> [TimeInterval] {
    zip(samples, samples.dropFirst()).compactMap { first, second in
      let gap = second.timestamp.timeIntervalSince(first.timestamp)
      return gap > 0 ? gap : nil
    }
  }

  private static func lowestRollingMedian(
    in samples: [EightSleepTimeSeriesSample],
    typicalCadence: TimeInterval?
  ) -> (median: Double, sampleCount: Int)? {
    guard samples.count >= 3 else { return nil }
    let allowedGap = max((typicalCadence ?? 5 * 60) * 1.75, 7.5 * 60)
    var best: (median: Double, sampleCount: Int)?

    for startIndex in samples.indices {
      let start = samples[startIndex].timestamp
      let end = start.addingTimeInterval(windowDuration)
      let window = samples[startIndex...].prefix { $0.timestamp <= end }
      let expectedCount = typicalCadence.map {
        Int((windowDuration / max($0, 1)).rounded(.down)) + 1
      } ?? 4
      let minimumSampleCount = max(3, Int((Double(expectedCount) * 0.6).rounded(.up)))
      guard window.count >= minimumSampleCount, let last = window.last else { continue }
      guard last.timestamp.timeIntervalSince(start) >= 10 * 60 else { continue }

      let hasLargeGap = zip(window, window.dropFirst()).contains { first, second in
        second.timestamp.timeIntervalSince(first.timestamp) > allowedGap
      }
      guard !hasLargeGap, let windowMedian = median(window.map(\.value)) else { continue }

      if best == nil || windowMedian < best!.median {
        best = (windowMedian, window.count)
      }
    }
    return best
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

  private static func normalize(_ value: String) -> String {
    value.lowercased().filter(\.isLetter)
  }

  private static func formatBPM(_ value: Double?) -> String {
    format(value, suffix: " bpm")
  }

  private static func format(_ value: Double?, suffix: String) -> String {
    guard let value else { return "not present" }
    return value.formatted(.number.precision(.fractionLength(0...2))) + suffix
  }
}
