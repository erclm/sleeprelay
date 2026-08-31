#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

cd "${repo_root}"

command -v xcodegen >/dev/null
xcodegen generate

swift test --package-path Packages/SleepRelayCore

ci_derived_data="$(mktemp -d "${TMPDIR:-/tmp}/sleeprelay-ci.XXXXXX")"
trap 'rm -rf -- "${ci_derived_data}"' EXIT

for configuration in Release Internal; do
  scheme="SleepRelay"
  if [[ "${configuration}" == "Internal" ]]; then
    scheme="SleepRelay-Internal"
  fi

  xcodebuild \
    -quiet \
    -project SleepRelay.xcodeproj \
    -scheme "${scheme}" \
    -configuration "${configuration}" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "${ci_derived_data}" \
    CODE_SIGNING_ALLOWED=NO \
    build
done

release_binary="${ci_derived_data}/Build/Products/Release-iphonesimulator/Sleep Relay.app/Sleep Relay"
if [[ ! -f "${release_binary}" ]]; then
  print -u2 "Expected Release binary was not produced."
  exit 1
fi
if strings "${release_binary}" \
  | rg 'live-piezo-probe-v[0-9]+|developer\.livePiezo|SLEEP_RELAY_LIVE_PIEZO_VALID|saved-sdnn-hypothesis-v[0-9]+|saved-respiratory-sinusoid-v[0-9]+|SavedEightSDNN|developer\.savedSDNN|Saved-data SDNN estimation lab|SLEEP_RELAY_SAVED_SDNN_VALID' \
    >/dev/null; then
  print -u2 "Internal Developer diagnostics leaked into the Release binary."
  exit 1
fi
