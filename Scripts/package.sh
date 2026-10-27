#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/environment.sh

mode="${1:-signed}"
if [[ "$mode" != signed && "$mode" != --unsigned ]]; then
    echo 'Usage: Scripts/package.sh [--unsigned]' >&2
    exit 1
fi
if [[ "$mode" == signed ]]; then
    : "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple team ID}"
    : "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Apple signing identity}"
    : "${APP_PROFILE:?Set APP_PROFILE to the host app provisioning profile path}"
    : "${EXTENSION_PROFILE:?Set EXTENSION_PROFILE to the filter provisioning profile path}"
else
    DEVELOPMENT_TEAM=UNSIGNED00
fi
export DEVELOPMENT_TEAM
export NARK_SIGNING_MODE="$mode"
configuration="${NARK_CONFIGURATION:-release}"
xcrun swift build --configuration "$configuration" --disable-sandbox
bin=$(xcrun swift build --configuration "$configuration" --disable-sandbox --show-bin-path)
mkdir -p dist
staging=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
app="$staging/Nark.app"
ext="$app/Contents/Library/SystemExtensions/com.ollieatkinson.Nark.Filter.systemextension"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$ext/Contents/MacOS"
cp "$bin/nark" "$app/Contents/MacOS/nark"
cp "$bin/NarkFilter" "$ext/Contents/MacOS/NarkFilter"
for bundle in "$bin/"*.bundle; do
    [[ ! -e "$bundle" ]] || cp -R "$bundle" "$app/Contents/Resources/"
done
export NARK_APP="$app" NARK_EXTENSION="$ext"
python3 - <<'PY'
import datetime, fnmatch, os, pathlib, plistlib, re, subprocess
team = os.environ['DEVELOPMENT_TEAM']
app = pathlib.Path(os.environ['NARK_APP'])
ext = pathlib.Path(os.environ['NARK_EXTENSION'])
app_id = 'com.ollieatkinson.Nark'
settings = {}
for line in pathlib.Path('Configuration/Project.xcconfig').read_text().splitlines():
    if line.strip() and not line.lstrip().startswith(('#', '//')) and '=' in line:
        key, value = line.split('=', 1)
        settings[key.strip()] = value.strip()
group = settings['NARK_APP_GROUP']
network_values = ['content-filter-provider']
if os.environ['NARK_SIGNING_MODE'] == 'signed':
    profiles = []
    for variable, identifier in [('APP_PROFILE', app_id), ('EXTENSION_PROFILE', app_id+'.Filter')]:
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', os.environ[variable]]))
        entitlement = profile['Entitlements']
        expected = f'{team}.{identifier}'
        if entitlement.get('com.apple.application-identifier') != expected:
            raise SystemExit(f'{variable} does not authorize {expected}')
        if entitlement.get('com.apple.developer.team-identifier') != team:
            raise SystemExit(f'{variable} belongs to a different team')
        if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
            raise SystemExit(f'{variable} has expired')
        if not any(fnmatch.fnmatchcase(group, allowed) for allowed in entitlement.get('com.apple.security.application-groups', [])):
            raise SystemExit(f'{variable} does not authorize {group}')
        profiles.append(entitlement)
    if not profiles[0].get('com.apple.developer.system-extension.install'):
        raise SystemExit('Host profile cannot install a system extension')
    # Development and Developer ID profiles authorize different NE values.
    candidates = ['content-filter-provider-systemextension', 'content-filter-provider']
    value = next((value for value in candidates if all(value in p.get('com.apple.developer.networking.networkextension', []) for p in profiles)), None)
    if value is None:
        raise SystemExit('Profiles do not authorize a common content-filter entitlement')
    network_values = [value]
settings.update(DEVELOPMENT_TEAM=team, NARK_FILTER_ENTITLEMENT=network_values[0])
def expand(value, variables):
    if isinstance(value, dict): return {key: expand(value, variables) for key, value in value.items()}
    if isinstance(value, list): return [expand(value, variables) for value in value]
    if not isinstance(value, str): return value
    for _ in range(10):
        if '$(' not in value: return value
        value = re.sub(r'\$\(([^)]+)\)', lambda match: variables[match[1]], value)
    raise SystemExit('Cyclic build setting in a packaging template')
for prefix, identifier, executable, bundle, entitlement_name in [
    ('Nark', app_id, 'nark', app, 'app.entitlements'),
    ('NarkFilter', app_id+'.Filter', 'NarkFilter', ext, 'extension.entitlements')
]:
    variables = dict(settings, PRODUCT_BUNDLE_IDENTIFIER=identifier, EXECUTABLE_NAME=executable)
    for source, destination in [
        (f'{prefix}-Info.plist', bundle/'Contents/Info.plist'),
        (f'{prefix}.entitlements', app.parent/entitlement_name)
    ]:
        with (pathlib.Path('Configuration')/source).open('rb') as file:
            value = expand(plistlib.load(file), variables)
        with destination.open('wb') as file: plistlib.dump(value, file)
PY
if [[ "$mode" == signed ]]; then
    cp "$APP_PROFILE" "$app/Contents/embedded.provisionprofile"
    cp "$EXTENSION_PROFILE" "$ext/Contents/embedded.provisionprofile"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" --entitlements "$staging/extension.entitlements" "$ext"
    codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" --entitlements "$staging/app.entitlements" "$app"
    codesign --verify --deep --strict "$app"
else
    # Unsigned artifacts carry no restricted entitlements and cannot activate a filter.
    codesign --force --sign - "$ext"
    codesign --force --sign - "$app"
fi
# Replace only generated output, after the complete staged bundle has verified.
rm -rf -- "$PWD/dist/Nark.app"
mv "$app" "$PWD/dist/Nark.app"
cp "$staging/app.entitlements" "$staging/extension.entitlements" "$PWD/dist/"
echo "$PWD/dist/Nark.app"
