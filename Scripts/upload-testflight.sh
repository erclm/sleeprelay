#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
work_directory="$(mktemp -d /tmp/sleeprelay-testflight.XXXXXX)"
archive_path="${work_directory}/SleepRelay.xcarchive"
upload_path="${work_directory}/upload"
local_auth_file="${repo_root}/Config/AppStoreConnect.local.env"

channel="internal"
if [[ "${1:-}" == "--channel" ]]; then
  channel="${2:-}"
  shift 2
fi
if (( $# != 0 )) || [[ "${channel}" != "internal" && "${channel}" != "release" ]]; then
  printf 'Usage: %s [--channel internal|release]\n' "$0" >&2
  exit 64
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

cleanup() {
  if [[ "${SLEEP_RELAY_KEEP_ARTIFACTS:-0}" == "1" ]]; then
    printf 'Kept archive artifacts at %s\n' "${work_directory}"
  else
    rm -rf -- "${work_directory}"
  fi
}
trap cleanup EXIT

if [[ -f "${local_auth_file}" ]]; then
  source "${local_auth_file}"
fi

cd "${repo_root}"

if [[ "${SLEEP_RELAY_ALLOW_DIRTY:-0}" != "1" ]] && [[ -n "$(git status --porcelain)" ]]; then
  printf 'Refusing to upload from a dirty working tree. Commit or stash changes first.\n' >&2
  printf 'For an intentional local experiment only, set SLEEP_RELAY_ALLOW_DIRTY=1.\n' >&2
  exit 1
fi

build_number="${SLEEP_RELAY_BUILD_NUMBER:-}"
if [[ -z "${build_number}" ]]; then
  build_number="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/p' project.yml | head -1)"
fi
if [[ ! "${build_number}" =~ ^[0-9]+$ ]]; then
  printf 'SLEEP_RELAY_BUILD_NUMBER must be a positive integer.\n' >&2
  exit 1
fi

git_sha="${SLEEP_RELAY_GIT_SHA:-$(git rev-parse --short=12 HEAD)}"

case "${channel}" in
  internal)
    scheme="SleepRelay-Internal"
    configuration="Internal"
    export_options_source="${repo_root}/Config/InternalTestFlightExportOptions.plist"
    build_channel="Nightly"
    ;;
  release)
    scheme="SleepRelay"
    configuration="Release"
    export_options_source="${repo_root}/Config/TestFlightExportOptions.plist"
    build_channel="Release Candidate"
    ;;
esac

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

export_options_plist="${export_options_source}"
archive_signing_args=()
if [[ -n "${ASC_TEAM_ID:-}" || -n "${ASC_SIGNING_CERTIFICATE:-}" || -n "${ASC_PROVISIONING_PROFILE:-}" ]]; then
  : "${ASC_TEAM_ID:?ASC_TEAM_ID is required when manual distribution signing is configured}"
  : "${ASC_SIGNING_CERTIFICATE:?ASC_SIGNING_CERTIFICATE is required when manual distribution signing is configured}"
  : "${ASC_PROVISIONING_PROFILE:?ASC_PROVISIONING_PROFILE is required when manual distribution signing is configured}"

  bundle_id="${ASC_BUNDLE_ID:-app.sleeprelay.ios}"
  export_options_plist="${work_directory}/TestFlightExportOptions.plist"
  cp "${export_options_source}" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c 'Set :signingStyle manual' "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :signingCertificate string ${ASC_SIGNING_CERTIFICATE}" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :teamID string ${ASC_TEAM_ID}" "${export_options_plist}"
  /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "${export_options_plist}"
  /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${bundle_id} string ${ASC_PROVISIONING_PROFILE}" "${export_options_plist}"

  archive_signing_args=(
    CODE_SIGN_STYLE=Manual
    "DEVELOPMENT_TEAM=${ASC_TEAM_ID}"
    "CODE_SIGN_IDENTITY=${ASC_SIGNING_CERTIFICATE}"
    "PROVISIONING_PROFILE_SPECIFIER=${ASC_PROVISIONING_PROFILE}"
  )
fi

command -v xcodegen >/dev/null
xcodegen generate

swift test --package-path Packages/SleepRelayCore

xcodebuild \
  -project SleepRelay.xcodeproj \
  -scheme "${scheme}" \
  -configuration "${configuration}" \
  -destination generic/platform=iOS \
  -archivePath "${archive_path}" \
  -allowProvisioningUpdates \
  "${authentication_args[@]}" \
  "${archive_signing_args[@]}" \
  "CURRENT_PROJECT_VERSION=${build_number}" \
  "SLEEP_RELAY_BUILD_CHANNEL=${build_channel}" \
  "SLEEP_RELAY_GIT_SHA=${git_sha}" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${upload_path}" \
  -exportOptionsPlist "${export_options_plist}" \
  -allowProvisioningUpdates \
  "${authentication_args[@]}"

printf 'Submitted %s build %s (%s) to TestFlight.\n' \
  "${build_channel}" "${build_number}" "${git_sha}"
