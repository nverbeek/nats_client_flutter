# Releasing

## Cutting a release

1. Open a PR that bumps `pubspec.yaml`'s `version: X.Y.Z+1` and adds a `# X.Y.Z` section to the top of `CHANGELOG.md`. Use the subsections the existing entries use (New Features, Changes, Bug Fixes, Maintenance & Dependencies), written for users.
2. After it merges, push a lightweight tag `vX.Y.Z` on the merge commit. Only `vX.Y.Z` tags trigger a release.
3. The tag run's `release-notes` job fails unless the tag matches the pubspec version and the CHANGELOG section exists. That section becomes the GitHub release body.

Every build job is gated on the `test` job, so a red test suite blocks the release.

## What the tag run publishes

| Channel | Job | Notes |
|---|---|---|
| GitHub Release | `build-*` | Linux, web, Windows x64/arm64 zips (unsigned on purpose); macOS signed DMG + zip |
| Microsoft Store | `publish-windows-store` | MSIX via `msix` + `msstore`; Microsoft signs it during certification |
| Homebrew | `publish-homebrew` | Cask in [nverbeek/homebrew-tap](https://github.com/nverbeek/homebrew-tap) |
| Docker Hub | `build-docker` | `nverbeek/nats-client-flutter:X.Y.Z` + `latest`, amd64 + arm64 |

A queued macOS job can wait a long time for a GitHub runner. Give it about 30 minutes before cancelling, then `gh run rerun <id> --failed` reruns only the failed jobs.

## Secrets

Set them with `gh secret set NAME -R nverbeek/nats_client_flutter`. In Git Bash, prompts need `winpty`, or use PowerShell. Jobs whose secrets are missing (forks, PRs) skip publishing or fall back to unsigned builds.

| Secret | Used by | What it holds |
|---|---|---|
| `PARTNER_CENTER_TENANT_ID` / `_SELLER_ID` / `_CLIENT_ID` / `_CLIENT_SECRET` | Store | Azure AD app registration with Partner Center access |
| `MACOS_CERT_P12_BASE64` / `MACOS_CERT_PASSWORD` | macOS | Developer ID Application certificate as `.p12`, exported with `openssl pkcs12 -export -legacy` (macOS `security import` rejects OpenSSL 3's default encryption) |
| `MACOS_KEYCHAIN_PASSWORD` | macOS | Any random string, used only for the temporary keychain |
| `ASC_KEY_P8_BASE64` / `ASC_KEY_ID` / `ASC_ISSUER_ID` | macOS | App Store Connect API key (Team key, Developer role), used by `notarytool` |
| `APPLE_TEAM_ID` | none yet | Kept for reference |
| `HOMEBREW_TAP_TOKEN` | Homebrew | Fine-grained PAT, contents read/write on `nverbeek/homebrew-tap` only |
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Docker | Docker Hub push credentials |

### Renewal

- The Apple Developer Program membership renews yearly. If it lapses, notarization stops working, but already-notarized releases keep working.
- The Developer ID certificate lasts 5 years. To replace it, create an openssl CSR, upload it at developer.apple.com, then replace the two cert secrets.
- The App Store Connect API key doesn't expire unless revoked.
- Check the expiry dates of the Homebrew PAT and the Partner Center client secret when you create them.

## macOS signing and Homebrew

- `build-macos` runs `scripts/ci/macos_sign_notarize.sh`. It signs the app inside-out with the hardened runtime and `macos/Runner/Release.entitlements`, then notarizes and staples it. It then builds, signs, notarizes and staples the DMG. The app gets its own ticket because Homebrew copies it out of the DMG.
- `publish-homebrew` runs `scripts/ci/homebrew_cask.sh`. It renders the cask and installs it from a throwaway local tap, downloading through the real release URL. It checks `codesign`/`spctl`/`stapler` on the installed app, and only then pushes `Casks/nats-client-ui.rb` to the tap.
- **Testing without a release:** `gh workflow run build.yml --ref <branch>`. A manual run signs and notarizes for real, but `publish-homebrew` does a dry run: it install-tests a `file://` cask built from the DMG artifact and doesn't push.
- **Debugging:** a rejected notarization prints Apple's log in the job output. The log names the file and the reason, usually an unsigned nested binary or a missing hardened runtime. A Homebrew failure before the push leaves the tap untouched.
- Homebrew installs keep the in-app update popover on purpose (users run `brew upgrade`). Store-managed installs (MSIX, Snap) skip it via `isStoreManagedInstall()`.
