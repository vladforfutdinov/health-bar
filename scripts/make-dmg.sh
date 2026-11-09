#!/bin/bash
# Package dist/HealthBar.app into dist/HealthBar.dmg (drag-to-Applications). Run build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/HealthBar.app"
DMG="dist/HealthBar.dmg"
VOLNAME="HealthBar"

[ -d "$APP" ] || { echo "error: $APP not found — run ./scripts/build.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# hdiutil intermittently fails with "Resource busy" on CI runners
for attempt in 1 2 3 4; do
    if hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"; then
        break
    fi
    if [ "$attempt" = 4 ]; then echo "error: hdiutil create failed after retries" >&2; exit 1; fi
    echo "hdiutil create failed (attempt $attempt) -- retrying in 5s"
    sleep 5
done

echo "Built $DMG"
