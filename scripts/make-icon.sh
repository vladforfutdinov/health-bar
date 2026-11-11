#!/bin/bash
# Regenerates Resources/AppIcon.icns from design/g2.svg. Needs Inkscape.
set -euo pipefail
cd "$(dirname "$0")/.."

INKSCAPE="${INKSCAPE:-/Applications/Inkscape.app/Contents/MacOS/inkscape}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Artwork fills ~80% of the canvas, per the macOS icon grid.
"$INKSCAPE" design/g2.svg --export-type=png --export-height=824 --export-filename="$TMP/art.png" >/dev/null 2>&1
sips --padToHeightWidth 1024 1024 "$TMP/art.png" --out "$TMP/1024.png" >/dev/null

SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
