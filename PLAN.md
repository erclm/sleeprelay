# Sleep Relay implementation plan

Status: implementation — guarded RHR writer; HRV remains RMSSD-only and local
Last verified: 2026-08-29
Repository license: MPL-2.0

## 1. Product definition

Sleep Relay is a privacy-focused, open-source iOS app that fills useful gaps in
Eight Sleep's Apple Health integration. It is not intended to replace Eight
Sleep's native integration or create a second copy of every sleep sample.

The product promise is:

> Sleep Relay writes only metrics that Eight Sleep leaves out, and only when
> the Eight data genuinely matches the corresponding Apple Health definition.

The app should:

- inspect which sleep-related HealthKit types are already visible from Eight
  Sleep and other sources;
- obtain completed-night data from the user's own Eight Sleep account;
- explain every proposed transformation before enabling it;
- write only explicitly enabled, semantically compatible metrics;
- make repeat synchronization idempotent;
- keep unsupported or differently defined metrics inside Sleep Relay;
- store credentials and health information locally, without an app-operated
  cloud service;
- provide a readable sync log explaining what was written, skipped, blocked,
  or could not be verified.

## 2. Non-goals

The first release will not:

- replace Eight Sleep's existing sleep-stage, heart-rate, or respiratory-rate
  integration;
- relabel Eight Sleep RMSSD as Apple Health SDNN;
- write sleep scores, readiness scores, bed temperature, movement, or other
  values into unrelated HealthKit types;
- modify Pod temperature, alarms, schedules, or device settings;
- upload HealthKit data, Eight credentials, or raw sleep payloads to a Sleep
  Relay server;
- provide medical advice, diagnosis, or clinical interpretation;
- automatically repair partial biometric streams;
- promise uninterrupted operation against an undocumented third-party API.

## 3. Metric compatibility and policy

| Eight Sleep metric | HealthKit destination | Initial policy | Reason |
| --- | --- | --- | --- |
| Eight-reported nightly resting heart rate | `restingHeartRate` | Guarded MVP writer | `sleepQualityScore.heartRate.current` matched Eight's displayed RHR on all three inspected nights. |
| Heart-rate interval series | `restingHeartRate` | Derivation experiment only | A derived estimate needs a documented algorithm and validation before HealthKit writes are enabled. |
| HRV reported as RMSSD | None | Display/export locally | HealthKit's HRV quantity is specifically SDNN; RMSSD must not be placed in that field. |
| Raw normal-to-normal beat intervals | `heartRateVariabilitySDNN` | Conditional future support | Genuine SDNN may be calculated only if sufficiently detailed, valid beat intervals are available. |
| Sleep stages | `sleepAnalysis` | Audit, never duplicate by default | Eight Sleep may already write these, and Apple Health can derive other sleep summaries from them. |
| Sleeping heart rate | `heartRate` | Audit, never duplicate by default | Avoid a second copy of an existing native stream. |
| Respiratory rate | `respiratoryRate` | Audit, never duplicate by default | Avoid a second copy of an existing native stream. |
| Total sleep, time in bed, sleep latency, WASO, sleep efficiency | No new standalone write | Calculate/display locally | These are summaries derived from sleep intervals and do not justify inventing a HealthKit type. |
| Sleep, quality, routine, or readiness scores | None | Display/export locally | HealthKit has no compatible custom score type. |
| Bed or room temperature | None | Display/export locally | Environmental bed temperature is not body or sleeping wrist temperature. |
| Tosses, turns, snoring, disturbances | None | Display/export locally | There is no compatible HealthKit type. |
| Oxygen saturation | Undetermined | Do not implement without source evidence | The app must not infer a metric that is absent from the verified Eight payload. |

### 3.1 Resting heart rate rules

Apple describes resting heart rate as an estimate of a person's lowest heart
rate during periods of rest and distinguishes it from an ordinary sedentary
heart-rate sample. Therefore, a generic nightly average must not automatically
be called resting heart rate.

Use this priority order:

1. Prefer an explicit Eight API field that Eight itself defines as nightly
   resting heart rate.
2. Verify that field against the value shown in the Eight Sleep app for several
   nights.
3. If the API exposes only an interval series, calculate a candidate in dry-run
   mode first.
4. Compare candidates over at least 7 to 14 representative nights, including a
   night with gaps or unusual readings.
5. Enable HealthKit writes only after the algorithm and its limitations are
   documented in the app and repository.

Live validation on 2026-08-29 found a direct nightly value at
`sleepQualityScore.heartRate.current`; it matched the Eight app's displayed RHR
for three nights (55, 51, and 51 bpm). The writer uses this reported value. It
does not use `heartRate.average` or the experimental low-median derivation.

The provisional derived candidate is the lowest duration-based rolling median
during confirmed asleep intervals. If the source cadence is five minutes, the
first experiment may use a 15-minute window. This is a proposed product
algorithm, not an assertion that it reproduces Apple's private algorithm.

The derivation module must:

- use only finite, positive source readings;
- exclude values outside confirmed sleep intervals;
- use duration and timestamps instead of assuming perfect sample cadence;
- reject windows with insufficient coverage;
- report why no candidate could be calculated;
- return the source window and supporting samples for transparent inspection;
- carry an explicit algorithm version;
- remain disabled for HealthKit writes until validation is complete.

For the validated direct field, write one discrete `restingHeartRate` sample at
the end of the source sleep interval. The user-facing description should say:

> Sleep Relay writes Eight Sleep's reported nightly resting heart rate. Apple
> Health records Sleep Relay as the source, and other apps' samples are not
> changed.

### 3.2 HRV rules

Eight Sleep reports HRV as RMSSD. HealthKit's writable HRV type is
`heartRateVariabilitySDNN`, which is the standard deviation of normal-to-normal
RR intervals. These values are related but are not interchangeable.

Required behavior:

- never write a nightly RMSSD value as `heartRateVariabilitySDNN`;
- never estimate SDNN from average heart rate or aggregated RMSSD values;
- retain RMSSD as a clearly labeled Sleep Relay metric;
- optionally export RMSSD as JSON or CSV without importing it into HealthKit;
- only unlock an SDNN writer if the live Eight payload contains raw, usable
  normal-to-normal beat intervals;
- validate any future SDNN implementation against a trusted reference and
  include minimum-duration, data-quality, and artifact-handling requirements;
- attach an algorithm version to any derived SDNN sample.

The capability should be represented explicitly rather than inferred in UI:

```swift
enum HRVImportCapability: Equatable, Sendable {
    case rawBeatIntervalsAvailable
    case rmssdOnly
    case unavailable(reason: String)
}
```

## 4. Gap-aware HealthKit behavior

### 4.1 Coverage audit

For a user-selected date range, query these HealthKit types:

- sleep analysis;
- heart rate;
- respiratory rate;
- resting heart rate;
- HRV SDNN.

Group visible samples by:

- HealthKit type;
- sleep night rather than simple calendar day;
- `sample.sourceRevision.source.bundleIdentifier`;
- source name and source version for display;
- sample start and end times.

Do not hard-code an assumed Eight Sleep bundle identifier. Initially show the
observed sources and let the user identify the Eight Sleep source if it cannot
be recognized reliably. Persist only the selected bundle identifier locally.

Suggested audit states:

```swift
enum CoverageState: Equatable, Sendable {
    case visibleFromEight(sampleCount: Int)
    case visibleFromOtherSources(sampleCount: Int)
    case noVisibleSamples
    case unavailableOnDevice
}
```

HealthKit intentionally does not tell an app whether read permission was
denied. A query with no visible samples therefore cannot prove that data is
missing. The UI must use language such as "No visible samples" rather than
"Definitely missing," and automatic gap filling must remain conservative.

### 4.2 Write decision

For each completed Eight session and candidate metric:

1. Confirm that HealthKit is available.
2. Confirm that write authorization for the exact target type is granted.
3. Confirm that the user explicitly enabled the metric.
4. Confirm that the source session is complete rather than in progress.
5. Confirm that the transformation is on the safe-write allowlist.
6. Check for a prior Sleep Relay sync identifier.
7. Check visible Eight coverage for the same type and night.
8. If Eight already wrote it, skip it.
9. If read visibility is ambiguous, show the condition and require an explicit
   user decision instead of silently assuming the metric is absent.
10. Save the sample, then read it back and record a minimal local sync result.

Other apps, including Apple Watch, may legitimately have an RHR sample for the
same day. Sleep Relay may add its independently sourced overnight estimate if
the user chooses, but the UI must explain that multiple sources will coexist.

### 4.3 Idempotency and metadata

Every HealthKit object written by Sleep Relay must include
`HKMetadataKeySyncIdentifier` and `HKMetadataKeySyncVersion`.

Example metadata shape:

```swift
[
    HKMetadataKeySyncIdentifier:
        "com.sleeprelay.rhr.\(stableAccountHash).\(sessionID)",
    HKMetadataKeySyncVersion: algorithmSyncVersion,
    "com.sleeprelay.metric": "overnightRHR",
    "com.sleeprelay.algorithmVersion": algorithmVersion,
    "com.sleeprelay.source": "eight-sleep"
]
```

Do not put an email address, access token, unredacted account identifier, or raw
payload into HealthKit metadata. A changed algorithm should increment the sync
version for the stable logical sample instead of creating an unrelated copy.

The app should eventually offer a screen listing samples it wrote and a
user-initiated way to delete Sleep Relay's samples.

## 5. Eight Sleep integration strategy

Eight Sleep does not currently publish a supported public API. Community tools
use private cloud endpoints, which can change or disappear without notice.
This is the largest product and maintenance risk.

### 5.1 Integration phases

Phase A — fixtures only:

- define provider-neutral domain models;
- create a sanitized, synthetic completed-night fixture;
- implement decoding behind an `EightSleepProviding` protocol;
- build the HealthKit pipeline without live credentials.

Phase B — inspect the user's own payload:

- use an established open-source community client or documented request shape
  to fetch one completed session;
- inspect the V2 trends response first and request any additional endpoint only
  after its current path is verified from maintained source or live app traffic;
- redact account IDs, names, emails, device IDs, and tokens;
- record only the smallest representative fixture needed for tests;
- determine whether RHR is explicit or must be derived;
- determine whether HRV data is RMSSD aggregates or true beat intervals.

Current endpoint research (2026-08-29): maintained community clients pyEight
and eightctl retrieve nightly heart rate, HRV, respiratory rate, and embedded
heart-rate samples from `GET /v1/users/{id}/trends`. eightctl also implements
the read-only `GET /v1/users/{id}/intervals/{sessionID}` path. No separate RHR
endpoint or evidence that the intervals response contains raw NN/RR intervals
was found. Sleep Relay now probes both verified GET paths, retains only
sanitized field names, value kinds, container counts, broad cadence buckets,
and existing metric/series summaries, and does not guess additional paths. The
Internal-only structure report omits the night date, all health values, exact
timestamps/cadence, recognized identifiers, credentials, and response text.

Phase C — on-device client:

- use `URLSession` with a narrow endpoint adapter;
- isolate transport DTOs from domain models;
- centralize endpoint paths, headers, and decoder quirks;
- handle expiry and rate limiting without repeated logins;
- implement bounded retries with backoff;
- expose provider breakage as an actionable app state;
- never include credentials or real payloads in diagnostics.

### 5.2 Authentication and secret storage

Design constraints:

- authentication happens directly between the app and Eight Sleep;
- Sleep Relay has no account server;
- never commit mobile client credentials or user credentials to Git;
- do not persist the user's password if token refresh can work without it;
- persist access and refresh material only in Keychain;
- use a device-only Keychain accessibility class appropriate for foreground or
  later background operation;
- wipe tokens and local account identifiers on sign out;
- use an ephemeral or explicitly cache-controlled URL session;
- redact authorization headers and identifiers from logs.

Before App Store release, review Eight Sleep's current terms and the technical
feasibility of distributing an open-source client for its private API. If safe
credential handling cannot be achieved without embedding inappropriate secrets
or retaining a password, stop and reconsider the distribution model.

## 6. Proposed architecture

Minimum platform proposal: iOS 17 or later. This permits SwiftUI,
`NavigationStack`, Swift concurrency, Observation, and SwiftData without legacy
fallbacks. Revisit the target before release based on intended users.

Use a small dependency graph with protocols around every external system:

```text
SwiftUI features
    |
    +-- AppModel / sync coordinator
            |
            +-- EightSleepProviding
            |       +-- FixtureEightSleepClient
            |       +-- LiveEightSleepClient
            |
            +-- HealthStoreProviding
            |       +-- HealthKitStore
            |       +-- FakeHealthStore
            |
            +-- RestingHeartRateDeriving
            |
            +-- SyncLedgerProviding
```

Recommended repository shape:

```text
SleepRelay/
├── PLAN.md
├── README.md
├── LICENSE
├── project.yml                    # Reproducible XcodeGen project definition
├── Package.swift                  # Pure Swift core library and unit tests
├── Sources/
│   └── SleepRelayCore/
│       ├── Domain/
│       ├── Derivation/
│       ├── SyncPolicy/
│       └── EightSleepModels/
├── Tests/
│   └── SleepRelayCoreTests/
│       └── Fixtures/
└── App/
    ├── SleepRelayApp.swift
    ├── AppModel.swift
    ├── Features/
    │   ├── Onboarding/
    │   ├── Coverage/
    │   ├── Sync/
    │   └── Settings/
    ├── HealthKit/
    ├── EightSleep/
    ├── Persistence/
    └── Resources/
```

The pure Swift core must not import HealthKit or SwiftUI. This lets derivation,
mapping, decoding, and sync-policy tests run quickly and deterministically.

### 6.1 Initial UI

Keep the first UI small:

1. **Overview** — connection state, Health access, last completed session, and
   last sync result.
2. **Coverage** — visible data types grouped by source and night.
3. **Candidate RHR** — source value or derivation inputs, result, algorithm
   version, and dry-run/write state.
4. **Unsupported metrics** — RMSSD, scores, temperatures, and summaries that
   remain local, with plain-language reasons.
5. **Settings** — account, Health permissions link, metric toggles, diagnostics,
   privacy policy, and deletion controls.

Use explicit states for loading, empty, error, authorization-required, provider
unavailable, dry-run, skipped, and written. Previews and tests must use fixtures,
not live network calls or HealthKit.

## 7. Local storage and privacy

Persist only what is necessary:

- Keychain: Eight access/refresh material and the minimum account binding;
- local app database: hashed session identifier, metric, algorithm version,
  sync result, and timestamp;
- optional local export: user-initiated JSON or CSV;
- no raw HealthKit history cache unless a later feature strictly requires it;
- no iCloud or CloudKit synchronization of health information;
- no advertising SDKs or health-based analytics;
- no secrets, personal payloads, or health samples in crash logs.

If SwiftData is used for the ledger, configure a local-only store and keep
health values out of the model where possible. The HealthKit store remains the
source of truth for objects written to Apple Health.

Before distribution, provide a plain-language privacy policy covering:

- exactly which Eight and HealthKit data is accessed;
- exactly which data is written;
- local storage and deletion behavior;
- lack of advertising/data sales;
- the unofficial nature of the Eight integration;
- how users revoke permissions and remove written samples.

## 8. Development environment and setup

### 8.1 Current machine state

Observed on 2026-08-29:

- Apple silicon Mac;
- macOS 27.0 beta 7, build 26A5421a;
- Xcode 27 beta 6, build 27A5252f, installed at
  `/Applications/Xcode-beta.app`;
- the active developer directory is
  `/Applications/Xcode-beta.app/Contents/Developer`;
- the Xcode license and first-launch setup are complete;
- iOS 26.5 and iOS 27.0 Simulator runtimes are installed;
- XcodeGen 2.46.0 is installed;
- an Apple Account and Personal Team are available in Xcode;
- the Personal Team is selected through the ignored local xcconfig;
- live Eight authentication and recent-trend retrieval were validated in the
  Simulator on 2026-08-29, returning three available nights without saving a
  payload;
- a physical iPhone is paired with Developer Mode enabled;
- Xcode created a valid Apple Development signing identity and automatic device
  provisioning profile for `app.sleeprelay.ios`;
- the signed read-only prototype was installed and launched successfully on the
  physical iPhone on 2026-08-29;
- the HealthKit coverage build was signed with the HealthKit entitlement, then
  installed and launched on the paired iPhone on 2026-08-29; and
- the paid Apple Developer Program membership is active in App Store Connect;
- an App Store Connect app record and automatic internal TestFlight group were
  created; and
- version 0.1.0 build 1 was uploaded, processed, and assigned to the account
  holder for internal testing on 2026-08-29; and
- version 0.1.0 build 2 passes core tests and archives successfully, but its
  App Store Connect export is pending because Xcode requires the saved Apple
  Account credential to be refreshed.

### 8.2 One-time local setup

Run these manually in Terminal because they require the Mac administrator
password and acceptance of Apple's license:

```bash
sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
sudo xcodebuild -license
sudo xcodebuild -runFirstLaunch
```

Then verify:

```bash
xcodebuild -version
xcrun simctl list runtimes
swift --version
```

For a reproducible generated project, install XcodeGen if it is not already
available:

```bash
brew install xcodegen
xcodegen version
```

The repository commits both `project.yml` and the generated `.xcodeproj` so a
contributor can either open the project directly or regenerate it.

### 8.3 Apple signing and device setup

1. Add an Apple ID in Xcode Settings > Accounts.
2. Choose a unique reverse-domain bundle identifier.
3. Select the appropriate development team with automatic signing.
4. Add the HealthKit capability to the app target.
5. Do not enable Clinical Health Records; Sleep Relay does not need them.
6. Defer HealthKit Background Delivery until foreground/manual sync works.
7. Connect an iPhone, trust the Mac, and enable Developer Mode if requested.
8. A paid Apple Developer Program membership is required for TestFlight and App
   Store distribution; local capability availability depends on the selected
   signing team.

App Store Connect validation requires both HealthKit purpose strings whenever
the HealthKit entitlement is present. The coverage audit requests an empty
write set; the RHR review flow separately requests RHR write authorization:

```text
NSHealthShareUsageDescription
Sleep Relay reads selected sleep and heart metrics to identify gaps and avoid
duplicate resting-heart-rate imports.
```

```text
NSHealthUpdateUsageDescription
Sleep Relay writes only Eight Sleep reported resting-heart-rate samples after
you approve an individual import or history backfill. It never writes Eight HRV
as Apple Health SDNN or changes another app's samples.
```

HealthKit checks and real-source behavior must ultimately be tested on an
iPhone. Simulator tests remain useful for UI and pure logic but are not the
release proof for authorization, existing source coverage, or Health app
display.

## 9. Implementation milestones

### Milestone 0 — plan and toolchain

- [x] Record product boundary and metric safety rules.
- [x] Record the current local Xcode state.
- [x] Accept the Xcode license and finish first-launch components.
- [x] Install XcodeGen and generate a reproducible project.
- [x] Sign in to Xcode and identify the Personal Team.
- [x] Select the Personal Team in ignored local build configuration.
- [x] Connect and register a physical iPhone.
- [x] Confirm the bundle identifier and let automatic signing create the Apple
  Development identity and device provisioning profile.

Exit criterion: `xcodebuild -version` and simulator runtime discovery work from
the normal shell without a `DEVELOPER_DIR` override.

### Milestone 1 — reproducible scaffold

- [x] Create the iOS app and pure Swift core targets.
- [x] Add an app target and pure Swift unit-test target.
- [ ] Add an app UI-test target.
- [x] Add HealthKit entitlement and metric-specific read/update purpose strings.
- [x] Wire app dependencies with protocols and fixture implementations.
- [x] Add Connect, Eight Data, and About screens with deterministic previews.
- [ ] Add CI that builds the core and runs unit tests without secrets.

Exit criterion: clean checkout, generate/open project, build, and run a fixture
UI without Eight credentials.

### Milestone 2 — core domain and policy

- [ ] Define sessions, sleep intervals, heart readings, source coverage, metric
  candidates, and sync decisions.
- [x] Limit HealthKit writes to the dedicated RHR provider method; no generic
  quantity writer is exposed.
- [x] Implement stable RHR sync identifiers and version rules.
- [x] Encode the invariant that RMSSD cannot map to HealthKit SDNN.
- [ ] Add timezone and cross-midnight night grouping.
- [x] Add sanitized synthetic fixtures.

Exit criterion: all policy and derivation behavior is covered by unit tests and
does not import HealthKit.

### Milestone 3 — HealthKit coverage audit

- [x] Check `HKHealthStore.isHealthDataAvailable()`.
- [x] Request only the five read types needed by the coverage audit, with an
  empty write-authorization set.
- [x] Query recent samples and group them by night, type, and source.
- [x] Display observed source names and bundle identifiers.
- [x] Represent no-visible-data honestly despite permission ambiguity.
- [x] Implement a fake Health store for previews and tests.

Implementation, Simulator UI verification, and signed-device installation and
launch are complete. User-triggered on-device authorization and validation
against real source coverage remain pending.

Exit criterion: on an iPhone, the app shows visible source coverage without
writing any HealthKit data.

### Milestone 4 — RHR dry run

- [x] Decode known explicit RHR paths and adaptively discover a nested RHR-like
  numeric path in synthetic decoder tests. Live schema evidence is still
  required before treating any discovered value as authoritative.
- [x] Implement a timestamp-aware 15-minute low-median experiment as the
  separate `presence-low-median-v0` strategy.
- [x] Display input statistics, result, limitations, and rejection reasons, and
  generate a sanitized share report. Selected-window inspection and
  confirmed-asleep filtering remain pending.
- [x] Compare the direct `heartRate.current` field with Eight's displayed value
  over the three available nights; all three matched exactly.
- [x] Document the chosen direct-field mapping. The derived lab value remains
  research-only.

Exit criterion: the user can inspect a trustworthy direct candidate; the
derived RHR Lab remains disabled for HealthKit writes.

### Milestone 5 — live Eight data

- [ ] Capture and sanitize one real completed-session response.
- [x] Validate read-only live login and recent-trend retrieval; the account
  returned three available nights on 2026-08-29. No real payload was saved.
- [x] Add complete in-memory payload-shape discovery and a structure-only report
  that excludes health values, credentials, tokens, recognized identifiers,
  dates, exact timestamps, raw samples, and raw payload data, with an explicit
  warning to inspect unknown private-schema field names before sharing.
- [x] Document and implement the current password-grant and V2 trends request
  shape behind a provider protocol.
- [x] Store the login in a device-only Keychain item after live read validation;
  keep the short-lived access token in memory and delete the login on disconnect.
- [x] Implement recent completed-night trend retrieval.
- [x] Implement best-effort, read-only interval retrieval for session IDs from
  the trends response; sanitize the response into field names, JSON kinds,
  counts, broad cadence buckets, matched scalar metrics, and numeric series
  statistics rather than retaining raw JSON.
- [x] Handle token expiry, rate-limit errors, schema failures, and disconnect.
- [x] Confirm that the current trends and intervals responses contain processed
  HRV/RMSSD series rather than raw beat intervals.
- [x] Add an Internal-only, foreground, aggregate-only probe for the private
  authenticated live piezo stream found in Eight Sleep's Android app. It does
  not retain response text, sensor values, identifiers, or absolute timestamps.
- [ ] Determine on the user's Pod whether live piezo sample blocks are available,
  continuous, timed precisely enough for beat recovery, and present outside the
  onboarding test-drive flow.

Exit criterion: the app retrieves the user's completed night without exposing
credentials in code/logs; saved login material remains in device-only Keychain.

### Milestone 6 — guarded RHR write

- [x] Present a metric-specific opt-in and disclosure.
- [x] Require source and duplicate checks before writing.
- [x] Save one RHR sample with stable sync and algorithm metadata.
- [x] Query it back and display the resulting sync state.
- [ ] Sync the same session twice and prove only one logical sample remains.
- [x] Add a user-initiated deletion path limited to app-written records.
- [x] Add a full-history audit/backfill that writes only `.ready` reported-RHR
  candidates and skips visible Eight, Sleep Relay, and other-source nights.
- [x] Add foreground auto-sync after permission is already granted, with a
  once-per-sleep-day lifecycle refresh policy.
- [x] Register a best-effort iOS background app-refresh task for saved logins;
  reschedule it after each run based on recent wake times and use it for
  already-authorized RHR auto-sync.

Core policy tests, the app build, and fixture UI import/remove flows pass. The
remaining proof is an on-iPhone write, Health app readback, and repeat sync.

Exit criterion: one test night appears correctly under Resting Heart Rate in the
Health app with Sleep Relay as its source, and rerunning sync does not duplicate
it.

### Milestone 7 — HRV research gate

- [x] With aggregate RMSSD-only evidence, keep the HealthKit HRV writer unsupported
  and provide local display/export.
- [x] Keep the live piezo experiment separate from HealthKit and expose only a
  sanitized Nightly diagnostic until waveform semantics and timing are known.
- [ ] If raw NN intervals exist, specify filtering, duration, minimum sample
  count, SDNN formula, validation data, and error handling.
- [ ] Add reference-vector tests before exposing any SDNN write toggle.
- [ ] Attach `HKMetadataKeyAlgorithmVersion` to derived HRV samples.

Exit criterion: either a validated genuine-SDNN implementation exists or the UI
clearly explains why HRV remains local. There is no RMSSD-to-SDNN relabeling.

### Milestone 8 — release preparation

- [ ] Accessibility and VoiceOver review.
- [ ] Privacy policy and App Store privacy disclosures.
- [ ] Threat review for tokens, logs, fixtures, exports, and local database.
- [ ] Review Eight Sleep's current terms and API stability risk.
- [ ] Device matrix and limited-access HealthKit testing.
- [ ] TestFlight build, feedback, and migration plan for API breakage.
- [ ] Contributor documentation and issue templates.

## 10. Test plan

### Pure unit tests

- explicit RHR decoding and unit conversion;
- rolling-window behavior with regular and irregular cadence;
- insufficient coverage and missing intervals;
- cross-midnight sessions and daylight-saving transitions;
- non-finite or non-positive input rejection;
- stable logical identifiers across repeat runs;
- sync-version replacement behavior;
- visible Eight source causes a skip;
- other-source-only coverage produces the intended user choice;
- no-visible-samples remains ambiguous;
- RMSSD is never accepted by the SDNN writer;
- redaction removes tokens and personal identifiers;
- decoder failure is explicit when provider schemas drift.

### Adapter tests

- HealthKit types and units map correctly;
- metadata contains sync keys and no personal information;
- the HealthKit adapter can be replaced with a fake;
- the Eight client handles success, unauthorized, rate-limited, malformed, and
  temporarily unavailable responses;
- credential material is read from Keychain rather than source configuration.

### UI tests

- onboarding requests Health access in context;
- loading, empty, limited visibility, provider error, and successful states;
- an unsupported HRV explanation is visible;
- no write can occur without a metric-specific opt-in;
- the sync log explains skip and write decisions;
- signing out clears Eight credentials without pretending HealthKit samples
  were deleted.

### On-device acceptance test

1. Use a test account or the user's account with one known completed session.
2. Record what Eight already exposes in Apple Health for that night.
3. Run Coverage with no write enabled.
4. Inspect the RHR candidate and supporting data.
5. Enable one RHR write.
6. Verify it in Health > Browse > Heart > Resting Heart Rate > Show All Data.
7. Verify Sleep Relay is the source and metadata dates/units are sensible.
8. Run sync again and verify no duplicate appears.
9. Revoke read permission and confirm the app does not claim certainty about
   missing data.
10. Delete the test sample using Sleep Relay's deletion flow.

Never commit an unredacted real payload or test credentials.

## 11. Release acceptance criteria

The first public build is ready only when:

- a user can understand exactly what the app reads and writes;
- existing Eight-native HealthKit data is not duplicated by default;
- RHR mapping has documented source semantics and validation evidence;
- RMSSD can never enter the SDNN HealthKit path;
- repeated syncs are idempotent;
- permission ambiguity is represented honestly;
- credentials remain in device-only Keychain only while saved login is enabled;
- there is no Sleep Relay backend receiving health data;
- all committed fixtures are synthetic or irreversibly sanitized;
- core tests, app build, UI smoke test, and real-device HealthKit test pass;
- the privacy policy and current App Store HealthKit requirements are satisfied.

## 12. Open questions and decision log

Resolve these with evidence rather than assumptions:

1. What exact fields and cadence are returned for one current Eight session?
2. Does the API provide an explicit resting-heart-rate value, and how is it
   defined?
3. Are interval HR values already five-minute medians or another aggregation?
4. Does any endpoint expose raw NN/RR intervals, or only aggregate RMSSD?
5. What source name and bundle identifier does Eight currently use in HealthKit?
6. Which types does Eight currently write for this user's account and hardware?
7. Can authentication avoid persistent password storage in a distributed
   open-source app?
8. Is `app.sleeprelay.ios` available for the user's development team, or should
   the bundle identifier change?
9. Is iOS 17 an acceptable minimum deployment target for release?

Initial decisions:

- **Accepted:** Sleep Relay is a gap filler, not a full mirror.
- **Accepted:** RHR is the first candidate metric.
- **Accepted:** RHR writes start behind a dry-run and validation gate.
- **Accepted:** Eight RMSSD is not written to HealthKit SDNN.
- **Accepted:** unsupported metrics remain visible/exportable locally.
- **Accepted:** first sync is manual/foreground; background delivery comes later.
- **Accepted:** no app-operated backend for credentials or health data.
- **Accepted:** XcodeGen generates the project, and the generated project is
  also committed for convenience.
- **Accepted after live validation:** direct Eight credentials are stored only
  in device-bound Apple Keychain for automatic login; access tokens remain
  memory-only, and disconnect deletes the Keychain item.
- **Validated for prototype:** live read-only authentication and recent V2
  trend retrieval work in Simulator; three available nights were displayed.
- **Validated for three nights:** `sleepQualityScore.heartRate.current` matched
  the Eight app RHR exactly; `heartRate.average` did not represent that value.
- **Observed in Apple Health:** Google Health exported RHR but no visible HRV
  SDNN samples. Fitbit/Google's documented HRV metric is RMSSD, not SDNN.
- **Validated by app reverse engineering:** Eight Sleep's Android Health Connect
  writer exports `timeseries.rmssd` as RMSSD and contains no SDNN mapping. Its
  private `/v1/devices/{device}/live` route exposes timestamped piezo sample
  blocks, but not a declared sampling rate, per-sample timestamps, beat markers,
  or RR/NN intervals.
- **Accepted for research:** Nightly may make one explicit, bounded foreground
  request to the private live stream and retain only value-free aggregate
  diagnostics. It does not save a waveform or enable an HRV writer.
- **Accepted for MVP:** write the direct Eight-reported RHR after individual or
  backfill review; future foreground auto-sync may add only source-empty nights,
  while other visible sources are skipped and never modified.
- **Accepted for validation:** the app shares only a sanitized trends summary;
  user credentials and raw responses are never requested in chat.
- **Accepted for prototype:** iOS 17 minimum deployment target.
- **Pending evidence:** live Eight payload shape and RHR semantics.
- **Pending decision:** final bundle identifier and signing team.

## 13. How to build this with Codex

Work one milestone at a time:

1. The user handles administrator-password commands, Apple license acceptance,
   signing-account selection, iPhone trust prompts, and Health permission
   prompts.
2. Codex creates or edits source, tests, configuration, and documentation; runs
   all available automated verification; and reports exact file changes.
3. The user never sends Eight credentials in chat or commits them to the repo.
4. For live schema work, the user runs the app or a local capture and shares a
   redacted payload; Codex helps verify that redaction before it becomes a test
   fixture.
5. Every HealthKit write feature is reviewed first as a dry-run diff showing the
   proposed type, unit, value, date, source session, and reason.
6. At the end of each milestone, update this file's checkboxes and decision log
   before starting the next milestone.

The next implementation instruction, after completing the one-time Xcode setup,
can simply be:

> Continue Sleep Relay milestone 1 from `PLAN.md`.

## 14. References

Apple:

- [HealthKit overview](https://developer.apple.com/documentation/healthkit)
- [Configuring HealthKit access](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Protecting user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
- [Resting heart rate](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate)
- [Heart rate variability SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
- [HealthKit sync identifier](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier)
- [HealthKit source queries](https://developer.apple.com/documentation/healthkit/hksourcequery)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Eight Sleep and community API evidence:

- [Eight Sleep HR and HRV methodology](https://www.eightsleep.com/blog/hrv-accuracy/)
- [eightctl project](https://github.com/steipete/eightctl)
- [eightctl current command and endpoint notes](https://github.com/steipete/eightctl/blob/main/docs/spec.md)

Community clients are implementation references, not authoritative or stable API
contracts. Re-verify all provider behavior before a release.
