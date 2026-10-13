#!/usr/bin/env bash
# Signs, notarizes and staples the macOS release build, then packages it as
# a signed, notarized, stapled DMG (plus a zip of the stapled app). Run by
# CI's build-macos job after `flutter build macos --release`:
#
#   scripts/ci/macos_sign_notarize.sh <output dir> <artifact base name>
#
# Writes <output dir>/<base>.dmg and <output dir>/<base>.zip.
#
# Expects these environment variables (repo secrets; see ROADMAP.md M35):
#   MACOS_CERT_P12_BASE64, MACOS_CERT_PASSWORD  Developer ID Application cert
#   MACOS_KEYCHAIN_PASSWORD                     any value; temp keychain only
#   ASC_KEY_P8_BASE64, ASC_KEY_ID, ASC_ISSUER_ID App Store Connect API key
#
# The app is notarized and stapled first, then the DMG built from it is
# notarized and stapled too. Homebrew copies the app out of the DMG, so the
# app needs its own stapled ticket to pass Gatekeeper offline; the DMG needs
# one so the download itself opens without a warning.
set -euo pipefail

OUT_DIR="$1"
BASE_NAME="$2"
APP="build/macos/Build/Products/Release/NATS Client.app"
ENTITLEMENTS="macos/Runner/Release.entitlements"
WORK="${RUNNER_TEMP:?}/macos-signing"

mkdir -p "$OUT_DIR" "$WORK"

KEYCHAIN="$WORK/signing.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN" 2> /dev/null || true
  rm -f "$WORK/cert.p12" "$WORK/AuthKey.p8"
}
trap cleanup EXIT

echo "::group::Import signing certificate"
security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
printf '%s' "$MACOS_CERT_P12_BASE64" | base64 --decode > "$WORK/cert.p12"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
rm -f "$WORK/cert.p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
# Put the temp keychain on the search list, ahead of the runner's own.
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
# Sign by certificate hash rather than name, so nothing depends on how the
# certificate's common name is spelled.
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" \
  | awk '/Developer ID Application/ { print $2; exit }')
if [ -z "$IDENTITY" ]; then
  echo "No 'Developer ID Application' identity found in the imported certificate" >&2
  security find-identity -v -p codesigning "$KEYCHAIN" >&2
  exit 1
fi
echo "Signing identity: $IDENTITY"
echo "::endgroup::"

printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode > "$WORK/AuthKey.p8"
NOTARY_AUTH=(--key "$WORK/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

# Submits a file for notarization and waits. On anything but "Accepted",
# prints Apple's log (which names the offending file and reason) and fails.
notarize() {
  local file="$1" result id status
  result=$(xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" \
    --wait --timeout 30m --output-format json)
  echo "$result"
  id=$(jq -r '.id' <<< "$result")
  status=$(jq -r '.status' <<< "$result")
  if [ "$status" != "Accepted" ]; then
    echo "Notarization of $(basename "$file") ended with status: $status" >&2
    xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" >&2 || true
    exit 1
  fi
}

echo "::group::Sign app (inside-out, hardened runtime)"
# Nested code first, deepest first, then the app itself with its
# entitlements. --force replaces the ad-hoc signature `flutter build` left.
find "$APP/Contents/Frameworks" -depth \
  \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) -print0 \
  | while IFS= read -r -d '' item; do
      codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
    done
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "::endgroup::"

echo "::group::Notarize and staple app"
ditto -c -k --keepParent "$APP" "$WORK/app-for-notarization.zip"
notarize "$WORK/app-for-notarization.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"
echo "::endgroup::"

echo "::group::Build, sign, notarize and staple DMG"
STAGE="$WORK/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/NATS Client.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT_DIR/$BASE_NAME.dmg"
# hdiutil occasionally fails on CI runners with "Resource busy"; retry.
for attempt in 1 2 3; do
  if hdiutil create -volname "NATS Client" -srcfolder "$STAGE" -ov -format UDZO "$DMG"; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    exit 1
  fi
  echo "hdiutil failed (attempt $attempt), retrying..."
  sleep 5
done
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "::endgroup::"

# A zip of the stapled app too, for anyone who used the old zip download.
ditto -c -k --keepParent "$APP" "$OUT_DIR/$BASE_NAME.zip"
