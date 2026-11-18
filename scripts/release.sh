#!/bin/bash
# Publishes a release: zip, GitHub release, and the Homebrew cask bump.
# Usage: scripts/release.sh 1.5 "Release notes"
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$1"
NOTES="${2:-}"
TAP_DIR="${TAP_DIR:-$HOME/Projects/homebrew-tap}"

# The update check compares this version with the latest release's tag.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
if ! git diff --quiet Resources/Info.plist; then
    git commit -qm "Version $VERSION" Resources/Info.plist
    git push -q
fi

scripts/package.sh
gh release create "v$VERSION" build/Start-Menu.zip --title "macOS Start Menu $VERSION" --notes "$NOTES"

SHA=$(shasum -a 256 build/Start-Menu.zip | cut -d' ' -f1)
[ -d "$TAP_DIR" ] || gh repo clone corentin-gautier/homebrew-tap "$TAP_DIR"
CASK="$TAP_DIR/Casks/macos-start-menu.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git -C "$TAP_DIR" commit -qam "macos-start-menu $VERSION"
git -C "$TAP_DIR" push -q
echo "Released $VERSION (sha256 $SHA)"
