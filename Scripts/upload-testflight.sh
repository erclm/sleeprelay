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

export_options_plist="${repo_root}/Config/TestFlightExportOptions.plist"
if [[ -n "${ASC_TEAM_ID:-}" || -n "${ASC_SIGNING_CERTIFICATE:-}" || -n "${ASC_PROVISIONING_PROFILE:-}" ]]; then
  : "${ASC_TEAM_ID:?ASC_TEAM_ID is required when manual distribution signing is configured}"
  : "${ASC_SIGNING_CERTIFICATE:?ASC_SIGNING_CERTIFICATE is required when manual distribution signing is configured}"
  : "${ASC_PROVISIONING_PROFILE:?ASC_PROVISIONING_PROFILE is required when manual distribution signing is configured}"

  bundle_id="${ASC_BUNDLE_ID:-app.sleeprelay.ios}"
  export_options_plist="${work_directory}/TestFlightExportOptions.plist"
  cp "${repo_root}/Config/TestFlightExportOptions.plist" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c 'Set :signingStyle manual' "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :signingCertificate string ${ASC_SIGNING_CERTIFICATE}" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :teamID string ${ASC_TEAM_ID}" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${bundle_id} string ${ASC_PROVISIONING_PROFILE}" "${export_options_plist}"
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
  -exportOptionsPlist "${export_options_plist}" \
  -allowProvisioningUpdates \
  "${authentication_args[@]}"

printf 'TestFlight upload submitted. Temporary archive: %s\n' "${archive_path}"
