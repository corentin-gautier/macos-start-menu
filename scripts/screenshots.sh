#!/bin/bash
# Regenerates the website screenshots in docs/img (glass-categories,
# glass-search, classic-list, og.jpg) with the installed app in demo mode.
# Run scripts/install.sh first so the installed app has the current code.
# The user's defaults are exported first and restored at the end.
# Needs cwebp (brew install webp) and Google Chrome (for og.jpg).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Start Menu.app"
BIN="$APP/Contents/MacOS/StartMenu"
DOMAIN=local.mac-start-menu
OUT=docs/img
TMP="$(mktemp -d)"
HELPER="$TMP/helper"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

command -v cwebp >/dev/null || { echo "cwebp missing: brew install webp" >&2; exit 1; }
[ -x "$BIN" ] || { echo "$APP not installed: run scripts/install.sh" >&2; exit 1; }

swiftc -O scripts/screenshot-helper.swift -o "$HELPER"
"$HELPER" backdrop "$TMP/backdrop.png"

quit_app() { pkill -x StartMenu 2>/dev/null || true; sleep 1; }

quit_app
defaults export "$DOMAIN" "$TMP/saved.plist"
restore() {
    quit_app
    defaults delete "$DOMAIN" 2>/dev/null || true
    defaults import "$DOMAIN" "$TMP/saved.plist"
    open "$APP"
    rm -rf "$TMP"
}
trap restore EXIT

# shot <name> <query>
shot() {
    quit_app
    STARTMENU_DEMO=1 STARTMENU_DEMO_BACKDROP="$TMP/backdrop.png" STARTMENU_DEMO_QUERY="$2" \
        "$BIN" >/dev/null 2>&1 &
    sleep 3
    "$HELPER" park-mouse   # the panel opens on the screen under the mouse
    open "$APP"            # reopen event: shows the menu
    sleep 2.5
    local rect
    rect="$("$HELPER" panel-rect)"
    screencapture -x -R"$rect" "$TMP/$1.png"
    sips -Z 1200 "$TMP/$1.png" --out "$TMP/$1-1200.png" >/dev/null
    cwebp -quiet -q 82 "$TMP/$1-1200.png" -o "$OUT/$1.webp"
    echo "$OUT/$1.webp ($rect)"
}

defaults write "$DOMAIN" showsRecentFiles -bool true
defaults write "$DOMAIN" pinned -array \
    "app:/System/Applications/Photos.app" "app:/System/Applications/Music.app" \
    "app:/System/Applications/Maps.app" "app:/System/Applications/Notes.app" \
    "folder:$HOME/Downloads" "setting:com.apple.wifi-settings-extension"
defaults write "$DOMAIN" hiddenApps -array
defaults write "$DOMAIN" style glass
defaults write "$DOMAIN" layout grid
defaults write "$DOMAIN" sortMode categories
shot glass-categories ""
shot glass-search "dis"

defaults write "$DOMAIN" style classic
defaults write "$DOMAIN" layout list
shot classic-list ""

if [ -x "$CHROME" ]; then
    "$CHROME" --headless --disable-gpu --hide-scrollbars --window-size=1200,630 \
        --screenshot="$TMP/og.png" "file://$PWD/docs/src/og.html" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 85 "$TMP/og.png" --out "$OUT/og.jpg" >/dev/null
    echo "$OUT/og.jpg"
else
    echo "warning: Google Chrome not found, og.jpg not rendered" >&2
fi
