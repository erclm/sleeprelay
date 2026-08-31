# Sleep Relay

An open-source iOS app for filling useful gaps between Eight Sleep and Apple
Health. Simple, private, and transparent.

## Current status

Sleep Relay is an early, explicitly controlled prototype. It can:

- authenticate directly with Eight Sleep's unofficial cloud API;
- fetch the most recent seven nights from the V2 trends endpoint;
- display known sleep metrics in the normal app while keeping response fields,
  endpoint probes, and time-series summaries in an Internal-only Developer tab;
- decode Eight's nightly reported resting heart rate separately from its
  differently defined heart-rate average field;
- discover heart-, HRV-, respiratory-, and RHR-related numeric field paths
  without retaining a raw Eight response;
- probe the currently documented read-only intervals endpoint and retain only
  sanitized field names, JSON kinds, container counts, broad cadence buckets,
  matched scalar metrics, and numeric series statistics;
- run an Internal-only, user-initiated 15-second probe of Eight Sleep's private
  live sensor stream; it resolves the authenticated account's current household
  `pod` identity separately from `pillow`, validates the echoed device and
  online state, makes at most one live request, and retains only fixed identity
  relationships, transport categories, event counts, sample-block sizes, and
  relative timing aggregates—not identifiers, timestamps, response text, or
  sensor values;
- run a versioned, research-only RHR lab over timestamped heart-rate samples and
  compare it with a value manually read from the Eight app;
- copy or share a structure-only diagnostic that excludes the night date,
  health values, credentials, tokens, recognized account/device/session
  identifiers, exact timestamps, raw samples, and raw payloads; the report asks
  the user to inspect private-schema field names before sharing, and the existing
  value-bearing RHR research report remains a separate action;
- request read-only Apple Health access for sleep analysis, heart rate,
  respiratory rate, resting heart rate, and HRV SDNN;
- group visible Apple Health samples by metric, sleep night, and source so gaps
  can be investigated without assuming that an empty result proves data is
  missing;
- review and write one Eight-reported RHR sample with stable synchronization
  metadata, skip visible Eight/Sleep Relay duplicates, warn about other visible
  sources, and delete only Sleep Relay's own sample;
- save the Eight login in device-only Apple Keychain, restore it at launch, and
  request a best-effort iOS background refresh after the user's typical wake
  time while retaining the foreground refresh when the app becomes active;
- audit available Eight history from 2015 onward and backfill only RHR nights
  where no existing source is visible; and
- label Eight Sleep HRV as RMSSD rather than incorrectly writing it as Apple
  Health SDNN.

It has no Eight Sleep mutation endpoints and no Sleep Relay backend. The only
HealthKit writer is the reported-RHR path. A backfill always requires explicit
confirmation; automatic checks run only after RHR write access has already been
granted and can be disabled. The account login is stored only in device-bound
Apple Keychain and is deleted when the app disconnects. Access tokens remain in
memory.

The live read-only path was validated locally on 2026-08-29: login succeeded
and the app displayed the account's three available recent nights. No real
payload was saved to the repository.

For three inspected nights, `sleepQualityScore.heartRate.current` exactly
matched the RHR shown in the Eight app (55, 51, and 51 bpm). Sleep Relay uses
that reported value and does not derive the HealthKit write from the differently
defined `heartRate.average` field or the experimental RHR Lab series. The
intervals endpoint was also validated, but it exposed aggregate HRV series, not
evidence of raw NN/RR beat intervals suitable for SDNN.

Static analysis of Eight Sleep's Android app identified a separate authenticated
live sensor endpoint whose piezo events contain timestamped arrays of floating-point
samples. The app does not disclose their sampling rate, continuity, channel, or
units, so Sleep Relay treats the endpoint only as a research lead. The Nightly
probe does not retain the waveform, calculate HRV, or write Apple Health. A real
SDNN path remains gated on recovering and independently validating genuine beat
intervals.

The first on-device probe used the completed-night session device and received
HTTP 404. That result does not prove the Pod lacks raw data: current Eight
accounts can expose separate household Pod and pillow identities, while the
official Android Test Drive passes a physical onboarding device identity. The
follow-up probe therefore resolves the unique explicit household Pod, rejects
ambiguous or conflicting identities, validates it through the device endpoint,
and reports a 2xx-without-piezo response separately from observed sample blocks.

Eight Sleep does not publish a supported public API. This integration is
unofficial and may stop working when its private endpoints change.

## Build

Requirements:

- Apple silicon Mac
- Xcode 26.6 or later (use the latest App Store-supported stable or RC build)
- XcodeGen 2.46 or later

Generate the project:

```bash
xcodegen generate
open -a /Applications/Xcode.app SleepRelay.xcodeproj
```

Run the pure Swift tests:

```bash
cd Packages/SleepRelayCore
swift test
```

Run the same core tests and Release/Internal simulator builds used by CI:

```bash
Scripts/ci.sh
```

The project builds without an Eight Sleep client configuration, but live login
is disabled in that state. For local live testing, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and provide an
authorized mobile OAuth client configuration. `Config/Local.xcconfig` is
ignored by Git. This working copy already has a local configuration for testing.

Never put an Eight Sleep email, password, bearer token, or real unredacted
payload in the repository.

## Real-device signing

Open Xcode Settings > Apple Accounts and sign in yourself. Then select the
SleepRelay app target, open Signing & Capabilities, enable automatic signing,
and select your team. A free Personal Team needs a connected, trusted physical
iPhone before Xcode can create its development certificate and provisioning
profile. Do not send Apple or Eight Sleep credentials to a contributor or paste
them into an issue.

The current prototype can retrieve Eight Sleep data in Simulator. Automatic
signing for `app.sleeprelay.ios` has also been validated with a physical iPhone:
the app was signed, installed, trusted, and launched successfully.
The HealthKit coverage audit is implemented, simulator-tested, signed with the
HealthKit entitlement, and installed and launched on the paired iPhone. The
user-triggered RHR write, history backfill, Health app readback, and
deduplication behavior still need validation on the phone.

App Store Connect requires both HealthKit purpose strings for an entitled app.
The update-purpose text limits writes to Eight-reported RHR samples approved
through an individual review or history backfill. The coverage audit requests
an empty write set; write permission is requested only after a separate RHR
confirmation.

## TestFlight

The App Store Connect record and private `Sleep Relay Internal` group were
created on 2026-08-29. Version 0.1.0 build 8 passed the automated Nightly
pipeline and entered internal testing. It uses the stable Xcode 26.6 release
toolchain and was uploaded from the protected `nightly` branch.

On the iPhone, install Apple's TestFlight app, accept the Sleep Relay invitation
for the same Apple Account, and install the available build. The installed
build can be used away from the Mac. A push to the protected `nightly` branch
runs CI and uploads an Internal-only build from a GitHub-hosted Xcode 26.6 runner.
Release-candidate uploads are manually dispatched from `main`.

For a local Internal-only upload, increment `CURRENT_PROJECT_VERSION` in
`project.yml`, regenerate the project, and run:

```bash
Scripts/upload-testflight.sh --channel internal
```

Use `--channel release` only from a tested `main` checkout. The script refuses
dirty working trees by default, runs the core tests, creates an App Store
archive, and uploads it to App Store Connect. `ITSAppUsesNonExemptEncryption`
is false because Sleep Relay
implements no encryption algorithms itself; HTTPS is supplied by Apple's
networking stack.

For non-interactive App Store Connect authentication, create the ignored local
file `Config/AppStoreConnect.local.env` with these three variables:

```bash
ASC_KEY_ID=YOUR_KEY_ID
ASC_ISSUER_ID=YOUR_ISSUER_ID
ASC_KEY_PATH=/absolute/path/to/AuthKey_YOUR_KEY_ID.p8
```

Keep the `.p8` outside the repository with file mode `600`. The API key handles
App Store Connect authentication, but a TestFlight export still requires an
Apple Distribution signing certificate. Xcode can cloud-sign when its Apple
Account has access, while CI needs a distribution certificate and provisioning
profile supplied through protected secrets.

When the API key cannot use Apple's cloud-managed distribution certificate,
add the local certificate and App Store provisioning profile to the keychain
and set these values in the same ignored file:

```bash
ASC_TEAM_ID=YOUR_TEAM_ID
ASC_SIGNING_CERTIFICATE=YOUR_DISTRIBUTION_CERTIFICATE_SHA1
ASC_PROVISIONING_PROFILE="YOUR_APP_STORE_PROFILE_NAME"
ASC_BUNDLE_ID=app.sleeprelay.ios
```

The script then generates temporary manual-signing export options without
putting account-specific signing identifiers or credentials in the repository.

See [RELEASING.md](RELEASING.md) for branch promotion, CI credentials,
TestFlight channels, and release tagging.

## Project direction

See [PLAN.md](PLAN.md) for the metric policy, privacy model, architecture,
implementation milestones, and HealthKit safety gates.

## License

MPL-2.0. Eight Sleep is a trademark of its owner. Sleep Relay is not affiliated
with or endorsed by Eight Sleep.
