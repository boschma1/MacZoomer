# Releasing MacZoomer

This document captures the one-time and per-release steps for cutting a
signed, notarized, auto-updating MacZoomer build.

## One-time setup

### 1. GitHub repository secrets

In `Settings → Secrets and variables → Actions → New repository secret`,
add the following:

| Secret | Value | How to obtain |
| --- | --- | --- |
| `APPLE_ID` | `markus@qualified.ink` | Apple ID used for the Developer Program. |
| `APPLE_APP_PASSWORD` | `xxxx-xxxx-xxxx-xxxx` | Generate at <https://account.apple.com> → Sign-In and Security → App-Specific Passwords. Label it "MacZoomer Notary". |
| `APPLE_DEV_ID_P12_BASE64` | base64-encoded `.p12` | Export the **Developer ID Application** cert from Keychain Access (right-click → Export → .p12 with a password), then `base64 -i cert.p12 | pbcopy`. |
| `APPLE_DEV_ID_P12_PASSWORD` | password set during export | The password you typed in the Keychain Access export dialog. |
| `KEYCHAIN_PASSWORD` | any random string | Used only to create/unlock the ephemeral CI keychain. e.g. `openssl rand -hex 32`. |
| `SPARKLE_PRIVATE_KEY` | base64 EdDSA private key | Recover from your local keychain: `security find-generic-password -s "https://sparkle-project.org" -a ed25519 -w` (run on the machine where Sparkle's `generate_keys` was originally executed). |

### 2. GitHub Pages for the Sparkle appcast

In `Settings → Pages`:

1. **Source:** Deploy from a branch.
2. **Branch:** `gh-pages` / `/ (root)`.
3. Save.

The first release-workflow run creates the `gh-pages` branch and seeds it
with an `appcast.xml` containing the new release. Subsequent runs prepend
a new `<item>` and push. The published URL is
<https://boschma1.github.io/MacZoomer/appcast.xml>, which matches the
`SUFeedURL` in `Info.plist`.

### 3. Local prerequisites (only if you run `scripts/release-local.sh`)

- The **Developer ID Application: qualified.ink GmbH (5R57LQA4MP)**
  certificate installed in your login keychain.
- `notarytool` credentials stored once:
  ```sh
  xcrun notarytool store-credentials MacZoomerNotary \
    --apple-id markus@qualified.ink \
    --team-id 5R57LQA4MP \
    --password <app-specific-password>
  ```
- `brew install xcodegen`.

## Per-release flow

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
   `project.yml`.
2. Update `CHANGELOG.md` (if/when one exists) and commit.
3. Tag and push:
   ```sh
   git tag v0.5.0 -m "Release 0.5.0"
   git push origin v0.5.0
   ```
4. `.github/workflows/release.yml` runs automatically:
   - Imports the Developer ID cert into an ephemeral keychain.
   - Builds the Release configuration with hardened runtime + timestamped signature.
   - Notarizes and staples the `.app`.
   - Builds, signs, notarizes, and staples the `.dmg`.
   - Signs the DMG with the Sparkle EdDSA private key.
   - Pushes an updated `appcast.xml` to `gh-pages`.
   - Creates a draft GitHub Release with the DMG and `SHA256SUMS.txt`.
5. Review the draft release on GitHub and click **Publish**. Sparkle clients
   on macOS will pick up the new version within the next scheduled check
   (~24h by default; users can run `MacZoomer → Check for Updates…`
   immediately).

## Verifying a build locally

```sh
scripts/release-local.sh                # uses MARKETING_VERSION in project.yml
spctl --assess --type execute --verbose build/Build/Products/Release/MacZoomer.app
spctl --assess --type open --context context:primary-signature --verbose \
    artifacts/MacZoomer-*.dmg
```

Both `spctl` checks should print `source=Notarized Developer ID` and `accepted`.

## Sparkle key rotation

If you ever need to rotate the Sparkle EdDSA key pair:

1. On a trusted machine, run `bin/generate_keys` from a Sparkle release
   (`/tmp/sparkle-keys/Sparkle-2.6.4/bin/generate_keys`).
2. Copy the new public key into `project.yml` under `SUPublicEDKey`,
   commit, and ship a release **using the old key** so existing users
   pick up the new public key.
3. Update the `SPARKLE_PRIVATE_KEY` GitHub secret with the new key.
4. Subsequent releases sign with the new key.

Existing installs that haven't updated before the rotation will be stuck;
they'd need to download a fresh DMG manually.
