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
  field names, matched scalar metrics, and numeric series statistics;
- run a versioned, research-only RHR lab over timestamped heart-rate samples and
  compare it with a value manually read from the Eight app;
- share a sanitized text report that excludes credentials, tokens, account,
  device, and session identifiers, exact timestamps, and raw payloads;
- request read-only Apple Health access for sleep analysis, heart rate,
  respiratory rate, resting heart rate, and HRV SDNN;
- group visible Apple Health samples by metric, sleep night, and source so gaps
  can be investigated without assuming that an empty result proves data is
  missing;
- review and write one Eight-reported RHR sample with stable synchronization
  metadata, skip visible Eight/Sleep Relay duplicates, warn about other visible
  sources, and delete only Sleep Relay's own sample; and
- label Eight Sleep HRV as RMSSD rather than incorrectly writing it as Apple
  Health SDNN.

It has no Eight Sleep mutation endpoints and no Sleep Relay backend. The only
HealthKit writer is the explicitly confirmed RHR import. The account password
and short-lived access token are kept in memory only and disappear when the app
disconnects or exits.

The live read-only path was validated locally on 2026-08-29: login succeeded
and the app displayed the account's three available recent nights. No real
payload was saved to the repository.

For three inspected nights, `sleepQualityScore.heartRate.current` exactly
matched the RHR shown in the Eight app (55, 51, and 51 bpm). Sleep Relay uses
that reported value and does not derive the HealthKit write from the differently
defined `heartRate.average` field or the experimental RHR Lab series. The
intervals endpoint was also validated, but it exposed aggregate HRV series, not
evidence of raw NN/RR beat intervals suitable for SDNN.

Eight Sleep does not publish a supported public API. This integration is
unofficial and may stop working when its private endpoints change.

## Build

Requirements:

- Apple silicon Mac
- Xcode 27 beta with the iOS 27 SDK
- XcodeGen 2.46 or later

Generate the project:

```bash
xcodegen generate
open -a /Applications/Xcode-beta.app SleepRelay.xcodeproj
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
user-triggered RHR write, Health app readback, and deduplication behavior still
need validation on the phone.

App Store Connect requires both HealthKit purpose strings for an entitled app.
The update-purpose text limits writes to an explicitly confirmed
Eight-reported RHR sample. The coverage audit requests an empty write set; write
permission is requested only from the separate RHR confirmation flow.

## TestFlight

The App Store Connect record and private `Sleep Relay Internal` group were
created on 2026-08-29. Version 0.1.0 build 5 passed processing and internal
distribution. It fixes Health authorization presentation and ensures the RHR
sample metadata uses the value types required by HealthKit.

On the iPhone, install Apple's TestFlight app, accept the Sleep Relay invitation
for the same Apple Account, and install the available build. The installed
build can be used away from the Mac. A push to the protected `nightly` branch
runs CI and uploads an Internal-only build from a GitHub-hosted Xcode 27 runner.
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
