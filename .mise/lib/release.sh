#!/bin/bash

# Shared by the release file tasks. Never trace signing credentials.
set +x
set -euo pipefail
export LC_ALL=C

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${RUNNER_TEMP:-$project_root/dist}"
SIGNING_DIRECTORY="${SIGNING_DIRECTORY:-$release_root/nark-signing}"
RELEASE_DIRECTORY="${RELEASE_DIRECTORY:-$release_root/nark-release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$release_root/Nark.xcarchive}"
# Read by the tasks that source this file.
# shellcheck disable=SC2034
APP="$ARCHIVE_PATH/Products/Applications/Nark.app"
# shellcheck disable=SC2034
profiles_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

cd "$project_root"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_env() {
    local name
    for name in "$@"; do
        [[ -n "${!name:-}" ]] || fail "Set $name before running this release task."
    done
}

output() {
    printf '%s=%s\n' "$1" "$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    fi
}

decode_secret() {
    require_env "$1"
    printf '%s' "${!1}" | tr -d '[:space:]' | base64 --decode > "$2"
}

validate_version() {
    require_env VERSION
    [[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
        || fail "Version must be three numbers, for example 0.1.0, without a v prefix."
}

validate_build() {
    require_env BUILD
    [[ "$BUILD" =~ ^[1-9][0-9]{0,3}\.[1-9][0-9]?$ ]] \
        || fail "Build must be a counter (1–9999) and attempt (1–99), for example 26.1."
}

validate_uuid() {
    [[ "$1" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]] \
        || fail "Invalid provisioning profile UUID."
}

validate_entitlements() {
    local file="$1" identifier="$2"
    jq -e --arg team "$APPLE_TEAM_ID" '
        (."get-task-allow" // false | not)
        and (."com.apple.security.get-task-allow" // false | not)
        and (."com.apple.developer.team-identifier" == $team)
        and (."com.apple.developer.networking.networkextension" | index("content-filter-provider-systemextension") != null)
    ' "$file" > /dev/null || fail "Wrong team, development signing or missing content-filter capability in $identifier."
    if [[ "$identifier" == com.ollieatkinson.Nark ]]; then
        jq -e '."com.apple.developer.system-extension.install" == true' "$file" > /dev/null \
            || fail "The app needs the System Extension installation capability."
    fi
}
