import Foundation
import Testing

@testable import SleepRelayCore

struct RestingHeartRateSyncTests {
  @Test
  func createsCandidateOnlyFromValidatedReportedRHRAndPresenceInterval() throws {
    let night = makeNight(reportedRHR: 55)
    let candidate = try #require(night.restingHeartRateSyncCandidate)

    #expect(candidate.valueBPM == 55)
    #expect(candidate.syncIdentifier == "app.sleeprelay.rhr.2026-08-29")
    #expect(candidate.startDate == start)
    #expect(candidate.endDate == end)
    #expect(candidate.isValidForHealthKitWrite)
    #expect(RestingHeartRateSyncCandidate.healthKitAlgorithmVersion == 1)

    #expect(makeNight(reportedRHR: .infinity).restingHeartRateSyncCandidate == nil)
    #expect(makeNight(reportedRHR: 10).restingHeartRateSyncCandidate == nil)
    #expect(makeNight(reportedRHR: nil).restingHeartRateSyncCandidate == nil)
    #expect(makeNight(reportedRHR: 55, processing: true).restingHeartRateSyncCandidate == nil)
  }

  @Test
  func rejectsInvalidDirectCandidatesBeforeHealthKitConstruction() {
    let invalidCandidate = RestingHeartRateSyncCandidate(
      id: "invalid",
      day: "2026-08-29",
      valueBPM: .infinity,
      startDate: end,
      endDate: end
    )

    #expect(!invalidCandidate.isValidForHealthKitWrite)
  }

  @Test
  func prioritizesSleepRelayAndEightSamplesBeforeOtherSources() throws {
    let candidate = try #require(makeNight(reportedRHR: 55).restingHeartRateSyncCandidate)
    let google = sample(name: "Google Health", bundle: "com.fitbit.FitbitMobile")
    let eight = sample(name: "Eight Sleep", bundle: "com.eightsleep.Eight")
    let relay = sample(
      name: "Sleep Relay",
      bundle: "app.sleeprelay.ios",
      syncIdentifier: candidate.syncIdentifier
    )

    #expect(
      RestingHeartRateSyncPolicy.decision(
        for: candidate,
        existingSamples: [],
        sleepRelayBundleIdentifier: "app.sleeprelay.ios"
      ) == .ready
    )
    #expect(
      RestingHeartRateSyncPolicy.decision(
        for: candidate,
        existingSamples: [google],
        sleepRelayBundleIdentifier: "app.sleeprelay.ios"
      ) == .otherSourcesPresent(["Google Health"])
    )
    #expect(
      RestingHeartRateSyncPolicy.decision(
        for: candidate,
        existingSamples: [google, eight],
        sleepRelayBundleIdentifier: "app.sleeprelay.ios"
      ) == .eightAlreadyPresent
    )
    #expect(
      RestingHeartRateSyncPolicy.decision(
        for: candidate,
        existingSamples: [google, eight, relay],
        sleepRelayBundleIdentifier: "app.sleeprelay.ios"
      ) == .alreadyWritten
    )
  }

  @Test
  func ignoresSamplesOutsideTheSleepInterval() throws {
    let candidate = try #require(makeNight(reportedRHR: 55).restingHeartRateSyncCandidate)
    let oldSample = RestingHeartRateHealthSample(
      source: HealthDataSource(
        name: "Google Health",
        bundleIdentifier: "com.fitbit.FitbitMobile",
        version: nil
      ),
      valueBPM: 54,
      startDate: start.addingTimeInterval(-48 * 3_600),
      endDate: start.addingTimeInterval(-24 * 3_600),
      syncIdentifier: nil
    )

    #expect(
      RestingHeartRateSyncPolicy.decision(
        for: candidate,
        existingSamples: [oldSample],
        sleepRelayBundleIdentifier: "app.sleeprelay.ios"
      ) == .ready
    )
  }

  private var start: Date { Date(timeIntervalSince1970: 1_788_038_400) }
  private var end: Date { Date(timeIntervalSince1970: 1_788_067_200) }

  private func makeNight(
    reportedRHR: Double?,
    processing: Bool = false
  ) -> EightSleepNight {
    EightSleepNight(
      id: "night-1",
      day: "2026-08-29",
      presenceStart: start,
      presenceEnd: end,
      isProcessing: processing,
      score: nil,
      sleepDurationSeconds: nil,
      averageHeartRateBPM: nil,
      explicitRestingHeartRateBPM: reportedRHR,
      reportedHRVMilliseconds: nil,
      averageRespiratoryRate: nil,
      tossAndTurns: nil,
      lightSleepSeconds: nil,
      deepSleepSeconds: nil,
      remSleepSeconds: nil,
      availableFields: [],
      metricFields: [],
      timeSeries: [],
      latestSessionID: nil,
      intervalProbe: nil
    )
  }

  private func sample(
    name: String,
    bundle: String,
    syncIdentifier: String? = nil
  ) -> RestingHeartRateHealthSample {
    RestingHeartRateHealthSample(
      source: HealthDataSource(name: name, bundleIdentifier: bundle, version: nil),
      valueBPM: 54,
      startDate: start.addingTimeInterval(60),
      endDate: end.addingTimeInterval(-60),
      syncIdentifier: syncIdentifier
    )
  }
}
