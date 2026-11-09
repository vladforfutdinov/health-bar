# Releasing HealthBar

A release is a git tag `vX.Y.Z`. Pushing it runs `.github/workflows/build.yml`: `swift test`, build, Developer ID signing (Hardened Runtime), notarization, stapling, a GitHub Release with `HealthBar.dmg` + `HealthBar.zip`, the Sparkle appcast on `gh-pages`, and the Homebrew cask bump.

Manual `workflow_dispatch` runs without `release` build ad-hoc, skip notarization and need no secrets; the result is an Actions artifact. Pushes to `main` and PRs run only the test job.

## One-time: repository secrets

Settings, Secrets and variables, Actions, **Secrets**.

### Developer ID certificate

1. Create a **Developer ID Application** certificate (Xcode or developer.apple.com); keep its private key in the login keychain.
2. Export it from Keychain Access as `.p12` with a password.
3. `base64 -i DeveloperID.p12 | pbcopy`
   - `DEVELOPER_ID_CERT_P12_BASE64`: that base64
   - `DEVELOPER_ID_CERT_PASSWORD`: the export password

### App Store Connect API key (notarytool)

1. App Store Connect, Users and Access, Integrations: generate a key with the **Developer** role; download the `.p8` (once).
2. `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy`
   - `AC_API_KEY_ID`: Key ID
   - `AC_API_ISSUER_ID`: Issuer ID (UUID)
   - `AC_API_KEY_P8_BASE64`: that base64

### Sparkle EdDSA key

Generate a key pair dedicated to HealthBar (never reuse another app's). Installed apps accept only updates signed with the public key they embed, so losing or replacing the key strands existing installs.

```sh
WITH_SPARKLE=1 HEALTHBAR_FEED_URL=https://healthbar.forfutdinov.com/appcast.xml HEALTHBAR_SU_PUBLIC_KEY=x ./scripts/build.sh   # fetches the Sparkle tools into .sparkle/
.sparkle/*/bin/generate_keys -p                  # keychain account "ed25519": creates the pair, prints the PUBLIC key
.sparkle/*/bin/generate_keys -x sparkle_private.key   # exports the private key; the file contents are the secret
```

- Variable `HEALTHBAR_SU_PUBLIC_KEY`: the public key (also in `scripts/identity.env` for local Sparkle builds).
- Secret `SPARKLE_ED_PRIVATE_KEY`: contents of `sparkle_private.key`. Delete the file afterwards.

### Homebrew tap

Create the public repo `vladforfutdinov/homebrew-healthbar` and add a write **deploy key** to it; the private key is the secret `TAP_DEPLOY_KEY`. CI renders `packaging/homebrew/healthbar.rb.tmpl` (version + DMG sha256) into `Casks/healthbar.rb` and pushes it. If `TAP_DEPLOY_KEY` is unset the tap bump is skipped. Users install with:

```sh
brew install --cask vladforfutdinov/healthbar/healthbar
```

## Repository variables

Settings, Secrets and variables, Actions, **Variables** (public values):

| Variable | Value |
|---|---|
| `HEALTHBAR_BUNDLE_ID` | `com.vladforfutdinov.healthbar` (dev builds append `.dev`) |
| `HEALTHBAR_DISPLAY_NAME` | `HealthBar` |
| `HEALTHBAR_REPO_SLUG` | `vladforfutdinov/health-bar` (falls back to the building repo) |
| `HEALTHBAR_FEED_URL` | `https://healthbar.forfutdinov.com/appcast.xml` |
| `HEALTHBAR_SU_PUBLIC_KEY` | Sparkle public key from above |
| `HEALTHBAR_TAP_REPO` | `vladforfutdinov/homebrew-healthbar` |

`build.sh` fails a Sparkle release build when the feed URL or key is missing. For local builds with the same identity copy `scripts/identity.env.example` to `scripts/identity.env` (gitignored); environment variables win over it.

## Appcast hosting

The `gh-pages` branch holds `appcast.xml`; CI creates the branch on the first release and only touches `appcast.xml`. Serve `gh-pages` at `https://healthbar.forfutdinov.com/` (a static host connected to the repo, for example Cloudflare Pages with production branch `gh-pages`, no build command, output `/`; or GitHub Pages with a custom domain). After publishing, CI waits up to 10 minutes for the feed to list the new version and fails the release otherwise. The appcast and the cask follow only the latest release.

## Release notes

Optional `docs/release-notes/vX.Y.Z.md`, committed before the tag, is prepended to the GitHub Release body and rendered through the GitHub `/markdown` API into `HealthBar.html`, which `generate_appcast` embeds as the item description shown in the Sparkle update window. No file: auto-generated notes only.

## App icon

The build looks for `Resources/AppIcon.icns`; if present it is copied into the bundle and `CFBundleIconFile` is set, otherwise the app ships without an icon. Add the file to get one.

## Cutting a release

```sh
git tag vX.Y.Z
git push origin vX.Y.Z
```

Watch: `gh run watch`. Verify: `gh release view vX.Y.Z`. Rebuild an existing release from its tag (files replaced, notes kept):

```sh
gh workflow run build.yml --ref main -f release=vX.Y.Z
```

## Local signed build (optional)

```sh
SIGN_IDENTITY="Developer ID Application: NAME (TEAMID)" ./scripts/build.sh
ditto -c -k --keepParent dist/HealthBar.app notarize.zip
AC_API_KEY_PATH=AuthKey.p8 AC_API_KEY_ID=... AC_API_ISSUER_ID=... ./scripts/notarize.sh notarize.zip dist/HealthBar.app
./scripts/make-dmg.sh
```

Without `SIGN_IDENTITY` the app is ad-hoc signed: fine for development, not for distribution. `./scripts/build.sh` alone builds `dist/HealthBar (dev).app`; `HEALTHBAR_RELEASE=1` builds `dist/HealthBar.app`.
