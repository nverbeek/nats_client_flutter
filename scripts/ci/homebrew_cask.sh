#!/usr/bin/env bash
# Renders the Homebrew cask for a notarized DMG, proves it installs, and
# (with --publish) pushes it to the nverbeek/homebrew-tap repo. Run by CI's
# publish-homebrew job:
#
#   scripts/ci/homebrew_cask.sh <version> <dmg path> <dmg url> [--publish]
#
# <dmg url> is what the cask downloads: the GitHub Release asset URL for a
# real release, or a file:// URL for a dry run. The install test always
# downloads through that URL, so a release run tests the real asset before
# anything is pushed. --publish needs HOMEBREW_TAP_TOKEN (a fine-grained
# PAT with contents:write on nverbeek/homebrew-tap only).
set -euo pipefail

VERSION="$1"
DMG="$2"
URL="$3"
PUBLISH="${4:-}"
CASK_NAME="nats-client-ui"
SHA256=$(shasum -a 256 "$DMG" | awk '{ print $1 }')
# On a release the URL contains the version; write it with #{version} so
# the cask reads like a hand-maintained one and future bumps only touch
# version + sha256.
VERSION_RE=$(printf '%s' "$VERSION" | sed 's/\./\\./g')
CASK_URL=$(printf '%s' "$URL" | sed "s/$VERSION_RE/#{version}/g")

CASK_FILE="${RUNNER_TEMP:?}/$CASK_NAME.rb"
cat > "$CASK_FILE" << EOF
cask "$CASK_NAME" do
  version "$VERSION"
  sha256 "$SHA256"

  url "$CASK_URL"
  name "NATS Client UI"
  desc "Desktop client for monitoring, subscribing and publishing NATS messages"
  homepage "https://github.com/nverbeek/nats_client_flutter"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "NATS Client.app"

  zap trash: "~/Library/Containers/com.nverbeek.natsClientFlutter"
end
EOF
echo "::group::Rendered cask"
cat "$CASK_FILE"
echo "::endgroup::"

echo "::group::Install test from a local tap"
# Homebrew only installs casks from a tap, so stage this one in a
# throwaway local tap rather than installing it from a file path.
brew tap-new --no-git local/nats-ci-test > /dev/null
TEST_TAP="$(brew --repository local/nats-ci-test)"
mkdir -p "$TEST_TAP/Casks"
cp "$CASK_FILE" "$TEST_TAP/Casks/"
brew install --cask "local/nats-ci-test/$CASK_NAME"
INSTALLED="/Applications/NATS Client.app"
test -d "$INSTALLED"
codesign --verify --deep --strict "$INSTALLED"
spctl -a -t exec -vv "$INSTALLED"
xcrun stapler validate "$INSTALLED"
brew uninstall --cask "local/nats-ci-test/$CASK_NAME"
brew untap local/nats-ci-test
echo "::endgroup::"

if [ "$PUBLISH" != "--publish" ]; then
  echo "Dry run: not publishing to nverbeek/homebrew-tap"
  exit 0
fi

echo "::group::Publish to nverbeek/homebrew-tap"
TAP_DIR="$RUNNER_TEMP/homebrew-tap"
git clone --quiet "https://x-access-token:${HOMEBREW_TAP_TOKEN:?}@github.com/nverbeek/homebrew-tap.git" "$TAP_DIR"
cd "$TAP_DIR"
# The tap started out empty; make sure the first commit lands on main.
if ! git rev-parse --verify --quiet HEAD > /dev/null; then
  git symbolic-ref HEAD refs/heads/main
fi
mkdir -p Casks
cp "$CASK_FILE" "Casks/$CASK_NAME.rb"
if [ ! -f README.md ]; then
  cat > README.md << 'EOF'
# nverbeek/homebrew-tap

Homebrew tap for [NATS Client UI](https://github.com/nverbeek/nats_client_flutter).

```sh
brew install --cask nverbeek/tap/nats-client-ui
```

The cask here is updated automatically by that repo's release workflow.
EOF
fi
git add -A
if git diff --cached --quiet; then
  echo "Cask already up to date"
  exit 0
fi
git -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet -m "$CASK_NAME $VERSION"
git push --quiet origin HEAD:main
echo "Published $CASK_NAME $VERSION"
echo "::endgroup::"
