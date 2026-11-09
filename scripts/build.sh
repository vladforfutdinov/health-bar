#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Version precedence: HEALTHBAR_VERSION env, exact git tag, git describe, 0.0.0-dev.
version_from_git() {
    git describe --tags --exact-match 2>/dev/null && return
    git describe --tags --always --dirty 2>/dev/null && return
    return 1
}
VERSION="${HEALTHBAR_VERSION:-$(version_from_git || echo 0.0.0-dev)}"
VERSION="${VERSION#v}"
SHORT="${VERSION%%-*}"   # CFBundleShortVersionString must be plain dotted numbers
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

# Release = exact version tag (CI). Dev builds get a distinct bundle id, name and .app
# filename so their UserDefaults stay separate. Override with HEALTHBAR_RELEASE=1 / HEALTHBAR_DEV=1.
if git describe --tags --exact-match >/dev/null 2>&1; then IS_RELEASE=1; else IS_RELEASE=0; fi
[ "${HEALTHBAR_RELEASE:-}" = "1" ] && IS_RELEASE=1
[ "${HEALTHBAR_DEV:-}" = "1" ] && IS_RELEASE=0

# Identity: env vars (CI repository variables) > scripts/identity.env (gitignored) > defaults.
if [ -f scripts/identity.env ]; then . scripts/identity.env; fi
HEALTHBAR_BUNDLE_ID="${HEALTHBAR_BUNDLE_ID:-com.vladforfutdinov.healthbar}"
HEALTHBAR_DISPLAY_NAME="${HEALTHBAR_DISPLAY_NAME:-HealthBar}"
HEALTHBAR_REPO_SLUG="${HEALTHBAR_REPO_SLUG:-${GITHUB_REPOSITORY:-$(git remote get-url origin 2>/dev/null \
    | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' | grep -E '^[^/]+/[^/]+$' || true)}}"
HEALTHBAR_FEED_URL="${HEALTHBAR_FEED_URL:-}"
HEALTHBAR_SU_PUBLIC_KEY="${HEALTHBAR_SU_PUBLIC_KEY:-}"

OUT="dist"
if [ "$IS_RELEASE" = "1" ]; then
    APP="$OUT/HealthBar.app";        BUNDLE_ID="$HEALTHBAR_BUNDLE_ID";     DISPLAY_NAME="$HEALTHBAR_DISPLAY_NAME"
else
    APP="$OUT/HealthBar (dev).app";  BUNDLE_ID="$HEALTHBAR_BUNDLE_ID.dev"; DISPLAY_NAME="$HEALTHBAR_DISPLAY_NAME (dev)"
fi

mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macos/Info.plist "$APP/Contents/Info.plist"
PLIST="$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :HBVersionFull $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :HBRepoSlug $HEALTHBAR_REPO_SLUG" "$PLIST"

# A feed without its key ships an updater that rejects every update; plain http can be swapped in transit.
if [ -n "$HEALTHBAR_FEED_URL" ]; then
    case "$HEALTHBAR_FEED_URL" in https://*) ;; *) echo "ERROR: HEALTHBAR_FEED_URL must be https://" >&2; exit 1 ;; esac
    if [ -z "$HEALTHBAR_SU_PUBLIC_KEY" ]; then
        echo "ERROR: HEALTHBAR_FEED_URL is set but HEALTHBAR_SU_PUBLIC_KEY is empty" >&2; exit 1
    fi
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $HEALTHBAR_FEED_URL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $HEALTHBAR_SU_PUBLIC_KEY" "$PLIST"
else
    if [ "$IS_RELEASE" = "1" ] && [ "${WITH_SPARKLE:-0}" = "1" ]; then
        echo "ERROR: release with WITH_SPARKLE=1 needs HEALTHBAR_FEED_URL and HEALTHBAR_SU_PUBLIC_KEY" >&2; exit 1
    fi
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$PLIST"
    [ "${WITH_SPARKLE:-0}" = "1" ] && echo "WARNING: WITH_SPARKLE=1 but HEALTHBAR_FEED_URL is unset — updater disabled"
fi
echo "version: $VERSION (short $SHORT, build $BUILD) — $DISPLAY_NAME [$BUNDLE_ID]"

SWIFT_FLAGS=(-O -parse-as-library)
[ "${HEALTHBAR_DEBUG:-0}" = "1" ] && SWIFT_FLAGS+=(-D DEBUG)
LINK_FLAGS=(-framework Cocoa)

# Sparkle is opt-in (WITH_SPARKLE=1, release CI). The pinned tarball is SHA-256-checked on
# every build, cached or not, and extracted fresh: what gets signed is exactly that release.
. scripts/sparkle.env
if [ "${WITH_SPARKLE:-0}" = "1" ]; then
    SPARKLE_TAR=".sparkle/Sparkle-$SPARKLE_VERSION.tar.xz"
    SPARKLE_DIR=".sparkle/$SPARKLE_VERSION"
    mkdir -p .sparkle
    if [ ! -f "$SPARKLE_TAR" ]; then
        echo "fetching Sparkle ${SPARKLE_VERSION}..."
        curl -fsSL -o "$SPARKLE_TAR.part" \
            "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
        mv "$SPARKLE_TAR.part" "$SPARKLE_TAR"
    fi
    if ! echo "$SPARKLE_SHA256  $SPARKLE_TAR" | shasum -a 256 -c - >/dev/null 2>&1; then
        echo "ERROR: $SPARKLE_TAR does not match the pinned SHA-256 — delete it to re-fetch" >&2; exit 1
    fi
    rm -rf "$SPARKLE_DIR" && mkdir -p "$SPARKLE_DIR"
    tar -xJf "$SPARKLE_TAR" -C "$SPARKLE_DIR"
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
    cp "$SPARKLE_DIR/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
    SWIFT_FLAGS+=(-D SPARKLE)
    LINK_FLAGS+=(-F "$SPARKLE_DIR" -framework Sparkle
                 -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
fi

swiftc "${SWIFT_FLAGS[@]}" -o "$APP/Contents/MacOS/HealthBar" macos/main.swift Core/*.swift "${LINK_FLAGS[@]}"

# Signing: SIGN_IDENTITY (Developer ID + Hardened Runtime + timestamp, required for notarization),
# else ad-hoc. Hardened Runtime is Developer-ID-only: its library validation rejects an embedded
# framework not signed by the same Team ID. Sparkle is signed first so the seal is valid inside-out.
sign_app() {   # $1 = identity, $2 = "yes" to harden
    local id="$1" opts=""
    [ "$2" = "yes" ] && opts="--options runtime --timestamp"
    if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --deep $opts --sign "$id" "$APP/Contents/Frameworks/Sparkle.framework"
        codesign --force $opts --sign "$id" "$APP"
    else
        codesign --force --deep $opts --sign "$id" "$APP"
    fi
}
if [ -n "${SIGN_IDENTITY:-}" ]; then
    sign_app "$SIGN_IDENTITY" "yes"
    echo "signed: Developer ID ($SIGN_IDENTITY), hardened runtime"
else
    sign_app - "no"
    echo "signed: ad-hoc"
fi

echo "Built $APP"
echo "Run:   open \"./$APP\""
