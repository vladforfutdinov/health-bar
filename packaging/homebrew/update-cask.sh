#!/bin/bash
# Render Casks/healthbar.rb from the template (version + dmg sha256) and push it to the
# Homebrew tap over SSH with a deploy key. Run by CI on release; no-ops if TAP_DEPLOY_KEY is unset.
#
#   ./packaging/homebrew/update-cask.sh <version> <dmg-path>
#
# Env (required once TAP_DEPLOY_KEY is set):
#   TAP_DEPLOY_KEY        private SSH deploy key (write) for the tap repo
#   HEALTHBAR_TAP_REPO    owner/name of the tap
#   HEALTHBAR_REPO_SLUG   owner/repo the cask's url/homepage point at
#   HEALTHBAR_BUNDLE_ID   bundle id for the zap preferences path
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION="${1:?usage: update-cask.sh <version> <dmg-path>}"
DMG="${2:?usage: update-cask.sh <version> <dmg-path>}"

if [ -z "${TAP_DEPLOY_KEY:-}" ]; then
    echo "update-cask: TAP_DEPLOY_KEY unset — skipping tap bump"
    exit 0
fi

TAP_REPO="${HEALTHBAR_TAP_REPO:?set HEALTHBAR_TAP_REPO (repository variable) — see docs/RELEASING.md}"
REPO_SLUG="${HEALTHBAR_REPO_SLUG:?set HEALTHBAR_REPO_SLUG (repository variable) — see docs/RELEASING.md}"
BUNDLE_ID="${HEALTHBAR_BUNDLE_ID:?set HEALTHBAR_BUNDLE_ID (repository variable) — see docs/RELEASING.md}"

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

KEYFILE="$(mktemp)"
printf '%s\n' "$TAP_DEPLOY_KEY" > "$KEYFILE"
chmod 600 "$KEYFILE"
export GIT_SSH_COMMAND="ssh -i $KEYFILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" "$KEYFILE"' EXIT

git clone "git@github.com:${TAP_REPO}.git" "$WORK"
mkdir -p "$WORK/Casks"
sed -e "s|__VERSION__|${VERSION}|g" -e "s|__SHA256__|${SHA}|g" \
    -e "s|__REPO_SLUG__|${REPO_SLUG}|g" -e "s|__BUNDLE_ID__|${BUNDLE_ID}|g" \
    packaging/homebrew/healthbar.rb.tmpl > "$WORK/Casks/healthbar.rb"

cd "$WORK"
git add Casks/healthbar.rb
if git diff --cached --quiet; then
    echo "update-cask: cask already up to date"
    exit 0
fi
git -c user.name="healthbar-ci" -c user.email="ci@users.noreply.github.com" \
    commit -m "healthbar ${VERSION}"
git push origin HEAD:main
echo "update-cask: pushed healthbar ${VERSION} (sha ${SHA}) to ${TAP_REPO}"
