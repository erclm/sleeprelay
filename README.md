# Sleep Relay

An open-source iOS app for filling useful gaps between Eight Sleep and Apple
Health. Simple, private, and transparent.

## Current status

Sleep Relay is an early read-only prototype. It can:

- authenticate directly with Eight Sleep's unofficial cloud API;
- fetch the most recent seven nights from the V2 trends endpoint;
- display known sleep metrics, available response fields, and embedded
  time-series names and sample counts;
- distinguish an explicit resting-heart-rate field from average sleeping heart
  rate;
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
  missing; and
- label Eight Sleep HRV as RMSSD rather than incorrectly writing it as Apple
  Health SDNN.

It currently has no HealthKit writer, no Eight Sleep mutation endpoints, and no
Sleep Relay backend. The account password and short-lived access token are kept
in memory only and disappear when the app disconnects or exits.

The live read-only path was validated locally on 2026-08-29: login succeeded
and the app displayed the account's three available recent nights. No real
payload was saved to the repository.

The known live trends response did not contain an explicit resting-heart-rate
field for the inspected night. Average sleeping heart rate also differed from
the value shown as resting heart rate in the Eight app, so Sleep Relay does not
map one to the other. The RHR Lab remains a dry-run validation tool and cannot
write to Apple Health. The intervals response still needs live validation; no
claim is made that it contains RHR or raw NN/RR intervals.

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
the read-only build was signed, installed, trusted, and launched successfully.
The HealthKit coverage audit is implemented, simulator-tested, signed with the
HealthKit entitlement, and installed and launched on the paired iPhone. The
user-triggered authorization flow and real-source results still need validation
on the phone. The paid membership was purchased but was not yet active in Xcode
at the time of this checkpoint; the Personal Team remains sufficient for this
local device build.

App Store Connect requires both HealthKit purpose strings for an entitled app.
The update-purpose text explicitly states that this build does not write or
update Apple Health data, and the authorization request still contains an empty
write set.

## TestFlight

The App Store Connect record and private `Sleep Relay Internal` group were
created on 2026-08-29. Version 0.1.0 build 1 was uploaded, passed processing,
and was assigned to the account holder through automatic internal
distribution. Build 2 source, containing the sanitized RHR Lab, verified
read-only intervals probe, and report-sharing workflow, is prepared locally but
still needs a successful App Store Connect export and upload.

On the iPhone, install Apple's TestFlight app, accept the Sleep Relay invitation
for the same Apple Account, and install the available build. The installed
build can be used away from the Mac. New builds still have to be uploaded from
the Mac or a future CI service.

For each subsequent upload, increment `CURRENT_PROJECT_VERSION` in
`project.yml`, regenerate the project, and run:

```bash
Scripts/upload-testflight.sh
```

The script runs the core tests, creates an App Store archive, and uploads it to
App Store Connect. `ITSAppUsesNonExemptEncryption` is false because Sleep Relay
implements no encryption algorithms itself; HTTPS is supplied by Apple's
networking stack.

## Project direction

See [PLAN.md](PLAN.md) for the metric policy, privacy model, architecture,
implementation milestones, and HealthKit safety gates.

## License

MPL-2.0. Eight Sleep is a trademark of its owner. Sleep Relay is not affiliated
with or endorsed by Eight Sleep.
