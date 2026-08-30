import Foundation

enum EightSleepIntervalProbeDecoder {
  static func decode(
    _ data: Data,
    redacting identifiers: Set<String> = [],
    includePayloadShapeDiagnostics: Bool = false,
    trendsSeries: [EightSleepTimeSeries] = [],
    trendsAlgorithmVersion: String? = nil,
    nightlyHRVMilliseconds: Double? = nil
  ) throws -> EightSleepIntervalProbe {
    let root = try JSONDecoder().decode(JSONValue.self, from: data)
    var fieldPaths = Set<String>()
    var metricValues: [String: Double] = [:]
    var seriesByPath: [String: EightSleepSeriesSummary] = [:]
    let relationshipAnalysis = includePayloadShapeDiagnostics
      ? EightSleepSeriesRelationshipAnalyzer.analyze(
        trendsSeries: trendsSeries,
        intervalRoot: root,
        trendsAlgorithmVersion: trendsAlgorithmVersion,
        nightlyHRVMilliseconds: nightlyHRVMilliseconds
      )
      : nil

    inspect(
      root,
      path: [],
      insideArray: false,
      fieldPaths: &fieldPaths,
      metricValues: &metricValues,
      seriesByPath: &seriesByPath,
      redacting: identifiers
    )

    return EightSleepIntervalProbe(
      status: .available,
      fieldPaths: fieldPaths.sorted(),
      metricFields: metricValues.keys.sorted().compactMap { path in
        metricValues[path].map { EightSleepMetricField(path: path, value: $0) }
      },
      series: seriesByPath.keys.sorted().compactMap { seriesByPath[$0] },
      pathSummaries: includePayloadShapeDiagnostics
        ? EightSleepPayloadShapeAnalyzer.summarize(
          root,
          redacting: identifiers
        )
        : [],
      seriesRelationships: relationshipAnalysis?.relationships ?? [],
      algorithmVersionRelationship: relationshipAnalysis?.algorithmVersionRelationship
        ?? .notCaptured,
      nightlyHRVConsistency: relationshipAnalysis?.nightlyHRVConsistency ?? []
    )
  }

  private static func inspect(
    _ value: JSONValue,
    path: [String],
    insideArray: Bool,
    fieldPaths: inout Set<String>,
    metricValues: inout [String: Double],
    seriesByPath: inout [String: EightSleepSeriesSummary],
    redacting identifiers: Set<String>
  ) {
    switch value {
    case .object(let object):
      if object.isEmpty, !path.isEmpty {
        fieldPaths.insert(path.joined(separator: "."))
      }
      for key in object.keys.sorted() {
        guard let child = object[key] else { continue }
        inspect(
          child,
          path: path + [sanitizedFieldKey(key, redacting: identifiers)],
          insideArray: insideArray,
          fieldPaths: &fieldPaths,
          metricValues: &metricValues,
          seriesByPath: &seriesByPath,
          redacting: identifiers
        )
      }
    case .array(let array):
      let arrayPath = pathWithArraySuffix(path)
      let joinedPath = arrayPath.joined(separator: ".")
      fieldPaths.insert(joinedPath)

      let values = array.compactMap(observationValue).filter { $0.isFinite }
      if values.count >= 2, isHealthMetricPath(joinedPath),
        let minimum = values.min(),
        let median = median(values),
        let maximum = values.max()
      {
        seriesByPath[joinedPath] = EightSleepSeriesSummary(
          path: joinedPath,
          sampleCount: values.count,
          minimum: minimum,
          median: median,
          maximum: maximum
        )
      }

      for child in array.prefix(3) {
        inspect(
          child,
          path: arrayPath,
          insideArray: true,
          fieldPaths: &fieldPaths,
          metricValues: &metricValues,
          seriesByPath: &seriesByPath,
          redacting: identifiers
        )
      }
    case .number(let number):
      recordScalar(
        number,
        path: path,
        insideArray: insideArray,
        fieldPaths: &fieldPaths,
        metricValues: &metricValues
      )
    case .string(let string):
      if let number = Double(string) {
        recordScalar(
          number,
          path: path,
          insideArray: insideArray,
          fieldPaths: &fieldPaths,
          metricValues: &metricValues
        )
      } else if !path.isEmpty {
        fieldPaths.insert(path.joined(separator: "."))
      }
    case .bool, .null:
      if !path.isEmpty {
        fieldPaths.insert(path.joined(separator: "."))
      }
    }
  }

  private static func recordScalar(
    _ number: Double,
    path: [String],
    insideArray: Bool,
    fieldPaths: inout Set<String>,
    metricValues: inout [String: Double]
  ) {
    guard !path.isEmpty else { return }
    let joinedPath = path.joined(separator: ".")
    fieldPaths.insert(joinedPath)
    if !insideArray,
      number.isFinite,
      isHealthMetricPath(joinedPath),
      !isIdentifierPath(joinedPath)
    {
      metricValues[joinedPath] = number
    }
  }

  private static func observationValue(_ value: JSONValue) -> Double? {
    if let number = value.numberValue {
      return number
    }
    if let array = value.arrayValue {
      if array.count > 1, let number = array[1].numberValue {
        return number
      }
      return array.first?.numberValue
    }
    if let object = value.objectValue {
      for key in ["value", "heartRate", "hr", "rr", "ibi"] {
        if let number = object[key]?.numberValue {
          return number
        }
      }
    }
    return nil
  }

  private static func pathWithArraySuffix(_ path: [String]) -> [String] {
    guard let last = path.last else { return ["[]"] }
    return Array(path.dropLast()) + [last.hasSuffix("[]") ? last : last + "[]"]
  }

  private static func isHealthMetricPath(_ path: String) -> Bool {
    let normalized = path.lowercased().filter(\.isLetter)
    return [
      "heart", "hrv", "respir", "breath", "pulse", "rhr", "resting",
      "rrinterval", "nninterval", "beatinterval", "interbeat", "ibi",
    ].contains(where: normalized.contains)
  }

  private static func isIdentifierPath(_ path: String) -> Bool {
    guard let leaf = path.split(separator: ".").last else { return false }
    let normalized = leaf.lowercased().filter(\.isLetter)
    return normalized.hasSuffix("id")
      || normalized.hasSuffix("identifier")
      || normalized.hasSuffix("uuid")
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
}
