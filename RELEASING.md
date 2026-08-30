# Sleep Relay release flow

Sleep Relay uses two permanent branches and two build configurations. Beta and
release are distribution states, not additional branches.

| Stage | Source | Xcode configuration | Destination | Developer tools |
| --- | --- | --- | --- | --- |
| Feature | `elmcodex/*` | Release and Internal CI builds | None | Compile-checked |
| Nightly | `nightly` | Internal | Internal TestFlight only | Included |
| Beta candidate | `main` | Release | TestFlight | Excluded |
| App Store release | Tagged `main` commit | Existing tested build | App Store | Excluded |

## Promotion

1. Develop on a short-lived `elmcodex/*` branch.
2. Open a pull request into `nightly`; CI must pass before merging.
3. The push to `nightly` uploads a uniquely numbered, Internal-only TestFlight
   build. Test the normal app and the hidden diagnostics screen on a physical
   iPhone (tap About's Version row seven times to reveal it).
4. When the Nightly is accepted, open a pull request from `nightly` to `main`.
5. From the TestFlight workflow on `main`, manually dispatch the `release`
   channel. This archive does not contain `INTERNAL_TOOLS` and is eligible for
   external TestFlight and App Store distribution.
6. Test that exact build. Promote it in App Store Connect; do not rebuild solely
   to submit it. Tag its source commit as `v<marketing-version>` and create a
   GitHub Release.

`main` and `nightly` disallow force-pushes and deletion. Pull requests require
the `Core tests and app builds` check but no second-person approval, which keeps
the workflow practical for a solo maintainer.

## Build numbering

`MARKETING_VERSION` in `project.yml` changes only for a planned public version.
Every TestFlight upload needs a new `CURRENT_PROJECT_VERSION`. GitHub Actions
uses the shared TestFlight workflow run number plus the build-5 baseline, so
Internal and Release uploads cannot select the same number. Local uploads use
the value in `project.yml` unless `SLEEP_RELAY_BUILD_NUMBER` is supplied.

Each archive also records its channel and Git commit in the app's Info.plist.
Internal builds display these values in the hidden About diagnostics screen.

## CI workflows

- `CI` runs core Swift tests and code-signing-free Release and Internal
  simulator builds on pull requests and maintained branches.
- `TestFlight` runs automatically only on `nightly`. It can also be manually
  dispatched from `main` for a Release candidate.
- Uploads use the `testflight` GitHub environment. Forks and ordinary feature
  branches never receive signing or provider credentials.

The `testflight` environment contains these encrypted secrets:

- `EIGHT_SLEEP_CLIENT_ID`
- `EIGHT_SLEEP_CLIENT_SECRET`
- `APPLE_TEAM_ID`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_BASE64`
- `DISTRIBUTION_CERTIFICATE_P12_BASE64`
- `DISTRIBUTION_CERTIFICATE_PASSWORD`
- `PROVISIONING_PROFILE_BASE64`

Never commit or print their values. The workflow creates an ephemeral keychain,
installs the provisioning profile, uploads the archive, and removes the
temporary signing material even after failure.

## Local verification and upload

```bash
Scripts/ci.sh
Scripts/upload-testflight.sh --channel internal
```

The uploader refuses a dirty checkout. `SLEEP_RELAY_ALLOW_DIRTY=1` exists only
for deliberate local experiments and must not be used for a release candidate.
Set `SLEEP_RELAY_KEEP_ARTIFACTS=1` only when an archive must be inspected; the
default removes the temporary archive after upload.

## Rollback

Do not delete or rewrite a published Git tag. If an Internal build is bad,
disable it in App Store Connect and fix forward with a higher build number. If
a release candidate is bad, do not submit it; fix the source on a feature
branch and repeat the promotion flow.
