#!/bin/bash
# One-time (idempotent) GitHub setup for HealthBar releases:
#   - creates the Homebrew tap repo if missing;
#   - sets the repository variables;
#   - Sparkle EdDSA key pair (login keychain, account "healthbar") -> SPARKLE_ED_PRIVATE_KEY + HEALTHBAR_SU_PUBLIC_KEY;
#   - tap deploy key (write) -> TAP_DEPLOY_KEY;
#   - copies the Developer ID / notarization secrets from the reLayout repo via a throwaway
#     workflow there (GitHub never returns secret values to the API, only a workflow can read them).
# Needs: gh logged in with repo + workflow scopes; the health-bar repo already on GitHub.
# FORCE=1 re-creates secrets that already exist.
set -euo pipefail
cd "$(dirname "$0")/.."

OWNER="${OWNER:-vladforfutdinov}"
REPO="${REPO:-$OWNER/health-bar}"
TAP="${TAP:-$OWNER/homebrew-healthbar}"
SOURCE="${SOURCE:-$OWNER/reLayout}"
FEED_URL="${FEED_URL:-https://healthbar.forfutdinov.com/appcast.xml}"
COPIED=(DEVELOPER_ID_CERT_P12_BASE64 DEVELOPER_ID_CERT_PASSWORD AC_API_KEY_ID AC_API_ISSUER_ID AC_API_KEY_P8_BASE64)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

has_secret() { [ "${FORCE:-0}" != 1 ] && gh secret list -R "$REPO" --json name -q '.[].name' | grep -qx "$1"; }

gh repo view "$REPO" >/dev/null

echo "== tap repo"
if ! gh repo view "$TAP" >/dev/null 2>&1; then
    gh repo create "$TAP" --public --add-readme --description "Homebrew tap for HealthBar"
fi

echo "== variables"
gh variable set HEALTHBAR_BUNDLE_ID    -R "$REPO" --body "com.vladforfutdinov.healthbar"
gh variable set HEALTHBAR_DISPLAY_NAME -R "$REPO" --body "HealthBar"
gh variable set HEALTHBAR_REPO_SLUG    -R "$REPO" --body "$REPO"
gh variable set HEALTHBAR_FEED_URL     -R "$REPO" --body "$FEED_URL"
gh variable set HEALTHBAR_TAP_REPO     -R "$REPO" --body "$TAP"

echo "== Sparkle keys"
. scripts/sparkle.env
GEN_KEYS=".sparkle/$SPARKLE_VERSION/bin/generate_keys"
if [ ! -x "$GEN_KEYS" ]; then
    echo "fetching Sparkle tools via build.sh..."
    WITH_SPARKLE=1 scripts/build.sh >/dev/null
fi
# generate_keys keeps the private key in the login keychain and reuses it on later runs.
"$GEN_KEYS" --account healthbar >/dev/null
PUB="$("$GEN_KEYS" --account healthbar -p)"
gh variable set HEALTHBAR_SU_PUBLIC_KEY -R "$REPO" --body "$PUB"
if ! has_secret SPARKLE_ED_PRIVATE_KEY; then
    "$GEN_KEYS" --account healthbar -x "$TMP/ed_priv"
    gh secret set SPARKLE_ED_PRIVATE_KEY -R "$REPO" < "$TMP/ed_priv"
fi

echo "== tap deploy key"
if ! has_secret TAP_DEPLOY_KEY; then
    ssh-keygen -q -t ed25519 -N "" -C "healthbar-ci" -f "$TMP/tap_key"
    gh repo deploy-key add "$TMP/tap_key.pub" -R "$TAP" --allow-write --title "healthbar-ci $(date +%F)"
    gh secret set TAP_DEPLOY_KEY -R "$REPO" < "$TMP/tap_key"
fi

echo "== signing + notarization secrets from $SOURCE"
missing=()
for s in "${COPIED[@]}"; do has_secret "$s" || missing+=("$s"); done
if [ ${#missing[@]} -eq 0 ]; then
    echo "already set"
else
    BRANCH="hb-copy-secrets-$(date +%s)"
    WF=".github/workflows/hb-copy-secrets.yml"
    cleanup_source() {
        git -C "$TMP/src" push -q origin --delete "$BRANCH" 2>/dev/null || true
        gh secret delete HB_COPY_TOKEN -R "$SOURCE" 2>/dev/null || true
    }
    trap 'cleanup_source; rm -rf "$TMP"' EXIT

    gh secret set HB_COPY_TOKEN -R "$SOURCE" --body "$(gh auth token)"
    git clone -q --depth 1 "https://github.com/$SOURCE.git" "$TMP/src"
    git -C "$TMP/src" checkout -q -b "$BRANCH"
    mkdir -p "$(dirname "$TMP/src/$WF")"
    {
        echo "name: hb-copy-secrets"
        echo "on: { push: { branches: ['hb-copy-secrets-*'] } }"
        echo "permissions: {}"
        echo "jobs:"
        echo "  copy:"
        echo "    runs-on: ubuntu-latest"
        echo "    steps:"
        echo "      - env:"
        echo "          GH_TOKEN: \${{ secrets.HB_COPY_TOKEN }}"
        for s in "${missing[@]}"; do echo "          $s: \${{ secrets.$s }}"; done
        echo "        run: |"
        echo "          set -euo pipefail"
        for s in "${missing[@]}"; do
            echo "          [ -n \"\$$s\" ] || { echo \"::error::$s is empty in $SOURCE\"; exit 1; }"
            echo "          printf '%s' \"\$$s\" | gh secret set $s -R $REPO"
        done
    } > "$TMP/src/$WF"
    git -C "$TMP/src" add "$WF"
    git -C "$TMP/src" -c user.name="$OWNER" -c user.email="$OWNER@users.noreply.github.com" \
        commit -q -m "tmp: copy secrets to $REPO"
    git -C "$TMP/src" push -q origin "$BRANCH"

    RUN=""
    for _ in $(seq 1 30); do
        RUN="$(gh run list -R "$SOURCE" --branch "$BRANCH" --json databaseId -q '.[0].databaseId')"
        [ -n "$RUN" ] && break
        sleep 2
    done
    [ -n "$RUN" ] || { echo "workflow run did not start" >&2; exit 1; }
    gh run watch "$RUN" -R "$SOURCE" --exit-status >/dev/null
    gh run delete "$RUN" -R "$SOURCE" >/dev/null 2>&1 || true
fi

echo "== result"
gh secret list -R "$REPO"
gh variable list -R "$REPO"
