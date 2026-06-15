#!/usr/bin/env bash
# scripts/make-dmg.sh — packages /Applications-style DMG from a built .app.
#
# Usage:
#   scripts/make-dmg.sh <path-to-MacZoomer.app> <output-dmg> [volume-name]
#
# Examples:
#   scripts/make-dmg.sh build/Build/Products/Release/MacZoomer.app artifacts/MacZoomer-0.1.0.dmg
#
# If $MACZOOMER_SIGN_IDENTITY is set, the resulting DMG is codesigned with
# that identity (e.g. "Developer ID Application: qualified.ink GmbH
# (5R57LQA4MP)") using a secure timestamp. Notarization + stapling are run
# separately by the caller (see scripts/release-local.sh and
# .github/workflows/release.yml).
#
# If $MACZOOMER_SIGN_IDENTITY is empty, the DMG is left ad-hoc and
# Gatekeeper will warn on first launch.

set -euo pipefail

APP_PATH="${1:?Usage: $0 <app-path> <output-dmg> [volume-name]}"
OUTPUT_DMG="${2:?Usage: $0 <app-path> <output-dmg> [volume-name]}"
VOLUME_NAME="${3:-MacZoomer}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ App not found: $APP_PATH" >&2
    exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_DMG")"
mkdir -p "$OUTPUT_DIR"

STAGING_DIR="$(mktemp -d -t maczoomer-dmg-staging)"
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "→ Staging at $STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_DMG"

echo "→ Building DMG → $OUTPUT_DMG"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    -imagekey zlib-level=9 \
    "$OUTPUT_DMG"

if [[ -n "${MACZOOMER_SIGN_IDENTITY:-}" ]]; then
    echo "→ Codesigning DMG with: $MACZOOMER_SIGN_IDENTITY"
    codesign --force --sign "$MACZOOMER_SIGN_IDENTITY" --timestamp "$OUTPUT_DMG"
    codesign --verify --verbose=2 "$OUTPUT_DMG"
fi

echo "✓ DMG ready: $OUTPUT_DMG"
echo "  $(du -h "$OUTPUT_DMG" | cut -f1)"
