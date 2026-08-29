#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
work_directory="$(mktemp -d /tmp/sleeprelay-testflight.XXXXXX)"
archive_path="${work_directory}/SleepRelay.xcarchive"
upload_path="${work_directory}/upload"

cd "${repo_root}"

command -v xcodegen >/dev/null
xcodegen generate

swift test --package-path Packages/SleepRelayCore

xcodebuild \
  -project SleepRelay.xcodeproj \
  -scheme SleepRelay \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${upload_path}" \
  -exportOptionsPlist Config/TestFlightExportOptions.plist \
  -allowProvisioningUpdates

printf 'TestFlight upload submitted. Temporary archive: %s\n' "${archive_path}"
