#!/usr/bin/env bash
# scripts/release-local.sh — build, sign, notarize, and package MacZoomer
# locally using the developer's keychain. The same flow runs in CI via
# .github/workflows/release.yml; this script exists so a developer can
# repro problems without pushing a tag.
#
# Requirements:
#   • Developer ID Application cert installed in the login keychain.
#   • notarytool credentials stored under keychain profile "MacZoomerNotary"
#       (run `xcrun notarytool store-credentials MacZoomerNotary
#        --apple-id <you> --team-id 5R57LQA4MP --password <app-specific>`
#        once).
#   • XcodeGen installed (`brew install xcodegen`).
#
# Usage:
#   scripts/release-local.sh [version]
#
#   `version` defaults to the MARKETING_VERSION in project.yml. Pass an
#   explicit value (e.g. 0.5.0) to override.

set -euo pipefail

cd "$(dirname "$0")/.."

SIGN_IDENTITY="${MACZOOMER_SIGN_IDENTITY:-Developer ID Application: qualified.ink GmbH (5R57LQA4MP)}"
TEAM_ID="${MACZOOMER_TEAM_ID:-5R57LQA4MP}"
NOTARY_PROFILE="${MACZOOMER_NOTARY_PROFILE:-MacZoomerNotary}"

if [[ "${1:-}" ]]; then
    VERSION="$1"
else
    VERSION="$(grep -E '^    MARKETING_VERSION:' project.yml | head -1 | awk -F'"' '{print $2}')"
fi

if [[ -z "$VERSION" ]]; then
    echo "✗ Could not determine version. Pass it as the first argument." >&2
    exit 1
fi

echo "→ Releasing MacZoomer $VERSION as $SIGN_IDENTITY (team $TEAM_ID)"

echo "→ Generating Xcode project"
xcodegen generate

echo "→ Building Release"
xcodebuild \
    -project MacZoomer.xcodeproj \
    -scheme MacZoomer \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS=--timestamp \
    MARKETING_VERSION="$VERSION" \
    build

APP_PATH="build/Build/Products/Release/MacZoomer.app"

echo "→ Re-signing nested Sparkle helpers + main app (deep, hardened, timestamped)"
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --options runtime --timestamp \
    --entitlements Sources/MacZoomer/Resources/MacZoomer.entitlements \
    "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "→ Submitting .app for notarization"
APP_ZIP="$(mktemp -d)/MacZoomer.zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling .app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

echo "→ Building signed DMG"
mkdir -p artifacts
DMG_PATH="artifacts/MacZoomer-$VERSION.dmg"
MACZOOMER_SIGN_IDENTITY="$SIGN_IDENTITY" \
    scripts/make-dmg.sh "$APP_PATH" "$DMG_PATH" "MacZoomer $VERSION"

echo "→ Submitting DMG for notarization"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"

echo "→ Computing SHA-256"
( cd artifacts && shasum -a 256 "MacZoomer-$VERSION.dmg" | tee "SHA256SUMS-$VERSION.txt" )

echo "✓ Release complete: $DMG_PATH"