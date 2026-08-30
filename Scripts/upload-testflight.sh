#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
work_directory="$(mktemp -d /tmp/sleeprelay-testflight.XXXXXX)"
archive_path="${work_directory}/SleepRelay.xcarchive"
upload_path="${work_directory}/upload"
local_auth_file="${repo_root}/Config/AppStoreConnect.local.env"

if [[ -f "${local_auth_file}" ]]; then
  source "${local_auth_file}"
fi

authentication_args=()
if [[ -n "${ASC_KEY_PATH:-}" || -n "${ASC_KEY_ID:-}" || -n "${ASC_ISSUER_ID:-}" ]]; then
  : "${ASC_KEY_PATH:?ASC_KEY_PATH is required when App Store Connect API authentication is configured}"
  : "${ASC_KEY_ID:?ASC_KEY_ID is required when App Store Connect API authentication is configured}"
  : "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required when App Store Connect API authentication is configured}"

  if [[ ! -f "${ASC_KEY_PATH}" ]]; then
    printf 'App Store Connect private key not found: %s\n' "${ASC_KEY_PATH}" >&2
    exit 1
  fi

  authentication_args=(
    -authenticationKeyPath "${ASC_KEY_PATH}"
    -authenticationKeyID "${ASC_KEY_ID}"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID}"
  )
fi

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
  "${authentication_args[@]}" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${upload_path}" \
  -exportOptionsPlist Config/TestFlightExportOptions.plist \
  -allowProvisioningUpdates \
  "${authentication_args[@]}"

printf 'TestFlight upload submitted. Temporary archive: %s\n' "${archive_path}"
