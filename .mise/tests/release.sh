#!/bin/bash

# Real Bash, jq, plist, hashing and ZIP operations; Apple/GitHub services are
# replaced inside a private HOME. No signing identity or network is needed.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/project/.github" "$temporary/bin" "$temporary/home" "$temporary/runner"
cp -R "$root/.mise" "$temporary/project/.mise"
cp -R "$root/.github/package-trust" "$temporary/project/.github/package-trust"
cp "$root/Package.resolved" "$temporary/project/Package.resolved"
mkdir "$temporary/project/Configuration"
cp "$root/Configuration/Project.xcconfig" "$temporary/project/Configuration/Project.xcconfig"

export HOME="$temporary/home" RUNNER_TEMP="$temporary/runner"
export PATH="$temporary/bin:$PATH"
export VERSION=0.1.0 BUILD=26.1 APPLE_TEAM_ID=ABCDEFGHIJ
export DEVELOPER_ID_P12_BASE64=Zml4dHVyZQ== DEVELOPER_ID_P12_PASSWORD=fixture-password
export NOTARY_KEY_BASE64=Zml4dHVyZQ== NOTARY_KEY_ID=fixture NOTARY_ISSUER_ID=fixture
export GH_TOKEN=fixture GITHUB_REPOSITORY=example/Nark SOURCE_SHA=1111111111111111111111111111111111111111
export GITHUB_OUTPUT="$temporary/outputs" RELEASE_TEST_LOG="$temporary/commands"
export RELEASE_TEST_IDENTITY
RELEASE_TEST_IDENTITY=$(printf fixture | openssl dgst -sha1 | awk '{print toupper($NF)}')
unset GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT SIGNING_DIRECTORY RELEASE_DIRECTORY ARCHIVE_PATH
tasks="$temporary/project/.mise/tasks/release"

cat > "$temporary/bin/security" <<'BASH'
#!/bin/bash
set -euo pipefail
printf 'security %s\n' "$*" >> "$RELEASE_TEST_LOG"
case "$1" in
    list-keychains)
        if [[ "$*" != *' -s '* ]]; then
            printf '    "%s/Library/Keychains/login with spaces.keychain-db"\n' "$HOME"
        fi
        ;;
    create-keychain) touch "${@: -1}" ;;
    delete-keychain) rm "$2" ;;
    cms) cat "${@: -1}" ;;
    find-identity) printf '  1) %s "Developer ID Application: Fixture (ABCDEFGHIJ)"\n' "$RELEASE_TEST_IDENTITY" ;;
esac
BASH
cat > "$temporary/bin/git" <<'BASH'
#!/bin/bash
exit "${RELEASE_TEST_TAG_STATUS:-2}"
BASH
cat > "$temporary/bin/xcodebuild" <<'BASH'
#!/bin/bash
printf 'xcodebuild %s\n' "$*" >> "$RELEASE_TEST_LOG"
BASH
cat > "$temporary/bin/codesign" <<'BASH'
#!/bin/bash
set -euo pipefail
case "$*" in
    *--entitlements*)
        profile=app_profile
        [[ "${@: -1}" != *.systemextension ]] || profile=filter_profile
        plutil -extract Entitlements xml1 -o - "$RUNNER_TEMP/nark-signing/$profile.plist"
        ;;
    *--verbose=4*)
        printf '%s\n' 'Authority=Developer ID Application: Fixture' 'TeamIdentifier=ABCDEFGHIJ' 'flags=0x10000(runtime)' 'Timestamp=fixture' >&2
        ;;
esac
BASH
cat > "$temporary/bin/lipo" <<'BASH'
#!/bin/bash
printf '%s\n' 'x86_64 arm64'
BASH
cat > "$temporary/bin/xcrun" <<'BASH'
#!/bin/bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >> "$RELEASE_TEST_LOG"
case "$1 $2" in
    'notarytool submit') printf '{"id":"fixture-submission","status":"%s"}\n' "${RELEASE_TEST_NOTARY_STATUS:-Accepted}" ;;
    'notarytool log') printf '%s\n' '{"issues":["fixture rejection"]}' > "${@: -1}" ;;
esac
BASH
cat > "$temporary/bin/spctl" <<'BASH'
#!/bin/bash
exit 0
BASH
cat > "$temporary/bin/gh" <<'BASH'
#!/bin/bash
printf 'gh %s\n' "$*" >> "$RELEASE_TEST_LOG"
BASH
chmod +x "$temporary/bin/"*

profile() {
    local identifier="$1" uuid="$2" install=false
    [[ "$identifier" != com.ollieatkinson.Nark ]] || install=true
    cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>TeamIdentifier</key><array><string>ABCDEFGHIJ</string></array>
    <key>UUID</key><string>$uuid</string>
    <key>ExpirationDate</key><date>2099-01-01T00:00:00Z</date>
    <key>DeveloperCertificates</key><array><data>Zml4dHVyZQ==</data></array>
    <key>Entitlements</key><dict>
        <key>com.apple.application-identifier</key><string>ABCDEFGHIJ.$identifier</string>
        <key>com.apple.developer.team-identifier</key><string>ABCDEFGHIJ</string>
        <key>com.apple.developer.networking.networkextension</key><array><string>content-filter-provider-systemextension</string></array>
        <key>com.apple.security.application-groups</key><array><string>group.com.ollieatkinson.Nark</string></array>
        <key>com.apple.developer.system-extension.install</key><$install/>
    </dict>
</dict></plist>
XML
}
app_uuid=11111111-1111-1111-1111-111111111111
filter_uuid=22222222-2222-2222-2222-222222222222
profile com.ollieatkinson.Nark "$app_uuid" > "$temporary/app.plist"
profile com.ollieatkinson.Nark.Filter "$filter_uuid" > "$temporary/filter.plist"
export APP_PROFILE_BASE64 FILTER_PROFILE_BASE64
APP_PROFILE_BASE64=$(base64 < "$temporary/app.plist")
FILTER_PROFILE_BASE64=$(base64 < "$temporary/filter.plist")

expect_failure() {
    if "$@" > "$temporary/failure.log" 2>&1; then
        printf 'Expected failure: %s\n' "$*" >&2
        exit 1
    fi
}

"$tasks/check" > /dev/null
grep -qx 'build=26.1' "$GITHUB_OUTPUT"
GITHUB_RUN_NUMBER=2 GITHUB_RUN_ATTEMPT=3 "$tasks/check" > /dev/null
base=$(sed -nE 's/^CURRENT_PROJECT_VERSION = ([0-9]+)$/\1/p' "$root/Configuration/Project.xcconfig")
grep -qx "build=$((base + 2)).3" "$GITHUB_OUTPUT"
expect_failure env VERSION=01.2.3 "$tasks/check"
expect_failure env BUILD=10000.1 "$tasks/check"
expect_failure env APPLE_TEAM_ID=invalid "$tasks/check"
expect_failure env NOTARY_KEY_ID= "$tasks/check"
expect_failure env RELEASE_TEST_TAG_STATUS=0 "$tasks/check"
expect_failure env RELEASE_TEST_TAG_STATUS=128 "$tasks/check"

"$tasks/trust"
cmp "$temporary/project/.github/package-trust/macros.json" "$HOME/Library/org.swift.swiftpm/security/macros.json"
jq '.[0].fingerprint = "unreviewed"' "$temporary/project/.github/package-trust/macros.json" > "$temporary/unreviewed.json"
cp "$temporary/unreviewed.json" "$temporary/project/.github/package-trust/macros.json"
expect_failure "$tasks/trust"
cmp "$root/.github/package-trust/macros.json" "$HOME/Library/org.swift.swiftpm/security/macros.json"

profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
printf original > "$profiles/$app_uuid.provisionprofile"
"$tasks/sign" > /dev/null
[[ -f "$RUNNER_TEMP/nark-signing/release.keychain-db" ]]
"$tasks/archive"
grep -q 'ARCHS=arm64 x86_64 ONLY_ACTIVE_ARCH=NO archive' "$RELEASE_TEST_LOG"

app="$RUNNER_TEMP/Nark.xcarchive/Products/Applications/Nark.app"
extension="$app/Contents/Library/SystemExtensions/com.ollieatkinson.Nark.Filter.systemextension"
mkdir -p "$app/Contents/MacOS" "$extension/Contents/MacOS"
printf fixture > "$app/Contents/MacOS/nark"
printf fixture > "$extension/Contents/MacOS/NarkFilter"
for identifier in com.ollieatkinson.Nark com.ollieatkinson.Nark.Filter; do
    bundle="$app"
    [[ "$identifier" != com.ollieatkinson.Nark.Filter ]] || bundle="$extension"
    jq -n --arg id "$identifier" '{CFBundleIdentifier:$id,CFBundleShortVersionString:"0.1.0",CFBundleVersion:"26.1"}' \
        > "$bundle/Contents/Info.plist"
    if [[ "$bundle" == "$app" ]]; then
        plutil -insert NarkMachService -string group.com.ollieatkinson.Nark.filter.v26.1 "$bundle/Contents/Info.plist"
    else
        plutil -insert NetworkExtension -dictionary "$bundle/Contents/Info.plist"
        plutil -insert NetworkExtension.NEMachServiceName -string group.com.ollieatkinson.Nark.filter.v26.1 "$bundle/Contents/Info.plist"
    fi
done
"$tasks/verify"
expect_failure env BUILD=27.1 "$tasks/verify"
expect_failure env RELEASE_TEST_NOTARY_STATUS=Invalid "$tasks/notarize"
grep -q 'fixture rejection' "$temporary/failure.log"
[[ ! -f "$RUNNER_TEMP/nark-signing/notary.p8" ]]
"$tasks/notarize"
[[ ! -f "$RUNNER_TEMP/nark-signing/notary.p8" ]]
"$tasks/publish" > /dev/null
grep -q 'gh release create v0.1.0' "$RELEASE_TEST_LOG"
printf corrupt >> "$RUNNER_TEMP/nark-release/Nark-0.1.0-macOS.zip"
before=$(grep -c '^gh ' "$RELEASE_TEST_LOG")
expect_failure "$tasks/publish"
[[ "$(grep -c '^gh ' "$RELEASE_TEST_LOG")" == "$before" ]]
"$tasks/clean"
[[ ! -d "$RUNNER_TEMP/nark-signing" ]]
[[ "$(cat "$profiles/$app_uuid.provisionprofile")" == original ]]
[[ ! -e "$profiles/$filter_uuid.provisionprofile" ]]
grep -Fq "security list-keychains -d user -s $HOME/Library/Keychains/login with spaces.keychain-db" "$RELEASE_TEST_LOG"
"$tasks/clean"

# A rejected profile must clean up a partially imported identity and any earlier profile.
expect_failure env FILTER_PROFILE_BASE64=invalid "$tasks/sign"
[[ ! -d "$RUNNER_TEMP/nark-signing" ]]
[[ "$(cat "$profiles/$app_uuid.provisionprofile")" == original ]]
printf '%s\n' 'Release checks passed: inputs, trust pins, profile validation, universal archive, metadata, notarization, checksums and cleanup.'
