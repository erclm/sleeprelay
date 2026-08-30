#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

cd "${repo_root}"

command -v xcodegen >/dev/null
xcodegen generate

swift test --package-path Packages/SleepRelayCore

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
    CODE_SIGNING_ALLOWED=NO \
    build
done
