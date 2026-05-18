#!/usr/bin/env bash
#
# Convert an MP4 screen recording into a high-quality, README-friendly GIF.
#
# Uses ffmpeg's two-pass palettegen / paletteuse pipeline. This gives ~3x
# smaller files than a naive `ffmpeg -i in.mp4 out.gif` while keeping color
# fidelity comparable to gifski.
#
# Usage:
#   scripts/mp4-to-gif.sh <input.mp4> <output.gif> [width] [fps]
#
# Defaults: 720px wide, 15 fps. The HEVC/H.264 input is downsampled with
# Lanczos and quantized into a 256-entry palette generated from the entire
# clip (palettegen=stats_mode=full).
#
# Examples:
#   scripts/mp4-to-gif.sh ~/Movies/MacZoomer*.mp4 docs/demos/zoom.gif
#   scripts/mp4-to-gif.sh demo.mp4 demo.gif 1080 30

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input.mp4> <output.gif> [width=720] [fps=15]" >&2
    exit 1
fi

INPUT="$1"
OUTPUT="$2"
WIDTH="${3:-720}"
FPS="${4:-15}"

if [[ ! -f "$INPUT" ]]; then
    echo "Input not found: $INPUT" >&2
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found. Install with: brew install ffmpeg" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

PALETTE="$(mktemp -t maczoomer-palette).png"
trap 'rm -f "$PALETTE"' EXIT

echo "→ Pass 1: generating palette from $INPUT (${WIDTH}px, ${FPS} fps)"
ffmpeg -y -hide_banner -loglevel error \
    -i "$INPUT" \
    -vf "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos,palettegen=stats_mode=full" \
    "$PALETTE"

echo "→ Pass 2: writing $OUTPUT"
ffmpeg -y -hide_banner -loglevel error \
    -i "$INPUT" \
    -i "$PALETTE" \
    -lavfi "fps=${FPS},scale=${WIDTH}:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=sierra2_4a" \
    "$OUTPUT"

SIZE=$(du -h "$OUTPUT" | awk '{print $1}')
echo "✓ Wrote $OUTPUT ($SIZE)"
