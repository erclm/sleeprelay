import Foundation
import Testing

@testable import SleepRelayCore

struct EightSleepIntervalProbeDecoderTests {
  @Test
  func retainsPathsScalarCandidatesAndSeriesStatisticsButNotRawSamples() throws {
    let data = Data(
      #"{"resting":{"heartRate":55},"rrIntervals":[800,810,790],"heartRate":[["private-time-1",58],["private-time-2",56]],"heartRateUserId":123456,"accountId":"private-id","2f1c17e3-97c7-40a9-a86e-d44ec0c1cc24":{"heartRate":54}}"#.utf8
    )

    let probe = try EightSleepIntervalProbeDecoder.decode(data)

    #expect(probe.status == .available)
    #expect(
      probe.metricFields == [
        EightSleepMetricField(path: "resting.heartRate", value: 55),
        EightSleepMetricField(path: "{identifier}.heartRate", value: 54),
      ]
    )
    #expect(probe.series.first(where: { $0.path == "heartRate[]" })?.median == 57)
    #expect(probe.series.first(where: { $0.path == "rrIntervals[]" })?.sampleCount == 3)
    #expect(probe.fieldPaths.contains("accountId"))
    #expect(probe.fieldPaths.contains("heartRateUserId"))
    #expect(!probe.metricFields.contains(where: { $0.path == "heartRateUserId" }))
    #expect(!probe.fieldPaths.contains("private-id"))
    #expect(!probe.fieldPaths.contains("private-time-1"))
    #expect(!probe.fieldPaths.contains(where: { $0.contains("2f1c17e3") }))
    #expect(probe.fieldPaths.contains("{identifier}.heartRate"))
  }
}
