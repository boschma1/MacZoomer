#!/usr/bin/env bash
# scripts/publish-appcast.sh — sign a DMG with Sparkle's EdDSA key, prepend
# an <item> to appcast.xml on the gh-pages branch, and push.
#
# Required env vars:
#   SPARKLE_PRIVATE_KEY  — base64-encoded Sparkle EdDSA private key
#   VERSION              — semver string, e.g. 0.5.0
#   TAG                  — git tag, e.g. v0.5.0
#   REPO                 — github org/repo, e.g. boschma1/MacZoomer
#
# Required arg:
#   $1 — path to the signed, notarized, stapled .dmg
#
# This script is intended to run inside .github/workflows/release.yml after
# the DMG is finalized, but works locally too (set SPARKLE_PRIVATE_KEY, run
# from a fresh worktree, and the gh-pages push will fail unless you have
# write access).

set -euo pipefail

DMG="${1:?usage: $0 <dmg-path>}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY env var required}"
: "${VERSION:?VERSION env var required}"
: "${TAG:?TAG env var required}"
: "${REPO:?REPO env var required}"

# BUILD is the integer encoded from VERSION (1.2.3 -> 10203). When called
# standalone (e.g. from scripts/release-local.sh), derive it on the fly.
if [[ -z "${BUILD:-}" ]]; then
    IFS='.' read -r MAJ MIN PATCH <<<"$VERSION"
    BUILD=$(( ${MAJ:-0} * 10000 + ${MIN:-0} * 100 + ${PATCH:-0} ))
fi

if [[ ! -f "$DMG" ]]; then
    echo "✗ DMG not found: $DMG" >&2
    exit 1
fi

WORK_DIR="$(mktemp -d -t maczoomer-appcast)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "→ Fetching Sparkle tools"
curl -sSL -o "$WORK_DIR/Sparkle.tar.xz" \
    https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
tar -xf "$WORK_DIR/Sparkle.tar.xz" -C "$WORK_DIR"

KEY_FILE="$WORK_DIR/sparkle.key"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

echo "→ Signing $DMG with Sparkle EdDSA key"
SIG_LINE="$("$WORK_DIR/bin/sign_update" --ed-key-file "$KEY_FILE" "$DMG")"
rm -f "$KEY_FILE"
echo "  $SIG_LINE"

SIZE="$(stat -f%z "$DMG" 2>/dev/null || stat -c%s "$DMG")"
DMG_NAME="$(basename "$DMG")"
DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"
PUBDATE="$(LC_TIME=C date -u +'%a, %d %b %Y %H:%M:%S +0000')"
# Use the same monotonic build number that the .app's CFBundleVersion
# carries (computed from VERSION above). Sparkle compares
# CFBundleVersion against sparkle:version, so they must match for
# the upgrade detector to work correctly.

ITEM_FILE="$WORK_DIR/item.xml"
cat > "$ITEM_FILE" <<EOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUBDATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DMG_URL}"
                length="${SIZE}"
                type="application/octet-stream"
                ${SIG_LINE} />
        </item>
EOF

echo "→ Preparing gh-pages worktree"
git fetch origin gh-pages 2>/dev/null || true

WORKTREE="$WORK_DIR/gh-pages"
if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
    git worktree add "$WORKTREE" origin/gh-pages
else
    # First-ever publish: create an orphan gh-pages branch.
    git worktree add --detach "$WORKTREE"
    (
        cd "$WORKTREE"
        git checkout --orphan gh-pages
        git rm -rf . 2>/dev/null || true
    )
fi

cd "$WORKTREE"

if [[ ! -f appcast.xml ]]; then
    echo "→ Bootstrapping appcast.xml"
    cat > appcast.xml <<EOF
<?xml version="1.0" standalone="yes"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
    xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>MacZoomer</title>
        <link>https://boschma1.github.io/MacZoomer/appcast.xml</link>
        <description>Updates for MacZoomer</description>
        <language>en</language>
    </channel>
</rss>
EOF
fi

# Idempotency: strip any prior item with the same short version string so
# re-runs don't pile up duplicates.
python3 - "$VERSION" "$ITEM_FILE" <<'PY'
import re, sys, pathlib
version, item_path = sys.argv[1], sys.argv[2]
path = pathlib.Path("appcast.xml")
xml = path.read_text()
xml = re.sub(
    r"\s*<item>(?:(?!</item>).)*?<sparkle:shortVersionString>"
    + re.escape(version)
    + r"</sparkle:shortVersionString>.*?</item>",
    "",
    xml,
    flags=re.S,
)
item = pathlib.Path(item_path).read_text().rstrip() + "\n"
xml = xml.replace("    </channel>", item + "    </channel>", 1)
path.write_text(xml)
PY

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    git config user.name  "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi

git add appcast.xml
if git diff --cached --quiet; then
    echo "→ No appcast changes to commit"
else
    git commit -m "Publish MacZoomer ${VERSION} to appcast"
    git push origin HEAD:gh-pages
    echo "✓ appcast.xml published for ${VERSION}"
fi