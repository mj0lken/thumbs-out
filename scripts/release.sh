#!/usr/bin/env bash
# Cuts a release in one go: bumps the version, runs the tests, builds and zips the app, tags and
# publishes the GitHub release, checks the published download, and updates the Homebrew cask.
#
#   scripts/release.sh 1.2.0                     # release
#   scripts/release.sh 1.2.0 --dry-run           # everything local (tests, build, zip, notes), nothing published
#   scripts/release.sh 1.2.0 --notes-file x.md   # your own release notes instead of the generated ones
#
# Expects the tap checked out next to this repo (../homebrew-tap), or TAP_DIR set.
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="mj0lken/thumbs-out"
PLIST="Resources/Info.plist"
TAP_DIR="${TAP_DIR:-$(cd .. && pwd)/homebrew-tap}"
CASK="$TAP_DIR/Casks/thumbs-out.rb"

VERSION="${1:-}"
[[ $# -gt 0 ]] && shift
DRY_RUN=false
NOTES_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --notes-file) NOTES_FILE="${2:?--notes-file needs a file}"; shift ;;
    *) echo "release: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

fail() { echo "release: $*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
# Checks that guard what gets published; a dry run only warns.
require() { if $DRY_RUN; then echo "(dry run) warning: $1"; else fail "$1"; fi }
publish() { if $DRY_RUN; then echo "(dry run) skipped: $*"; else "$@"; fi }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: scripts/release.sh X.Y.Z [--dry-run] [--notes-file FILE]"
ZIP="build/thumbs-out-$VERSION-arm64.zip"
NOTES_PATH="build/release-notes-$VERSION.md"

step "Checking the repository and tools"
[[ "$(git branch --show-current)" == "main" ]] || require "not on main"
[[ -z "$(git status --porcelain)" ]] || require "uncommitted changes; commit them first"
git fetch -q origin --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || require "HEAD isn't origin/main; pull or push first"
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then fail "v$VERSION already exists"; fi
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEWEST=$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | tail -1)
[[ "$NEWEST" == "$VERSION" && "$CURRENT" != "$VERSION" ]] || fail "$VERSION isn't newer than $CURRENT"
gh auth status >/dev/null 2>&1 || require "gh isn't signed in (gh auth login)"
[[ -f "$CASK" ]] || fail "no cask at $CASK; set TAP_DIR to the homebrew-tap checkout"
[[ -z "$(git -C "$TAP_DIR" status --porcelain)" ]] || require "the tap has uncommitted changes"
publish git -C "$TAP_DIR" pull -q --ff-only

step "Bumping $CURRENT ($BUILD) to $VERSION ($((BUILD + 1)))"
if $DRY_RUN; then trap 'git checkout -q -- "$PLIST"' EXIT; fi # A dry run leaves the version as it was.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

step "Testing"
swift test 2>&1 | tail -3

step "Building and zipping"
./scripts/build-app.sh
codesign --verify --strict build/thumbs-out.app
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/thumbs-out.app/Contents/Info.plist)" == "$VERSION" ]] \
  || fail "the built app doesn't say $VERSION"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/thumbs-out.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo "$ZIP  $SHA"

step "Writing release notes"
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES_PATH"
else
  PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
  # Conventional commit subjects since the last release, without their type prefix. Only commits
  # that change the app count: website and debug-renderer work isn't in the download.
  changes() {
    git log --no-merges --format='%s' "${PREVIOUS:+$PREVIOUS..}HEAD" \
      -- Sources Resources Package.swift ':(exclude)Sources/ThumbsOut/Debug' \
      | sed -nE "s/^$1(\([^)]*\))?: (.*)$/- \2/p"
  }
  NEW=$(changes feat)
  FIXED=$(changes fix)
  {
    echo "## What's new"
    echo "${NEW:-- Smaller improvements}"
    if [[ -n "$FIXED" ]]; then printf '\n## Fixes\n%s\n' "$FIXED"; fi
    cat <<EOF

**Requirements:** Apple Silicon Mac, macOS 15 or later.

**Install or update:** \`brew install --cask mj0lken/tap/thumbs-out\` (or \`brew upgrade --cask thumbs-out\`), or unzip, drag **thumbs-out.app** to Applications and open it. The app isn't signed with a paid Apple Developer ID yet, so the first launch of a new download is blocked: click **Done**, then go to **System Settings › Privacy & Security** and click **Open Anyway**.

SHA-256 of \`$(basename "$ZIP")\`: \`$SHA\`
EOF
  } > "$NOTES_PATH"
fi
cat "$NOTES_PATH"

step "Publishing v$VERSION"
publish git commit -q -m "chore: release $VERSION" -- "$PLIST"
publish git tag -a "v$VERSION" -m "thumbs-out $VERSION"
publish git push -q origin main "v$VERSION"
publish gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "thumbs-out $VERSION" --notes-file "$NOTES_PATH"

step "Checking the published download"
if $DRY_RUN; then
  echo "(dry run) skipped"
else
  DOWNLOAD=$(mktemp -d)
  curl -fsSL -o "$DOWNLOAD/release.zip" "https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")"
  [[ "$(shasum -a 256 "$DOWNLOAD/release.zip" | cut -d' ' -f1)" == "$SHA" ]] || fail "the published zip doesn't match the local one"
  echo "matches $SHA"
fi

step "Updating the Homebrew cask"
UPDATED=$(mktemp)
sed -E -e "s/^  version \".*\"$/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"$/  sha256 \"$SHA\"/" "$CASK" > "$UPDATED"
diff -u "$CASK" "$UPDATED" || true
if $DRY_RUN; then
  echo "(dry run) cask left as it was"
else
  cp "$UPDATED" "$CASK"
  brew style "$CASK"
  git -C "$TAP_DIR" commit -q -m "thumbs-out $VERSION" -- Casks/thumbs-out.rb
  git -C "$TAP_DIR" push -q
fi

step "Done"
echo "Release:  https://github.com/$REPO/releases/tag/v$VERSION"
echo "Homebrew: brew upgrade --cask thumbs-out (after brew update)"
$DRY_RUN && echo "This was a dry run: nothing was committed, tagged, published or pushed."
exit 0
