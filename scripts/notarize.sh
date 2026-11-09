#!/bin/bash
# Notarize a Developer ID-signed artifact and staple the ticket (App Store Connect API key).
#
#   ./scripts/notarize.sh <submit-file> [staple-target]
#
# <submit-file>   .zip/.dmg/.pkg container to upload
# [staple-target] what to staple (default: the submit file); staple the .app so it passes Gatekeeper offline
#
# Env: AC_API_KEY_PATH (.p8 file), AC_API_KEY_ID, AC_API_ISSUER_ID
set -euo pipefail
cd "$(dirname "$0")/.."

SUBMIT="${1:?usage: notarize.sh <submit-file> [staple-target]}"
STAPLE="${2:-$SUBMIT}"
: "${AC_API_KEY_PATH:?set AC_API_KEY_PATH}"
: "${AC_API_KEY_ID:?set AC_API_KEY_ID}"
: "${AC_API_ISSUER_ID:?set AC_API_ISSUER_ID}"

echo "notarize: submitting $SUBMIT ..."
xcrun notarytool submit "$SUBMIT" \
    --key "$AC_API_KEY_PATH" \
    --key-id "$AC_API_KEY_ID" \
    --issuer "$AC_API_ISSUER_ID" \
    --wait

echo "notarize: stapling $STAPLE ..."
xcrun stapler staple "$STAPLE"
xcrun stapler validate "$STAPLE"
echo "notarize: done"
