#!/usr/bin/env bash
set -euo pipefail
: "${CERTIFICATE_P12_BASE64:?Add the CERTIFICATE_P12_BASE64 repository secret}"
: "${CERTIFICATE_PASSWORD?Add the CERTIFICATE_PASSWORD repository secret (may be empty)}"
: "${PROVISIONING_PROFILE_BASE64:?Add the PROVISIONING_PROFILE_BASE64 repository secret}"
SIGNING_DIR=$(mktemp -d)
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$KEYCHAIN_PASSWORD"
cleanup() {
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  if [ -n "${PROFILE_DEST:-}" ]; then rm -f "$PROFILE_DEST"; fi
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
export SIGNING_DIR
python3 - <<'PY'
import base64, os, pathlib
root = pathlib.Path(os.environ['SIGNING_DIR'])
for env, name in [('CERTIFICATE_P12_BASE64','certificate.p12'),('PROVISIONING_PROFILE_BASE64','profile.mobileprovision')]:
    (root/name).write_bytes(base64.b64decode(os.environ[env], validate=True))
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/certificate.p12" -P "$CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
security cms -D -i "$SIGNING_DIR/profile.mobileprovision" > "$SIGNING_DIR/profile.plist"
python3 - <<'PY'
import datetime, os, pathlib, plistlib
root = pathlib.Path(os.environ['SIGNING_DIR'])
p = plistlib.loads((root/'profile.plist').read_bytes())
team = p['TeamIdentifier'][0]
bundle = 'com.r347h4ck3r.nativezombies'
assert p['Entitlements']['application-identifier'].split('.',1)[1] == bundle, 'Profile must match '+bundle
assert p.get('ProvisionedDevices'), 'Use an ad hoc profile including your iPhone UDID'
assert not p['Entitlements'].get('get-task-allow',False), 'Use an ad hoc distribution profile, not development'
assert p['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Profile has expired'
(root/'team').write_text(team)
(root/'uuid').write_text(p['UUID'])
options = {'method':'release-testing','teamID':team,'signingStyle':'manual','signingCertificate':'Apple Distribution',
           'provisioningProfiles':{bundle:p['UUID']},'stripSwiftSymbols':True}
(root/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
TEAM_ID=$(cat "$SIGNING_DIR/team")
PROFILE_UUID=$(cat "$SIGNING_DIR/uuid")
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
PROFILE_DEST="$PROFILE_DIR/$PROFILE_UUID.mobileprovision"
cp "$SIGNING_DIR/profile.mobileprovision" "$PROFILE_DEST"
xcodebuild -project NativeZombies.xcodeproj -scheme NativeZombies -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/Afterlight.xcarchive \
  ARCHS=arm64 CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY='Apple Distribution' PROVISIONING_PROFILE_SPECIFIER="$PROFILE_UUID" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" archive
xcodebuild -exportArchive -archivePath build/Afterlight.xcarchive \
  -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -exportPath build/signed
