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
- label Eight Sleep HRV as RMSSD rather than incorrectly writing it as Apple
  Health SDNN.

It currently has no HealthKit writer, no Eight Sleep mutation endpoints, and no
Sleep Relay backend. The account password and short-lived access token are kept
in memory only and disappear when the app disconnects or exits.

The live read-only path was validated locally on 2026-08-29: login succeeded
and the app displayed the account's three available recent nights. No real
payload was saved to the repository.

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
Real-device HealthKit behavior is still unimplemented and untested.

## Project direction

See [PLAN.md](PLAN.md) for the metric policy, privacy model, architecture,
implementation milestones, and HealthKit safety gates.

## License

MPL-2.0. Eight Sleep is a trademark of its owner. Sleep Relay is not affiliated
with or endorsed by Eight Sleep.
